import { describe, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// Документы в профиле: те же файлы, что на сайте (docs/legal), читаются без сети.
describe('profile', { platforms: ['ios'] }, () => {
  test('opens the Terms of Use from the profile', async ({ app, screen }) => {
    await app.open();
    await screen.getByTestId('tab.settings').tap({ timeout: 20_000 });
    await screen.getByTestId('settings.profile').tap();
    // Список ленивый: строки ниже экрана нет, пока до неё не долистали.
    await screen.scrollUntilVisible(screen.getByTestId('docs.terms'));

    await screen.getByTestId('docs.terms').tap();

    await expect(screen.getByText('Recap — Terms of Use')).toBeVisible({ timeout: 15_000 });
  });
});
