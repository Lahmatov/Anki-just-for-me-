import { makeDB } from "./d1";
import type { Deps, Env } from "../src/env";
import type { ClaudeCall, ClaudeLike, ClaudeResult } from "../src/claude";
import { handle } from "../src/app";
import { codeHash, normalizeCode } from "../src/promo";
import { defaultRandomBytes } from "../src/crypto";

export const PEPPER = "test-pepper-0123456789abcdef0123456789abcdef";

export class FakeClaude implements ClaudeLike {
  calls: ClaudeCall[] = [];
  reply: () => ClaudeResult = () => ({
    text: JSON.stringify({ notes: [
      { term: "hang out", translation: "тусоваться", ipa: "/hæŋ aʊt/", partOfSpeech: "phrasal verb",
        example: "We hang out here.", exampleTranslation: "Мы тут тусуемся.",
        cloze: "We ___ ___ here.", note: "" },
    ] }),
    inputTokens: 1_000, outputTokens: 500,
  });
  /** Задержка ответа — чтобы параллельные запросы действительно пересеклись. */
  delayMs = 0;
  async complete(call: ClaudeCall) {
    this.calls.push(call);
    if (this.delayMs) await new Promise((resolve) => setTimeout(resolve, this.delayMs));
    return this.reply();
  }
}

/** Сеть: TVMaze и App Store отвечают тем, что задано в тесте. */
export function fakeFetch(routes: Record<string, () => Response>): typeof fetch {
  return (async (input: RequestInfo | URL) => {
    const url = String(input);
    for (const [prefix, respond] of Object.entries(routes)) {
      if (url.startsWith(prefix)) return respond();
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;
}

export const TVMAZE = {
  "https://api.tvmaze.com/shows/431/episodebynumber": () =>
    Response.json({ name: "The One with the Thumb", summary: "<p>Phoebe finds a thumb.</p>" }),
  "https://api.tvmaze.com/shows/431": () => Response.json({ name: "Friends" }),
};

export function makeWorld(options: { routes?: Record<string, () => Response> } = {}) {
  const db = makeDB();
  const claude = new FakeClaude();
  let clock = 1_800_000_000;
  const env: Env = {
    DB: db, ANTHROPIC_API_KEY: "sk-test", PROMO_PEPPER: PEPPER,
    BUNDLE_ID: "com.lahmatov.ajfm", MODEL: "claude-haiku-4-5",
    SUBSCRIPTION_UNITS: "2000000", PROMO_UNITS: "100000", MAX_DEVICES_PER_SUBSCRIPTION: "2",
    SUBSCRIPTION_PRODUCTS: "com.lahmatov.ajfm.plus.monthly",
  };
  const deps: Deps = {
    claude,
    fetch: fakeFetch({ ...TVMAZE, ...(options.routes ?? {}) }),
    now: () => clock,
    randomBytes: defaultRandomBytes,
  };

  async function call(method: string, path: string, body?: unknown, token?: string, ip = "1.2.3.4") {
    const headers: Record<string, string> = { "cf-connecting-ip": ip };
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    const response = await handle(new Request("https://api.test" + path, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, deps);
    return { status: response.status, body: await response.json() as Record<string, any> };
  }

  async function device() {
    const response = await call("POST", "/v1/devices");
    return response.body.token as string;
  }

  async function addPromo(code: string, days = 30, units = 100_000) {
    const hash = await codeHash(PEPPER, normalizeCode(code)!);
    db.raw.prepare(
      "INSERT INTO promo_codes (hash, batch, days, units, created_at) VALUES (?, 'test', ?, ?, 0)",
    ).run(hash, days, units);
  }

  return {
    db, env, deps, claude, call, device, addPromo,
    advance: (seconds: number) => { clock += seconds; },
    now: () => clock,
  };
}

export const CODE = "RECAP-ABCD-EFGH-JKMN-PQRS";

export const DECK_REQUEST = {
  showId: 431, season: 1, episode: 3, language: "ru", level: "B1", wordCount: 20,
  knownTerms: ["hello"],
};
