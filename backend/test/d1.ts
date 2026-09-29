import { DatabaseSync } from "node:sqlite";
import { readdirSync, readFileSync } from "node:fs";

/**
 * D1 поверх настоящего SQLite из Node: D1 — это SQLite, так что запросы
 * проверяются тем же движком, а не заглушкой, которая всё одобряет.
 */
class Statement {
  private args: unknown[] = [];
  constructor(private db: DatabaseSync, private sql: string) {}

  bind(...args: unknown[]) {
    this.args = args.map((value) => (value === undefined ? null : value));
    return this;
  }

  async first<T>(column?: string): Promise<T | null> {
    const row = this.db.prepare(this.sql).get(...(this.args as never[])) as Record<string, unknown> | undefined;
    if (!row) return null;
    return (column ? row[column] : { ...row }) as T;
  }

  async all<T>() {
    const rows = this.db.prepare(this.sql).all(...(this.args as never[])) as T[];
    return { results: rows.map((row) => ({ ...row })), success: true, meta: {} };
  }

  async run() {
    const info = this.db.prepare(this.sql).run(...(this.args as never[]));
    return { success: true, meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) } };
  }

  runSync() {
    return this.db.prepare(this.sql).run(...(this.args as never[]));
  }
}

export function makeDB(): D1Database & { raw: DatabaseSync } {
  const db = new DatabaseSync(":memory:");
  // Все миграции по порядку — как `wrangler d1 migrations apply`.
  const dir = new URL("../migrations/", import.meta.url);
  for (const file of readdirSync(dir).filter((name) => name.endsWith(".sql")).sort()) {
    db.exec(readFileSync(new URL(file, dir), "utf8"));
  }
  const d1 = {
    raw: db,
    prepare: (sql: string) => new Statement(db, sql),
    async batch(statements: Statement[]) {
      db.exec("BEGIN");
      try {
        // Форма результата — как у D1: число изменённых строк в meta.changes.
        const results = statements.map((statement) => {
          const info = statement.runSync();
          return { success: true, meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) } };
        });
        db.exec("COMMIT");
        return results;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
    async exec(sql: string) {
      db.exec(sql);
      return { count: 0, duration: 0 };
    },
  };
  return d1 as unknown as D1Database & { raw: DatabaseSync };
}
