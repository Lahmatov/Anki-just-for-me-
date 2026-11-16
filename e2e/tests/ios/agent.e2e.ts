import { describe, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// Агентские шаги на симуляторе: агент идёт к цели сам, как человек, который
// не знает id элементов; итог проверяется точно. Нужен вход Claude Code
// (CLAUDE_CODE_OAUTH_TOKEN в CI); без него CI исключает тег `agent`.
describe('agent on ios', { platforms: ['ios'], tags: ['agent'] }, () => {
  test('finds the Terms of Use from the Today screen', async ({ app, agent, screen }) => {
    await app.open();
    await screen.getByTestId('tab.today').waitFor({ state: 'visible', timeout: 20_000 });

    await agent.act('open the Terms of Use, which live on the Profile screen under Settings');

    await expect(screen.getByText('Recap — Terms of Use')).toBeVisible({ timeout: 15_000 });
  });

  test('a study session shows a flashcard to recall', async ({ app, agent, screen }) => {
    await app.open();
    await screen.getByTestId('today.starter').tap({ timeout: 20_000 });
    await screen.getByTestId('today.study').tap({ timeout: 15_000 });
    await screen.getByTestId('session.progress').waitFor({ state: 'visible', timeout: 15_000 });

    await agent.assert('a flashcard is on screen asking to recall an English word or phrase');
  });
});
