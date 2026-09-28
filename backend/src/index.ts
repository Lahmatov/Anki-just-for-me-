import { handle } from "./app";
import { anthropicClaude } from "./claude";
import { defaultRandomBytes } from "./crypto";
import type { Env } from "./env";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, {
      claude: anthropicClaude(env.ANTHROPIC_API_KEY, env.MODEL),
      fetch: (input, init) => fetch(input, init),
      now: () => Math.floor(Date.now() / 1000),
      randomBytes: defaultRandomBytes,
    });
  },
} satisfies ExportedHandler<Env>;
