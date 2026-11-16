import { describe, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// Главный путь: пустая база → стартовый набор → занятие.
describe('study', { platforms: ['ios'] }, () => {
  test('the starter deck leads to a study session', async ({ app, screen }) => {
    await app.open();
    await screen.getByTestId('today.starter').tap({ timeout: 20_000 });
    await screen.getByTestId('today.study').waitFor({ state: 'visible', timeout: 15_000 });

    await screen.getByTestId('today.study').tap();

    await expect(screen.getByTestId('session.progress')).toBeVisible({ timeout: 15_000 });
    // В сессии панель вкладок спрятана, чтобы не отъедать место у карточки.
    await expect(screen.getByTestId('tab.today')).toBeHidden();
  });
});
