/** Криптографические примитивы на Web Crypto — то же API есть в Workers и Node. */

const encoder = new TextEncoder();

export function toHex(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return Array.from(view, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function base64url(bytes: Uint8Array): string {
  // Кусками, а не по байту: снимки бэкапа — сотни килобайт.
  let binary = "";
  for (let start = 0; start < bytes.length; start += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(start, start + 0x8000));
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64urlDecode(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/")
    + "=".repeat((4 - (text.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

export async function sha256Hex(text: string): Promise<string> {
  return toHex(await crypto.subtle.digest("SHA-256", encoder.encode(text)));
}

export async function hmacHex(secret: string, text: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(text)));
}

export function defaultRandomBytes(count: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(count));
}

// MARK: - Подписи и шифрование

/** JWT с подписью ES256 — так подписываются запросы к Apple (App Store и вход). */
export async function es256JWT(
  pem: string, header: Record<string, unknown>, payload: Record<string, unknown>,
): Promise<string> {
  const signingInput = base64url(encoder.encode(JSON.stringify({ alg: "ES256", ...header }))) + "."
    + base64url(encoder.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  // Web Crypto отдаёт подпись ECDSA сразу в виде r‖s — ровно как требует JWS.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return signingInput + "." + base64url(new Uint8Array(signature));
}

export function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const bytes = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

/**
 * Ключ AES-GCM, выведенный из секрета и назначения. Отдельного секрета не
 * заводим: чем меньше секретов, тем меньше шансов потерять один из них.
 * Назначение входит в вывод, чтобы один секрет не служил двум целям.
 */
async function aesKey(secret: string, purpose: string): Promise<CryptoKey> {
  const raw = await crypto.subtle.digest("SHA-256", encoder.encode(`${purpose}|${secret}`));
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Шифрование с аутентификацией: nonce (12 байт) ‖ шифротекст, в base64url. */
export async function seal(
  secret: string, purpose: string, plaintext: string, randomBytes: (count: number) => Uint8Array,
): Promise<string> {
  return base64url(await sealBytes(secret, purpose, encoder.encode(plaintext), randomBytes));
}

/** Обратное к `seal`. Подменённый или чужой шифротекст — исключение. */
export async function open(secret: string, purpose: string, sealed: string): Promise<string> {
  return new TextDecoder().decode(await openBytes(secret, purpose, base64urlDecode(sealed)));
}

/** То же для байтов: снимки бэкапа — сжатые данные, не текст. */
export async function sealBytes(
  secret: string, purpose: string, plaintext: Uint8Array, randomBytes: (count: number) => Uint8Array,
): Promise<Uint8Array> {
  const iv = randomBytes(12);
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv }, await aesKey(secret, purpose), plaintext));
  const out = new Uint8Array(iv.length + ciphertext.length);
  out.set(iv);
  out.set(ciphertext, iv.length);
  return out;
}

export async function openBytes(secret: string, purpose: string, sealed: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: sealed.slice(0, 12) }, await aesKey(secret, purpose), sealed.slice(12)));
}

/** Алфавит Crockford: без I, L, O и U — их путают с 1, 0 и V. */
export const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** Случайная строка Crockford: 5 бит на символ, без перекоса по модулю. */
export function crockford(randomBytes: (count: number) => Uint8Array, length: number): string {
  let out = "";
  while (out.length < length) {
    for (const byte of randomBytes(length)) {
      // 256 делится на 32 без остатка: младшие 5 бит равномерны.
      out += CROCKFORD[byte & 31];
      if (out.length === length) break;
    }
  }
  return out;
}
