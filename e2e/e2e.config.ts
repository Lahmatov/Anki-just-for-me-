import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';
import { mobile } from '@e2e-dev/mobile';
import { claudeCode } from '@e2e-dev/acp';

// Две цели:
//  - `api`: сервер Recap (backend/) — настоящий Worker в локальном workerd,
//    поднимается из scripts/backend.mjs на свободном порту. Браузер нужен только
//    агентским шагам (они смотрят на ответ сервера глазами); тесты API ходят fetch.
//  - `ios`: приложение на симуляторе iOS. Сборку ставит на симулятор CI
//    (или ты руками, см. .agents/skills/verify-ajfm/SKILL.md): движок ничего не
//    устанавливает. `-ui-testing` — чистая база в памяти, без заставки и
//    знакомства (App/Sources/Services/UITesting.swift); английский — чтобы
//    тексты проверялись одной строкой.
const iphone = mobile({ platform: 'ios' });

export default {
  tests: 'tests/**/*.e2e.ts',
  targets: [
    {
      name: 'api',
      engine: web(),
      app: {
        url: 'http://127.0.0.1:0',
        readyUrl: 'http://127.0.0.1:{port}/v1/health',
        command: {
          executable: 'node',
          args: ['scripts/backend.mjs', '{port}'],
          startupTimeout: 120_000,
          log: '.e2e/logs/backend.log',
        },
      },
    },
    {
      name: 'ios',
      engine: iphone,
      app: {
        bundleId: 'com.lahmatov.ajfm',
        launchArguments: ['-ui-testing', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US'],
      },
    },
  ],
  // Один симулятор — один исполнитель; сервер на прогон один.
  workers: 1,
  // Агентские шаги (agent.act / agent.assert) — на Claude Code по подписке
  // владельца: локально через вход `claude`, в CI через CLAUDE_CODE_OAUTH_TOKEN
  // (`claude setup-token`). Без входа тесты с тегом `agent` исключаются:
  // `--exclude-tag agent`.
  agents: {
    default: {
      executor: claudeCode({
        model: 'sonnet',
        system:
          'You are testing Recap, an iOS app for learning English with flashcards, and its server API. ' +
          'Verify every outcome on screen before completing a step.',
      }),
    },
  },
} satisfies E2EConfig;
