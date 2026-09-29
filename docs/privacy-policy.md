# Recap — Privacy Policy

_Last updated: 28 September 2026_

Recap is a flashcard app for learning American English from TV shows. It is built
by one person and has no accounts, no ads, no analytics and no tracking.

## What stays on your phone

Everything the app keeps is stored on your device only:

- words, cards, review history and learning progress;
- retellings and their reviews;
- goals, rewards and settings;
- API keys and the cloud connection string (in the iOS Keychain).

Voice recordings used for pronunciation and retelling are not saved. Only the
recognized text is used. Speech recognition runs on the device when iOS supports
it; otherwise Apple's speech service processes the audio under
[Apple's privacy policy](https://www.apple.com/legal/privacy/).

## What leaves your phone, and only when you ask

| Service | When | What is sent |
|---|---|---|
| **Anthropic (Claude API)** | You ask for a deck or a retelling review, after you allow it | Your request text, attached subtitles, the retelling text and a list of words you already have. Sent with **your own** API key. See [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy). |
| **Recap server** (only with Recap Plus or a promo code) | You ask for words or chat about an episode | A random device ID, the show/season/episode number, your language and level, the words you already have, attached subtitles and chat lines. The server forwards the text to Anthropic and does **not** store it; it keeps only the device ID, your access status, the subscription transaction ID (to check it with Apple) and how much of the monthly allowance was used. |
| **Neon** (optional) | Once a day, only if you connected **your own** Neon database | A copy of your learning database. |
| **TVMaze** | You make a deck for a TV show | The show name, season and episode number — to find the poster and episode title. |

Apart from the Recap server described above, the developer never receives any of
this data. Nothing is sold or shared for advertising.

## Deleting your data

Settings → Privacy and data deletion → **Delete all data** removes everything the
app stored on the phone, the device record on the Recap server, and, if you choose,
the backup copies in your Neon database. A subscription itself belongs to your Apple ID
and is managed in Apple's settings.
Deleting the app also deletes all local data.

## Children

The app is not directed at children under 13.

## Contact

Questions: CONTACT_EMAIL (replace before publishing)

---

# Recap — политика конфиденциальности

Recap — приложение с карточками для изучения американского английского по
сериалам. Аккаунтов, рекламы, аналитики и трекинга нет.

**На телефоне** хранится всё: слова, карточки, история повторов, пересказы, цели,
настройки; ключи API и строка подключения к облаку — в Keychain. Записи голоса
не сохраняются, используется только распознанный текст.

**С телефона уходит** только по твоему действию:

- в **Anthropic (Claude)** — текст запроса, субтитры, текст пересказа и список уже
  известных слов, когда ты просишь набор или разбор и разрешил отправку; по твоему ключу;
- на **сервер Recap** — только с подпиской или промокодом: случайный номер устройства,
  номер серии, язык, уровень, уже известные слова, субтитры и реплики разговора.
  Сервер передаёт текст в Anthropic и не хранит его; у себя держит только номер
  устройства, статус доступа, номер транзакции подписки и расход лимита;
- в **Neon** — копия базы раз в сутки, если ты подключил свою базу;
- в **TVMaze** — название сериала, сезон и серия, чтобы найти постер и название серии.

Кроме сервера Recap, разработчик этих данных не получает. Ничего не продаётся и не передаётся для рекламы.

**Удалить всё:** Настройки → Конфиденциальность и удаление данных → «Удалить все
данные». Удаление приложения тоже стирает все локальные данные.

Вопросы: CONTACT_EMAIL (заменить перед публикацией)
