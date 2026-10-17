import { ApiError, oneOf, optionalStr, str } from "./http";
import type { Device } from "./auth";
import type { Deps, Env } from "./env";

/**
 * Поддержка (P-72): обращение из приложения с номером и диагностикой,
 * ответ — в приложении же. Письмо владельцу уходит, если подключена
 * отправка почты (SUPPORT_MAIL); без неё обращения копятся в базе, и
 * их видно скриптом `npm run support` (docs/support.md).
 */
export const SUPPORT = {
  messageLimit: 4_000,
  contactLimit: 200,
  diagnosticsLimit: 2_000,
  /** Сколько обращений показать в приложении. */
  listLimit: 20,
} as const;

export const CATEGORIES = ["bug", "question", "subscription", "privacy", "idea"] as const;
export type Category = typeof CATEGORIES[number];

export interface Ticket {
  id: string;
  category: Category;
  message: string;
  status: "open" | "answered" | "closed";
  reply: string | null;
  createdAt: number;
  updatedAt: number;
}

interface TicketRow {
  id: string;
  category: Category;
  message: string;
  status: Ticket["status"];
  reply: string | null;
  created_at: number;
  updated_at: number;
}

/** Номер для человека: «R-7K2Q9X» — коротко, без похожих букв, диктуется по телефону. */
export function ticketNumber(bytes: Uint8Array): string {
  const alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
  let out = "";
  for (const byte of bytes.slice(0, 6)) out += alphabet[byte % alphabet.length];
  return `R-${out}`;
}

function looksLikeEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@.]+$/.test(value);
}

/** Диагностика — только то, что приложение прислало, и не больше предела. */
function diagnosticsOf(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) throw new ApiError(400, "invalid_field", "diagnostics");
  const clean: Record<string, string> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>).slice(0, 20)) {
    if (!/^[a-zA-Z]{1,32}$/.test(key) || (typeof item !== "string" && typeof item !== "number")) {
      throw new ApiError(400, "invalid_field", "diagnostics");
    }
    clean[key] = String(item).slice(0, 120);
  }
  const text = JSON.stringify(clean);
  if (text.length > SUPPORT.diagnosticsLimit) throw new ApiError(400, "invalid_field", "diagnostics");
  return text;
}

export async function createTicket(
  env: Env, deps: Deps, device: Device, body: Record<string, unknown>,
): Promise<Ticket> {
  const category = oneOf(body, "category", CATEGORIES)!;
  const message = str(body, "message", SUPPORT.messageLimit);
  const contact = optionalStr(body, "contact", SUPPORT.contactLimit);
  if (contact !== undefined && !looksLikeEmail(contact)) throw new ApiError(400, "invalid_field", "contact");
  const diagnostics = diagnosticsOf(body.diagnostics);
  const now = deps.now();
  const id = ticketNumber(deps.randomBytes(6));
  await env.DB.prepare(
    `INSERT INTO support_tickets (id, device_id, account_id, category, message, contact, diagnostics,
                                  status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?)`,
  ).bind(id, device.id, device.account_id, category, message, contact ?? null, diagnostics, now, now).run();

  const ticket: Ticket = { id, category, message, status: "open", reply: null, createdAt: now, updatedAt: now };
  // Письмо — после записи: не дошло — обращение всё равно на месте.
  if (deps.sendSupportMail && env.SUPPORT_TO) {
    deps.waitUntil?.(deps.sendSupportMail(supportMail(env, ticket, contact, diagnostics)).catch(() => {
      console.error("support mail failed", id);
    }));
  }
  return ticket;
}

/** Обращения этого телефона и, если вошёл, его аккаунта — новые сверху. */
export async function listTickets(env: Env, device: Device): Promise<Ticket[]> {
  const rows = await env.DB.prepare(
    `SELECT id, category, message, status, reply, created_at, updated_at FROM support_tickets
     WHERE device_id = ? OR (account_id IS NOT NULL AND account_id = ?)
     ORDER BY created_at DESC, rowid DESC LIMIT ${SUPPORT.listLimit}`,
  ).bind(device.id, device.account_id).all<TicketRow>();
  return rows.results.map((row) => ({
    id: row.id, category: row.category, message: row.message, status: row.status, reply: row.reply,
    createdAt: row.created_at, updatedAt: row.updated_at,
  }));
}

export interface SupportMail {
  to: string;
  subject: string;
  text: string;
  replyTo?: string;
}

function supportMail(env: Env, ticket: Ticket, contact: string | undefined, diagnostics: string | null): SupportMail {
  return {
    to: env.SUPPORT_TO!,
    subject: `[Recap ${ticket.id}] ${ticket.category}`,
    text: [ticket.message, "", "—", `Обращение: ${ticket.id}`, `Ответить: npm run support -- reply ${ticket.id}`,
           contact ? `Почта человека: ${contact}` : "Почты нет — ответ только в приложении",
           diagnostics ? `Диагностика: ${diagnostics}` : ""].join("\n"),
    ...(contact ? { replyTo: contact } : {}),
  };
}

/** Письмо в виде MIME: UTF-8 в base64 — русский текст доходит без кракозябр. */
export function mimeMessage(from: string, mail: SupportMail, messageId: string, date: Date): string {
  const encode = (text: string) => btoa(String.fromCharCode(...new TextEncoder().encode(text)));
  const body = encode(mail.text).replace(/.{1,76}/g, (line) => line + "\r\n");
  return [
    `From: Recap <${from}>`,
    `To: ${mail.to}`,
    ...(mail.replyTo ? [`Reply-To: ${mail.replyTo}`] : []),
    `Subject: =?UTF-8?B?${encode(mail.subject)}?=`,
    `Message-ID: <${messageId}@recap>`,
    `Date: ${date.toUTCString()}`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    body,
  ].join("\r\n");
}
