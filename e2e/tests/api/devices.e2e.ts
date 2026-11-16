import { describe, expect, test } from 'e2e';

// Сервер Recap по HTTP — так, как к нему ходит приложение: регистрация телефона,
// профиль, отказ без токена, забывание устройства. Тесты берут только `app` и
// fetch: модель не нужна. Каждый тест регистрирует своё устройство.

async function register(baseUrl: string): Promise<string> {
  const response = await fetch(`${baseUrl}/v1/devices`, { method: 'POST' });
  expect(response.status).toBe(201);
  const body = (await response.json()) as { token?: unknown };
  expect(typeof body.token).toBe('string');
  return body.token as string;
}

function me(baseUrl: string, token: string, method = 'GET') {
  return fetch(`${baseUrl}/v1/me`, { method, headers: { authorization: `Bearer ${token}` } });
}

describe('devices api', { platforms: ['web'] }, () => {
  test('health reports the database and the latest migration', async ({ app }) => {
    const response = await fetch(`${app.baseUrl}/v1/health`);

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      ok: true,
      api: 1,
      schema: expect.stringMatching(/^\d{4}_.+\.sql$/),
      backups: 'd1',
    });
  });

  test('a newly registered device has a free profile', async ({ app }) => {
    const token = await register(app.baseUrl!);

    const response = await me(app.baseUrl!, token);

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      plan: 'none',
      active: false,
      unitsLeft: 0,
      signedIn: false,
      supportCode: expect.stringMatching(/^[0-9A-F]{4}-[0-9A-F]{4}$/),
    });
  });

  test('a request with an unknown token is refused', async ({ app }) => {
    const response = await me(app.baseUrl!, 'not-a-real-token');

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'unauthorized', message: 'unauthorized' });
  });

  test('a forgotten device can no longer sign requests', async ({ app }) => {
    const token = await register(app.baseUrl!);
    const forgotten = await me(app.baseUrl!, token, 'DELETE');
    expect(forgotten.status).toBe(200);

    const after = await me(app.baseUrl!, token);

    expect(after.status).toBe(401);
  });
});
