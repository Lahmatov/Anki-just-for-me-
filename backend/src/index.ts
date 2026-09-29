import { handle } from "./app";
import { anthropicClaude } from "./claude";
import { defaultRandomBytes } from "./crypto";
import type { Env } from "./env";
import { purge } from "./retention";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, {
      claude: anthropicClaude(env.ANTHROPIC_API_KEY, env.MODEL),
      fetch: (input, init) => fetch(input, init),
      now: () => Math.floor(Date.now() / 1000),
      randomBytes: defaultRandomBytes,
    });
  },

  /** Ночная чистка по срокам хранения — см. retention.ts. */
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(purge(env.DB, Math.floor(Date.now() / 1000)).then((report) => {
      console.log("purge", JSON.stringify(report));
    }));
  },
} satisfies ExportedHandler<Env>;
