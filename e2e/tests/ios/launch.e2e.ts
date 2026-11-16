import { describe, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// Запуск на симуляторе: чистая база (`-ui-testing`), сразу вкладка «Сегодня».
// Элементы — по accessibilityIdentifier: тексты на трёх языках, а id одни.
describe('launch', { platforms: ['ios'] }, () => {
  test('opens on the Today tab with every tab in the bar', async ({ app, screen }) => {
    await app.open();

    await expect(screen.getByTestId('tab.today')).toBeVisible({ timeout: 20_000 });
    await expect(screen.getByTestId('tab.decks')).toBeVisible();
    await expect(screen.getByTestId('tab.shows')).toBeVisible();
    await expect(screen.getByTestId('tab.settings')).toBeVisible();
  });
});
