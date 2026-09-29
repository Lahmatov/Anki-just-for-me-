import { describe, expect, it } from "vitest";
import { handle } from "../src/app";
import { BACKUP, splitChunks } from "../src/backups";
import { purge, RETENTION } from "../src/retention";
import { makeWorld } from "./helpers";

type World = ReturnType<typeof makeWorld>;

function payload(size: number, seed = 7): Uint8Array {
  const out = new Uint8Array(size);
  for (let index = 0; index < size; index++) out[index] = (index * 31 + seed) & 0xff;
  return out;
}

async function upload(w: World, token: string, body: Uint8Array,
                      query = "device=iPhone%20%C2%B7%20AB12&notes=120&mature=30",
                      type = "application/octet-stream") {
  const response = await handle(new Request(`https://api.test/v1/backups?${query}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": type },
    body,
  }), w.env, w.deps);
  return { status: response.status, body: await response.json() as Record<string, any> };
}

async function download(w: World, token: string, id: string) {
  const response = await handle(new Request(`https://api.test/v1/backups/${id}`, {
    headers: { authorization: `Bearer ${token}` },
  }), w.env, w.deps);
  return { status: response.status, type: response.headers.get("content-type"),
           bytes: new Uint8Array(await response.arrayBuffer()) };
}

/** Последнее зарегистрированное устройство — его номер для прямых правок базы. */
function lastDeviceId(w: World): string {
  const row = w.db.raw.prepare("SELECT id FROM devices ORDER BY rowid DESC LIMIT 1").get() as { id: string };
  return row.id;
}

/** Вход без Apple: сама проверка входа покрыта в account.test.ts. */
function linkAccount(w: World, deviceId: string, accountId = "acc-1") {
  w.db.raw.prepare(
    `INSERT OR IGNORE INTO accounts (id, apple_sub_hash, created_at, last_seen_at)
     VALUES (?, ?, ?, ?)`,
  ).run(accountId, "hash-" + accountId, w.now(), w.now());
  w.db.raw.prepare("UPDATE devices SET account_id = ? WHERE id = ?").run(accountId, deviceId);
}

describe("облачный бэкап на своём сервере", () => {
  it("снимок возвращается байт в байт", async () => {
    const w = makeWorld();
    const token = await w.device();
    const data = payload(1_500_000);
    const saved = await upload(w, token, data);
    expect(saved.status).toBe(201);
    expect(saved.body.backup).toMatchObject({ device: "iPhone · AB12", noteCount: 120,
                                              matureWords: 30, size: data.length });

    const loaded = await download(w, token, saved.body.backup.id);
    expect(loaded.status).toBe(200);
    expect(loaded.type).toBe("application/octet-stream");
    expect(Buffer.from(loaded.bytes).equals(Buffer.from(data))).toBe(true);
  });

  it("большой снимок режется на части не больше предела", async () => {
    const w = makeWorld();
    const token = await w.device();
    const data = payload(BACKUP.chunkBytes * 2 + 10);
    const saved = await upload(w, token, data);
    const rows = w.db.raw.prepare("SELECT length(data) AS size FROM backup_chunks").all() as { size: number }[];
    expect(rows).toHaveLength(3);
    // base64 и nonce — с запасом ниже предела строки D1 в 2 МБ.
    for (const row of rows) expect(row.size).toBeLessThan(1_000_000);
    expect((await download(w, token, saved.body.backup.id)).bytes.length).toBe(data.length);
  });

  it("в базе снимок зашифрован, а не лежит открытым текстом", async () => {
    const w = makeWorld();
    const token = await w.device();
    const text = new TextEncoder().encode(JSON.stringify({ term: "secret-word-hang-out" }));
    await upload(w, token, text);
    const dump = JSON.stringify(w.db.raw.prepare("SELECT * FROM backup_chunks").all());
    expect(dump).not.toContain("secret-word-hang-out");
    const encoded = Buffer.from(text).toString("base64url");
    expect(dump).not.toContain(encoded.slice(0, 16));
  });

  it("подменённая часть — ошибка, а не мусор вместо бэкапа", async () => {
    const w = makeWorld();
    const token = await w.device();
    const saved = await upload(w, token, payload(1000));
    const row = w.db.raw.prepare("SELECT data FROM backup_chunks").get() as { data: string };
    const flipped = (row.data[20] === "A" ? "B" : "A");
    w.db.raw.prepare("UPDATE backup_chunks SET data = ?")
      .run(row.data.slice(0, 20) + flipped + row.data.slice(21));
    const loaded = await download(w, token, saved.body.backup.id);
    expect(loaded.status).toBe(500);
  });

  it("потерянная часть — ошибка, а не обрезанный бэкап", async () => {
    const w = makeWorld();
    const token = await w.device();
    const saved = await upload(w, token, payload(BACKUP.chunkBytes + 5));
    w.db.raw.prepare("DELETE FROM backup_chunks WHERE seq = 1").run();
    expect((await download(w, token, saved.body.backup.id)).status).toBe(500);
  });

  it("список — новые сверху, без самих снимков", async () => {
    const w = makeWorld();
    const token = await w.device();
    const first = await upload(w, token, payload(100, 1));
    w.advance(86_400);
    const second = await upload(w, token, payload(200, 2));
    const list = await w.call("GET", "/v1/backups", undefined, token);
    expect(list.status).toBe(200);
    expect(list.body.backups.map((item: { id: string }) => item.id))
      .toEqual([second.body.backup.id, first.body.backup.id]);
    expect(list.body.backups[0]).not.toHaveProperty("data");
    expect(list.body.keep).toBe(BACKUP.keep);
    expect(list.body.signedIn).toBe(false);
  });

  it("хранятся только последние снимки — старые стираются вместе с частями", async () => {
    const w = makeWorld();
    const token = await w.device();
    const ids: string[] = [];
    for (let index = 0; index < BACKUP.keep + 2; index++) {
      ids.push((await upload(w, token, payload(100, index))).body.backup.id);
      w.advance(3_600);
    }
    const list = await w.call("GET", "/v1/backups", undefined, token);
    expect(list.body.backups).toHaveLength(BACKUP.keep);
    expect(list.body.backups.map((item: { id: string }) => item.id)).not.toContain(ids[0]);
    const chunks = w.db.raw.prepare("SELECT COUNT(*) AS n FROM backup_chunks").get() as { n: number };
    expect(chunks.n).toBe(BACKUP.keep);
  });

  it("снимки одной секунды не путаются при чистке", async () => {
    const w = makeWorld();
    const token = await w.device();
    const ids: string[] = [];
    for (let index = 0; index < BACKUP.keep + 1; index++) {
      ids.push((await upload(w, token, payload(50, index))).body.backup.id);
    }
    const list = await w.call("GET", "/v1/backups", undefined, token);
    expect(list.body.backups.map((item: { id: string }) => item.id)).toEqual(ids.slice(1).reverse());
  });

  it("чужой снимок не отдаётся и неотличим от несуществующего", async () => {
    const w = makeWorld();
    const alice = await w.device();
    const bob = await w.device();
    const saved = await upload(w, alice, payload(100));
    const stolen = await download(w, bob, saved.body.backup.id);
    const missing = await download(w, bob, "0".repeat(32));
    expect(stolen.status).toBe(404);
    expect(missing.status).toBe(404);
    expect((await w.call("GET", "/v1/backups", undefined, bob)).body.backups).toEqual([]);
  });

  it("пустой, огромный и не двоичный снимок отклоняются", async () => {
    const w = makeWorld();
    const token = await w.device();
    expect((await upload(w, token, new Uint8Array())).status).toBe(400);
    expect((await upload(w, token, payload(BACKUP.maxBytes + 1))).status).toBe(413);
    expect((await upload(w, token, payload(10), undefined, "application/json")).status).toBe(415);
    const rows = w.db.raw.prepare("SELECT COUNT(*) AS n FROM backups").get() as { n: number };
    expect(rows.n).toBe(0);
  });

  it("битое описание снимка — 400 с именем поля", async () => {
    const w = makeWorld();
    const token = await w.device();
    expect((await upload(w, token, payload(10), "notes=1&mature=1")).body.message).toBe("device");
    expect((await upload(w, token, payload(10), "device=x&notes=-1&mature=1")).body.message).toBe("notes");
    expect((await upload(w, token, payload(10), "device=x&notes=1&mature=1.5")).body.message).toBe("mature");
    expect((await upload(w, token, payload(10), `device=${"x".repeat(65)}&notes=1&mature=1`)).status)
      .toBe(400);
  });

  it("без токена — 401", async () => {
    const w = makeWorld();
    expect((await w.call("GET", "/v1/backups")).status).toBe(401);
  });

  it("отправка ограничена в сутки", async () => {
    const w = makeWorld();
    const token = await w.device();
    for (let index = 0; index < 20; index++) {
      expect((await upload(w, token, payload(10, index))).status).toBe(201);
    }
    expect((await upload(w, token, payload(10))).status).toBe(429);
  });

  it("при входе снимки телефона переходят аккаунту и видны с другого телефона", async () => {
    const w = makeWorld();
    const oldPhone = await w.device();
    const oldId = lastDeviceId(w);
    const saved = await upload(w, oldPhone, payload(300));
    linkAccount(w, oldId);
    // Первый запрос после входа — и снимок уже у аккаунта.
    expect((await w.call("GET", "/v1/backups", undefined, oldPhone)).body.signedIn).toBe(true);

    const newPhone = await w.device();
    linkAccount(w, lastDeviceId(w));
    const list = await w.call("GET", "/v1/backups", undefined, newPhone);
    expect(list.body.backups.map((item: { id: string }) => item.id)).toEqual([saved.body.backup.id]);
    expect((await download(w, newPhone, saved.body.backup.id)).bytes.length).toBe(300);
  });

  it("«Удалить копии» стирает снимки и их части", async () => {
    const w = makeWorld();
    const token = await w.device();
    await upload(w, token, payload(BACKUP.chunkBytes + 1));
    const erased = await w.call("DELETE", "/v1/backups", undefined, token);
    expect(erased.body.deleted).toBe(1);
    const left = w.db.raw.prepare(
      "SELECT (SELECT COUNT(*) FROM backups) + (SELECT COUNT(*) FROM backup_chunks) AS n").get() as { n: number };
    expect(left.n).toBe(0);
  });

  it("«Удалить все данные» уносит снимки телефона, но не аккаунта", async () => {
    const w = makeWorld();
    const lonely = await w.device();
    await upload(w, lonely, payload(100));
    const signed = await w.device();
    linkAccount(w, lastDeviceId(w));
    await upload(w, signed, payload(100));

    await w.call("DELETE", "/v1/me", undefined, lonely);
    await w.call("DELETE", "/v1/me", undefined, signed);
    const owners = w.db.raw.prepare("SELECT owner FROM backups").all() as { owner: string }[];
    expect(owners.map((row) => row.owner)).toEqual(["acc-1"]);
  });

  it("снимки попадают в выгрузку данных", async () => {
    const w = makeWorld();
    const token = await w.device();
    await upload(w, token, payload(100));
    const exported = await w.call("GET", "/v1/me/export", undefined, token);
    expect(exported.body.backups).toHaveLength(1);
    expect(exported.body.backups[0]).toMatchObject({ device: "iPhone · AB12", words: 120, bytes: 100 });
  });

  it("ночная чистка забирает снимки забытых устройств и только их", async () => {
    const w = makeWorld();
    const stale = await w.device();
    await upload(w, stale, payload(BACKUP.chunkBytes + 1));
    w.advance((RETENTION.inactiveDeviceDays + 1) * 86_400);
    const fresh = await w.device();
    await upload(w, fresh, payload(100));

    const report = await purge(w.db, w.now());
    expect(report.devices).toBe(1);
    expect(report.backups).toBe(1);
    const chunks = w.db.raw.prepare("SELECT COUNT(*) AS n FROM backup_chunks").get() as { n: number };
    expect(chunks.n).toBe(1);
    expect((await w.call("GET", "/v1/backups", undefined, fresh)).body.backups).toHaveLength(1);
  });

  it("снимки аккаунта переживают чистку, пока аккаунт жив", async () => {
    const w = makeWorld();
    const token = await w.device();
    linkAccount(w, lastDeviceId(w));
    await upload(w, token, payload(100));
    await purge(w.db, w.now());
    const rows = w.db.raw.prepare("SELECT COUNT(*) AS n FROM backups").get() as { n: number };
    expect(rows.n).toBe(1);
  });
});

describe("нарезка снимка", () => {
  it("части идут подряд и в сумме дают исходное", () => {
    const data = payload(25);
    const parts = splitChunks(data, 10);
    expect(parts.map((part) => part.length)).toEqual([10, 10, 5]);
    expect(Buffer.concat(parts.map((part) => Buffer.from(part))).equals(Buffer.from(data))).toBe(true);
  });

  it("ровно кратный размер не даёт пустой части", () => {
    expect(splitChunks(payload(20), 10).map((part) => part.length)).toEqual([10, 10]);
  });

  it("пустой снимок — ни одной части", () => {
    expect(splitChunks(new Uint8Array(), 10)).toEqual([]);
  });
});
