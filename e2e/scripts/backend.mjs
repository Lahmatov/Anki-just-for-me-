#!/usr/bin/env node
// Сервер Recap для e2e: настоящий Worker в локальном workerd (wrangler dev),
// база D1 — локальный SQLite, каждый прогон — с нуля и со всеми миграциями.
// Запускает его e2e (`app.command` в e2e.config.ts) и сам же останавливает.
//
//   node scripts/backend.mjs <порт>
//
// Секреты — заглушки: модель не вызывается (ключ Anthropic не настоящий),
// перец промокодов локальный. Настоящие секреты сюда не попадают никогда.
import { spawn, spawnSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const backend = join(here, '..', '..', 'backend');
const state = join(here, '..', '.wrangler-e2e');
const wrangler = join(here, '..', 'node_modules', 'wrangler', 'bin', 'wrangler.js');
const port = process.argv[2] ?? '8787';
const env = { ...process.env, WRANGLER_SEND_METRICS: 'false', CI: process.env.CI ?? '' };

rmSync(state, { recursive: true, force: true });
const migrate = spawnSync(process.execPath,
  [wrangler, 'd1', 'migrations', 'apply', 'recap', '--local', '--persist-to', state],
  { cwd: backend, env, stdio: 'inherit' });
if (migrate.status !== 0) process.exit(migrate.status ?? 1);

const server = spawn(process.execPath, [
  wrangler, 'dev', '--local', '--ip', '127.0.0.1', '--port', port, '--persist-to', state,
  '--show-interactive-dev-session=false',
  '--var', 'PROMO_PEPPER:e2e-local-pepper-0123456789abcdef',
  '--var', 'ANTHROPIC_API_KEY:sk-e2e-not-a-real-key',
], { cwd: backend, env, stdio: 'inherit' });

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.kill(signal));
}
server.on('exit', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
