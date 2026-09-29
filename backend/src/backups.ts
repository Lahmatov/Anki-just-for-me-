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
}

export interface BackupEntry {
  id: string;
  createdAt: number;
  device: string;
  noteCount: number;
  matureWords: number;
  size: number;
}

interface BackupRow {
  id: string;
  device_label: string;
  note_count: number;
  mature_words: number;
  size: number;
  chunks: number;
  created_at: number;
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
  const parts = splitChunks(payload);

  const statements = [
    db.prepare(
      `INSERT INTO backups (id, owner, device_label, note_count, mature_words, size, chunks, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(id, owner, meta.device, meta.noteCount, meta.matureWords, payload.length, parts.length, now),
  ];
  for (const [seq, part] of parts.entries()) {
    const sealed = await sealBytes(env.PROMO_PEPPER, `${PURPOSE}|${id}|${seq}`, part, deps.randomBytes);
    statements.push(db.prepare("INSERT INTO backup_chunks (backup_id, seq, data) VALUES (?, ?, ?)")
      .bind(id, seq, base64url(sealed)));
  }
  // Лишние — всё старше `keep` последних. rowid различает снимки одной секунды.
  const extra = `SELECT id FROM backups WHERE owner = ? ORDER BY created_at DESC, rowid DESC
                 LIMIT -1 OFFSET ${BACKUP.keep}`;
  statements.push(db.prepare(`DELETE FROM backup_chunks WHERE backup_id IN (${extra})`).bind(owner));
  statements.push(db.prepare(`DELETE FROM backups WHERE id IN (${extra})`).bind(owner));
  await db.batch(statements);

  return { id, createdAt: now, device: meta.device, noteCount: meta.noteCount,
           matureWords: meta.matureWords, size: payload.length };
}

/** Список без самих снимков: для выбора хватает даты, размера и числа слов. */
export async function listBackups(db: D1Database, owner: string): Promise<BackupEntry[]> {
  const rows = await db.prepare(
    `SELECT id, device_label, note_count, mature_words, size, chunks, created_at FROM backups
     WHERE owner = ? ORDER BY created_at DESC, rowid DESC`,
  ).bind(owner).all<BackupRow>();
  return rows.results.map(entryOf);
}

function entryOf(row: BackupRow): BackupEntry {
  return { id: row.id, createdAt: row.created_at, device: row.device_label,
           noteCount: row.note_count, matureWords: row.mature_words, size: row.size };
}

/**
 * Снимок целиком. Чужой снимок неотличим от несуществующего (404):
 * номер снимка не должен подтверждать, что такой есть у кого-то ещё.
 */
export async function loadBackup(env: Env, owner: string, id: string): Promise<Uint8Array> {
  const db = env.DB;
  const row = await db.prepare(
    `SELECT id, device_label, note_count, mature_words, size, chunks, created_at FROM backups
     WHERE id = ? AND owner = ?`,
  ).bind(id, owner).first<BackupRow>();
  if (!row) throw new ApiError(404, "backup_not_found");
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

/** Удалить все снимки владельца — часть «Удалить все данные». */
export function deleteBackupsStatements(db: D1Database, owner: string): D1PreparedStatement[] {
  return [
    db.prepare("DELETE FROM backup_chunks WHERE backup_id IN (SELECT id FROM backups WHERE owner = ?)")
      .bind(owner),
    db.prepare("DELETE FROM backups WHERE owner = ?").bind(owner),
  ];
}
