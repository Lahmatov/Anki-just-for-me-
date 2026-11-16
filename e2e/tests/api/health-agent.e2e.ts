import { describe, test } from '@e2e-dev/web';

// Агентская проверка: агент читает ответ /v1/health в браузере, как человек
// после деплоя, и судит по смыслу, а не по точной строке. Нужен вход Claude
// Code (см. e2e.config.ts); без него — `--exclude-tag agent`.
describe('health page', { platforms: ['web'], tags: ['agent'] }, () => {
  test('a person reading /v1/health sees a healthy server', async ({ app, agent }) => {
    await app.open('/v1/health');

    await agent.assert(
      'the page shows a JSON health report in which the database is ok and the schema names a database migration file',
    );
  });
});
