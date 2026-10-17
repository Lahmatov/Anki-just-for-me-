import { ApiError } from "./http";
import { base64url, base64urlDecode, openBytes, sealBytes, toHex } from "./crypto";
import type { Device } from "./auth";
import type { Deps, Env } from "./env";

/**
 * Облачный бэкап на своём сервере.
 *
 * Сервер хранит снимок как непрозрачные байты: что внутри (сжатый JSON
 * бэкапа), знает только приложение. Так формат бэкапа меняется без
 * изменений здесь, а сервер не разбирает чужие данные.
 */
export const BACKUP = {
  /** Сколько снимков хранить: неделя ежедневных копий и запас на откат. */
  keep: 7,
  /** Предел снимка после сжатия. Сжатая база в 20 тысяч слов — около мегабайта. */
  maxBytes: 8 * 1024 * 1024,
  /** Часть снимка: с запасом ниже предела строки D1 (2 МБ) даже после base64. */
  chunkBytes: 512 * 1024,
} as const;

const PURPOSE = "backup";

export interface BackupMeta {
  device: string;
  noteCount: number;
  matureWords: number;
  /** Изучаемый язык (P-67); копии хранятся и чистятся у каждого свои. */
  language: string;
}

export interface BackupEntry {
  id: string;
  createdAt: number;
  device: string;
  noteCount: number;
  matureWords: number;
  size: number;
  language: string;
}

interface BackupRow {
  id: string;
  device_label: string;
  note_count: number;
  mature_words: number;
  size: number;
  chunks: number;
  created_at: number;
  language: string;
  storage: string;
}

const COLUMNS = "id, device_label, note_count, mature_words, size, chunks, created_at, language, storage";

/** Снимок в R2 — одним объектом под своим номером. */
function blobKey(id: string): string {
  return `backups/${id}`;
}

/** Чьи снимки: аккаунта, если вошёл, — только он переживает смену телефона. */
export function ownerOf(device: Device): string {
  return device.account_id ?? device.id;
}

/**
 * Снимки, сделанные до входа, переходят аккаунту — иначе на новом телефоне
 * их не найти. Дёшево: одно обновление по индексу, и только для вошедших.
 */
export async function adoptDeviceBackups(db: D1Database, device: Device): Promise<void> {
  if (!device.account_id) return;
  await db.prepare("UPDATE backups SET owner = ? WHERE owner = ?")
    .bind(device.account_id, device.id).run();
}

export function splitChunks(bytes: Uint8Array, size: number = BACKUP.chunkBytes): Uint8Array[] {
  const chunks: Uint8Array[] = [];
  for (let start = 0; start < bytes.length; start += size) {
    chunks.push(bytes.subarray(start, start + size));
  }
  return chunks;
}

/**
 * Записать снимок: сам снимок, его части и чистку лишних — одним пакетом.
 * Оборвалось посередине — не остаётся ни половины снимка, ни лишних копий.
 */
export async function saveBackup(
  env: Env, deps: Deps, owner: string, meta: BackupMeta, payload: Uint8Array,
): Promise<BackupEntry> {
  if (payload.length === 0) throw new ApiError(400, "invalid_field", "payload");
  if (payload.length > BACKUP.maxBytes) throw new ApiError(413, "payload_too_large");
  const db = env.DB;
  const id = toHex(deps.randomBytes(16));
  const now = deps.now();
  const bucket = env.BACKUPS;

  // Лишние — всё старше `keep` последних этого же языка: ежедневные
  // португальские копии не вытесняют английские. rowid различает снимки одной секунды.
  const extra = `SELECT id FROM backups WHERE owner = ? AND language = ?
                 ORDER BY created_at DESC, rowid DESC LIMIT -1 OFFSET ${BACKUP.keep}`;
  const prune = [
    db.prepare(`DELETE FROM backup_chunks WHERE backup_id IN (${extra})`).bind(owner, meta.language),
    db.prepare(`DELETE FROM backups WHERE id IN (${extra})`).bind(owner, meta.language),
  ];

  if (bucket) {
    // Сначала объект, потом запись: запись без объекта читалась бы как
    // испорченный снимок, а объект без записи подберёт ночная чистка.
    const sealed = await sealBytes(env.PROMO_PEPPER, `${PURPOSE}|${id}|r2`, payload, deps.randomBytes);
    await bucket.put(blobKey(id), sealed);
    // Какие снимки в R2 вытеснит новый: после вставки они окажутся за `keep`.
    const evicted = await db.prepare(
      `SELECT id FROM backups WHERE owner = ? AND language = ? AND storage = 'r2'
       ORDER BY created_at DESC, rowid DESC LIMIT -1 OFFSET ${BACKUP.keep - 1}`,
    ).bind(owner, meta.language).all<{ id: string }>();
    try {
      await db.batch([
        db.prepare(
          `INSERT INTO backups (id, owner, device_label, note_count, mature_words, size, chunks,
                                created_at, language, storage)
           VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, 'r2')`,
        ).bind(id, owner, meta.device, meta.noteCount, meta.matureWords, payload.length, now, meta.language),
        ...prune,
      ]);
    } catch (error) {
      await bucket.delete(blobKey(id));
      throw error;
    }
    await deleteBackupBlobs(env, evicted.results.map((row) => row.id));
  } else {
    const parts = splitChunks(payload);
    const statements = [
      db.prepare(
        `INSERT INTO backups (id, owner, device_label, note_count, mature_words, size, chunks, created_at,
                              language)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(id, owner, meta.device, meta.noteCount, meta.matureWords, payload.length, parts.length, now,
             meta.language),
    ];
    for (const [seq, part] of parts.entries()) {
      const sealed = await sealBytes(env.PROMO_PEPPER, `${PURPOSE}|${id}|${seq}`, part, deps.randomBytes);
      statements.push(db.prepare("INSERT INTO backup_chunks (backup_id, seq, data) VALUES (?, ?, ?)")
        .bind(id, seq, base64url(sealed)));
    }
    await db.batch([...statements, ...prune]);
  }

  return { id, createdAt: now, device: meta.device, noteCount: meta.noteCount,
           matureWords: meta.matureWords, size: payload.length, language: meta.language };
}

/**
 * Список без самих снимков: для выбора хватает даты, размера и числа слов.
 * С языком — только его копии: восстанавливают в базу того же языка.
 */
export async function listBackups(db: D1Database, owner: string, language?: string): Promise<BackupEntry[]> {
  const rows = language === undefined
    ? await db.prepare(
      `SELECT ${COLUMNS} FROM backups WHERE owner = ? ORDER BY created_at DESC, rowid DESC`,
    ).bind(owner).all<BackupRow>()
    : await db.prepare(
      `SELECT ${COLUMNS} FROM backups WHERE owner = ? AND language = ?
       ORDER BY created_at DESC, rowid DESC`,
    ).bind(owner, language).all<BackupRow>();
  return rows.results.map(entryOf);
}

function entryOf(row: BackupRow): BackupEntry {
  return { id: row.id, createdAt: row.created_at, device: row.device_label,
           noteCount: row.note_count, matureWords: row.mature_words, size: row.size,
           language: row.language };
}

/**
 * Снимок целиком. Чужой снимок неотличим от несуществующего (404):
 * номер снимка не должен подтверждать, что такой есть у кого-то ещё.
 */
export async function loadBackup(env: Env, owner: string, id: string): Promise<Uint8Array> {
  const db = env.DB;
  const row = await db.prepare(`SELECT ${COLUMNS} FROM backups WHERE id = ? AND owner = ?`)
    .bind(id, owner).first<BackupRow>();
  if (!row) throw new ApiError(404, "backup_not_found");
  if (row.storage === "r2") return loadBlob(env, row);

  const chunks = await db.prepare(
    "SELECT seq, data FROM backup_chunks WHERE backup_id = ? ORDER BY seq",
  ).bind(id).all<{ seq: number; data: string }>();
  if (chunks.results.length !== row.chunks) throw new ApiError(500, "backup_damaged");

  const out = new Uint8Array(row.size);
  let offset = 0;
  for (const chunk of chunks.results) {
    let plain: Uint8Array;
    try {
      plain = await openBytes(env.PROMO_PEPPER, `${PURPOSE}|${id}|${chunk.seq}`, base64urlDecode(chunk.data));
    } catch {
      // Сменился секрет сервера или часть подменена — отдавать нечего.
      throw new ApiError(500, "backup_damaged");
    }
    if (offset + plain.length > out.length) throw new ApiError(500, "backup_damaged");
    out.set(plain, offset);
    offset += plain.length;
  }
  if (offset !== out.length) throw new ApiError(500, "backup_damaged");
  return out;
}

async function loadBlob(env: Env, row: BackupRow): Promise<Uint8Array> {
  const object = await env.BACKUPS?.get(blobKey(row.id));
  if (!object) throw new ApiError(500, "backup_damaged");
  let plain: Uint8Array;
  try {
    plain = await openBytes(env.PROMO_PEPPER, `${PURPOSE}|${row.id}|r2`,
                            new Uint8Array(await object.arrayBuffer()));
  } catch {
    throw new ApiError(500, "backup_damaged");
  }
  if (plain.length !== row.size) throw new ApiError(500, "backup_damaged");
  return plain;
}

/** Удалить все снимки владельца — часть «Удалить все данные». */
export function deleteBackupsStatements(db: D1Database, owner: string): D1PreparedStatement[] {
  return [
    db.prepare("DELETE FROM backup_chunks WHERE backup_id IN (SELECT id FROM backups WHERE owner = ?)")
      .bind(owner),
    db.prepare("DELETE FROM backups WHERE owner = ?").bind(owner),
  ];
}

/** Номера снимков владельца в R2 — до удаления записей, чтобы стереть и объекты. */
export async function blobIdsOf(db: D1Database, owner: string): Promise<string[]> {
  const rows = await db.prepare("SELECT id FROM backups WHERE owner = ? AND storage = 'r2'")
    .bind(owner).all<{ id: string }>();
  return rows.results.map((row) => row.id);
}

/** Стереть объекты снимков из R2 сразу: «удалить мои данные» не ждёт ночи. */
export async function deleteBackupBlobs(env: Env, ids: string[]): Promise<void> {
  if (!env.BACKUPS || ids.length === 0) return;
  await env.BACKUPS.delete(ids.map(blobKey));
}

/**
 * Ночная сверка R2 с записями: объект, у которого нет записи (запись
 * удалили, а объект не стёрся из-за сбоя), удаляется. Возвращает, сколько стёрто.
 */
export async function sweepBackupBlobs(env: Env): Promise<number> {
  const bucket = env.BACKUPS;
  if (!bucket) return 0;
  let removed = 0;
  let cursor: string | undefined;
  do {
    const page = await bucket.list({ prefix: "backups/", cursor, limit: 500 });
    const ids = page.objects.map((object) => object.key.slice("backups/".length));
    if (ids.length > 0) {
      const known = new Set<string>();
      // Пачками по сотне — у D1 предел параметров в одном запросе.
      for (let start = 0; start < ids.length; start += 100) {
        const slice = ids.slice(start, start + 100);
        const rows = await env.DB.prepare(
          `SELECT id FROM backups WHERE id IN (${slice.map(() => "?").join(", ")})`,
        ).bind(...slice).all<{ id: string }>();
        for (const row of rows.results) known.add(row.id);
      }
      const orphans = ids.filter((id) => !known.has(id));
      if (orphans.length > 0) {
        await bucket.delete(orphans.map(blobKey));
        removed += orphans.length;
      }
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return removed;
}
