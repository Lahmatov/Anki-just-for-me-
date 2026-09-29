import { describe, expect, it } from "vitest";
import { CODE, DECK_REQUEST, makeWorld } from "./helpers";
import { purge, RETENTION } from "../src/retention";

const DAY = 86_400;

function count(world: ReturnType<typeof makeWorld>, table: string): number {
  return (world.db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
}

describe("ночная чистка", () => {
  it("не трогает устройство, которое выходило на связь в течение года", async () => {
    const world = makeWorld();
    await world.device();
    world.advance((RETENTION.inactiveDeviceDays - 1) * DAY);
    await purge(world.db, world.now());
    expect(count(world, "devices")).toBe(1);
  });

  it("забывает устройство, год не выходившее на связь, вместе с его сериями и расходом", async () => {
    const world = makeWorld();
    const token = await world.device();
    await world.addPromo(CODE);
    await world.call("POST", "/v1/promo/redeem", { code: CODE }, token);
    expect((await world.call("POST", "/v1/deck", DECK_REQUEST, token)).status).toBe(200);
    expect(count(world, "device_episodes")).toBe(1);
    expect(count(world, "usage_log")).toBe(1);

    world.advance((RETENTION.inactiveDeviceDays + 1) * DAY);
    const report = await purge(world.db, world.now());

    expect(report.devices).toBe(1);
    expect(count(world, "devices")).toBe(0);
    expect(count(world, "device_episodes")).toBe(0);
    expect(count(world, "usage_log")).toBe(0);
  });

  it("отвязывает погашенный промокод от забытого устройства и удаляет его доступ", async () => {
    const world = makeWorld();
    const token = await world.device();
    await world.addPromo(CODE);
    await world.call("POST", "/v1/promo/redeem", { code: CODE }, token);

    world.advance((RETENTION.inactiveDeviceDays + 1) * DAY);
    await purge(world.db, world.now());

    const row = world.db.raw.prepare("SELECT redeemed_at, redeemed_by FROM promo_codes").get() as
      { redeemed_at: number | null; redeemed_by: string | null };
    expect(row.redeemed_by).toBeNull();
    // Код остаётся погашенным: чистка не должна делать его снова годным.
    expect(row.redeemed_at).not.toBeNull();
    expect(count(world, "entitlements")).toBe(0);
  });

  it("не удаляет доступ, к которому привязано живое устройство", async () => {
    const world = makeWorld();
    const token = await world.device();
    await world.addPromo(CODE);
    await world.call("POST", "/v1/promo/redeem", { code: CODE }, token);
    world.advance(2 * DAY);
    await purge(world.db, world.now());
    expect(count(world, "entitlements")).toBe(1);
  });

  it("не удаляет только что созданный доступ без устройства", async () => {
    const world = makeWorld();
    world.db.raw.prepare(
      `INSERT INTO entitlements (id, kind, units_per_period, period_start, period_end, updated_at)
       VALUES ('fresh', 'promo', 1, ?, ?, ?)`,
    ).run(world.now(), world.now() + 30 * DAY, world.now());
    await purge(world.db, world.now() + 60);
    expect(count(world, "entitlements")).toBe(1);
  });

  it("держит подписку без устройств месяц после конца срока, потом удаляет", async () => {
    const world = makeWorld();
    const end = world.now() + 30 * DAY;
    world.db.raw.prepare(
      `INSERT INTO entitlements (id, kind, units_per_period, period_start, period_end,
         original_transaction_id, product_id, updated_at)
       VALUES ('sub', 'subscription', 1, ?, ?, '2000000123', 'p', ?)`,
    ).run(world.now(), end, world.now());

    await purge(world.db, end + (RETENTION.lapsedSubscriptionDays - 1) * DAY);
    expect(count(world, "entitlements")).toBe(1);

    await purge(world.db, end + (RETENTION.lapsedSubscriptionDays + 1) * DAY);
    expect(count(world, "entitlements")).toBe(0);
  });

  it("удаляет журнал расхода старше трёх месяцев, но не свежий", async () => {
    const world = makeWorld();
    const insert = world.db.raw.prepare(
      `INSERT INTO usage_log (entitlement_id, device_id, kind, input_tokens, output_tokens, units, created_at)
       VALUES ('e', 'd', 'deck', 1, 1, 6, ?)`,
    );
    insert.run(world.now() - (RETENTION.usageLogDays + 1) * DAY);
    insert.run(world.now() - DAY);
    const report = await purge(world.db, world.now());
    expect(report.usageLog).toBe(1);
    expect(count(world, "usage_log")).toBe(1);
  });

  it("удаляет готовые наборы для повтора старше суток, но не свежие", async () => {
    const world = makeWorld();
    const insert = world.db.raw.prepare(
      "INSERT INTO deck_requests (device_id, request_id, status, response, created_at) VALUES ('d', ?, 'done', '{}', ?)",
    );
    insert.run("old-request", world.now() - (RETENTION.deckRequestDays + 1) * DAY);
    insert.run("new-request", world.now() - 60);
    const report = await purge(world.db, world.now());
    expect(report.deckRequests).toBe(1);
    expect(count(world, "deck_requests")).toBe(1);
  });

  it("удаляет счётчики частоты с закончившимся окном и оставляет текущие", async () => {
    const world = makeWorld();
    await world.device();                         // счётчик регистраций: окно — час
    await purge(world.db, world.now() + 60);
    expect(count(world, "rate_limits")).toBe(1);
    await purge(world.db, world.now() + 3_601);
    expect(count(world, "rate_limits")).toBe(0);
  });

  it("удаляет просроченные брони и старый кеш серий", async () => {
    const world = makeWorld();
    world.db.raw.prepare(
      "INSERT INTO reservations (id, entitlement_id, amount, created_at) VALUES ('r', 'e', 10, ?)",
    ).run(world.now());
    world.db.raw.prepare(
      `INSERT INTO episode_cache (show_id, season, episode, show_name, name, summary, fetched_at)
       VALUES (1, 1, 1, 's', 'n', 'x', ?)`,
    ).run(world.now());
    await purge(world.db, world.now() + (RETENTION.episodeCacheDays + 1) * DAY);
    expect(count(world, "reservations")).toBe(0);
    expect(count(world, "episode_cache")).toBe(0);
  });

  it("на пустой базе ничего не ломает", async () => {
    const world = makeWorld();
    const report = await purge(world.db, world.now());
    expect(Object.values(report).every((value) => value === 0)).toBe(true);
  });
});
