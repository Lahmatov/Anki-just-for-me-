/**
 * Ответы и разбор запросов.
 *
 * Ошибка для клиента — код и короткое сообщение, без подробностей
 * устройства сервера: стек, SQL и ответы сторонних служб в ответ не попадают.
 */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message = code,
  ) {
    super(message);
  }
}

const SECURITY_HEADERS: Record<string, string> = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: SECURITY_HEADERS });
}

export function errorResponse(error: ApiError): Response {
  return json({ error: error.code, message: error.message }, error.status);
}

/** Тело JSON с жёстким пределом размера: огромное тело — это атака, а не запрос. */
export async function readJson(request: Request, maxBytes: number): Promise<Record<string, unknown>> {
  const type = request.headers.get("content-type") ?? "";
  if (!type.toLowerCase().startsWith("application/json")) {
    throw new ApiError(415, "unsupported_media_type");
  }
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw new ApiError(413, "payload_too_large");
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maxBytes) throw new ApiError(413, "payload_too_large");
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(buffer));
  } catch {
    throw new ApiError(400, "invalid_json");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new ApiError(400, "invalid_json");
  }
  return parsed as Record<string, unknown>;
}

// MARK: - Проверка полей. Всё, что не прошло, — 400 с именем поля.

export function int(body: Record<string, unknown>, key: string, min: number, max: number): number {
  const value = body[key];
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    throw new ApiError(400, "invalid_field", key);
  }
  return value;
}

export function str(body: Record<string, unknown>, key: string, maxLength: number): string {
  const value = body[key];
  if (typeof value !== "string" || value.trim().length === 0 || value.length > maxLength) {
    throw new ApiError(400, "invalid_field", key);
  }
  return value.trim();
}

export function optionalStr(
  body: Record<string, unknown>, key: string, maxLength: number,
): string | undefined {
  const value = body[key];
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "string" || value.length > maxLength) {
    throw new ApiError(400, "invalid_field", key);
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function oneOf<T extends string>(
  body: Record<string, unknown>, key: string, allowed: readonly T[], optional = false,
): T | undefined {
  const value = body[key];
  if (optional && (value === undefined || value === null)) return undefined;
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    throw new ApiError(400, "invalid_field", key);
  }
  return value as T;
}

export function stringList(
  body: Record<string, unknown>, key: string, maxItems: number, maxLength: number,
): string[] {
  const value = body[key];
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > maxItems) {
    throw new ApiError(400, "invalid_field", key);
  }
  return value.map((item) => {
    if (typeof item !== "string" || item.length > maxLength) {
      throw new ApiError(400, "invalid_field", key);
    }
    return item.trim();
  }).filter((item) => item.length > 0);
}
