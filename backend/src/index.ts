import { handle } from "./app";
import { anthropicClaude } from "./claude";
import { defaultRandomBytes } from "./crypto";
import type { Env } from "./env";
import { purge } from "./retention";
import { sweepBackupBlobs } from "./backups";
import { EmailMessage } from "cloudflare:email";
import { mimeMessage, type SupportMail } from "./support";

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, {
      waitUntil: (promise) => ctx.waitUntil(promise),
      claude: anthropicClaude(env.ANTHROPIC_API_KEY, env.MODEL),
      fetch: (input, init) => fetch(input, init),
      now: () => Math.floor(Date.now() / 1000),
      randomBytes: defaultRandomBytes,
      sendSupportMail: env.SUPPORT_MAIL && env.SUPPORT_FROM
        ? async (mail: SupportMail) => {
          const id = crypto.randomUUID();
          const raw = mimeMessage(env.SUPPORT_FROM!, mail, id, new Date());
          await env.SUPPORT_MAIL!.send(new EmailMessage(env.SUPPORT_FROM!, mail.to, raw));
        }
        : undefined,
    });
  },

  /** Ночная чистка по срокам хранения — см. retention.ts. */
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    // Сначала записи, потом объекты R2: сверка удаляет объекты, у которых
    // записей больше нет, — в том числе только что вычищенных.
    ctx.waitUntil(purge(env.DB, Math.floor(Date.now() / 1000)).then(async (report) => {
      const blobs = await sweepBackupBlobs(env);
      console.log("purge", JSON.stringify({ ...report, backupBlobs: blobs }));
    }));
  },
} satisfies ExportedHandler<Env>;
