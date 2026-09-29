# Recap — Privacy Policy

_Last updated: 29 September 2026_

Recap is a flashcard app for learning American English from TV shows. It is built
by one person and has no accounts, no ads, no analytics and no tracking.

## Who is responsible

The controller of the personal data described here is **CONTROLLER_NAME**,
CONTROLLER_ADDRESS, Portugal. Contact: **CONTACT_EMAIL**.
_(Replace the placeholders before publishing — they must match the trader details in
App Store Connect.)_

## What stays on your phone

Everything the app keeps is stored on your device only, and the developer has no
access to it:

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
| **Anthropic (Claude API)**, with your own key | You ask for a deck or a retelling review, after you allow it | Your request text, attached subtitles, the retelling text and a list of words you already have. This goes from your phone straight to Anthropic under **your own** Anthropic account; the developer does not receive it. See [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy). |
| **Recap server** (only with Recap Plus or a promo code) | You ask for words or chat with Monchik about an episode | A random device ID, the show/season/episode number, your language and level, the words you already have, attached subtitles and chat lines. The server forwards the text to Anthropic and does **not** store it. |
| **Neon** (optional) | Once a day, only if you connected **your own** Neon database | A copy of your learning database. |
| **TVMaze** | You look up a show or make a deck for it | The show name, season and episode number — to find the poster and episode title. |

Nothing is sold or shared for advertising.

## What the Recap server keeps, why, and for how long

The server is used only by people with Recap Plus or a promo code. It does not
know your name, e-mail or Apple ID.

| Data | Why | Legal basis (GDPR) | Kept |
|---|---|---|---|
| Random device ID and a hash of its access token | To recognize your phone | Contract — Art. 6(1)(b) | Until you delete your data, or 12 months after the phone last contacted the server |
| Subscription transaction ID, product, period, allowance used | To check the subscription with Apple and apply the monthly limit | Contract — Art. 6(1)(b) | While the subscription is linked to a device; 30 days after it ends if no device is linked |
| Episodes you got words for | Chat with Monchik is allowed only about these episodes | Contract — Art. 6(1)(b) | Same as the device ID |
| Token counts per request (no content) | To see costs and detect abuse | Legitimate interest — Art. 6(1)(f) | 90 days |
| Request counters keyed by device ID or a keyed hash of the IP address | To stop abuse (rate limits, promo-code guessing) | Legitimate interest — Art. 6(1)(f) | Until the counter's window ends (at most 24 hours) |

The text of your requests, subtitles, retellings and chat lines is never stored on
the server or in its logs.

## Who processes data for us

- **Cloudflare, Inc.** hosts the Recap server and its database.
- **Anthropic, PBC** runs the Claude model that generates words and Monchik's
  replies. Under Anthropic's commercial terms, API data is not used to train models
  and is deleted after a limited period (currently up to 30 days).
- **Apple** sells the subscription, handles payment, refunds and VAT, and confirms
  the subscription status to the server. Apple is an independent controller for the
  purchase.

Cloudflare and Anthropic are based in the United States. Transfers are protected by
the European Commission's Standard Contractual Clauses in their data processing
terms and, where the provider is certified, by the EU–US Data Privacy Framework.

## Your rights

You have the right to access, correct, delete, restrict and port your data and to
object to processing based on legitimate interest.

- **Delete:** Settings → Privacy and data deletion → **Delete all data** removes
  everything the app stored on the phone, the device record on the Recap server,
  and, if you choose, the backup copies in your Neon database. Deleting the app
  also deletes all local data. A subscription belongs to your Apple ID and is
  managed and cancelled in Apple's settings.
- **Anything else:** write to CONTACT_EMAIL. Because there are no accounts, the
  server cannot tell who you are from your name or e-mail; we may ask you to send
  the request from the app so we can find your device record.

We answer within one month. You can also complain to the Portuguese data
protection authority, **CNPD** ([www.cnpd.pt](https://www.cnpd.pt)), or to the
authority in your country.

## AI

Words, retelling reviews and Monchik's replies are generated by an AI model
(Claude by Anthropic) and can contain mistakes. The app asks for your permission
before the first request to the AI, and you can withdraw it in the Privacy screen.
No decisions with legal or similarly significant effects are made automatically.

## Children

The app is not directed at children under 13. In Portugal and most of the EU,
people under 13 (or the age set by their country) need a parent's permission to
use online services that process their data.

## Security

Connections use HTTPS. The server stores access tokens and promo codes only as
cryptographic hashes and IP addresses only as keyed hashes. If a breach affecting
your data happens, we will notify the CNPD within 72 hours and tell you when the
law requires it.

## Changes

If this policy changes, the new version appears here and in the app with a new date.

---

# Recap — политика конфиденциальности

Recap — приложение с карточками для изучения американского английского по
сериалам. Аккаунтов, рекламы, аналитики и трекинга нет.

**Оператор данных:** CONTROLLER_NAME, CONTROLLER_ADDRESS, Португалия.
Связь: CONTACT_EMAIL.

**На телефоне** хранится всё: слова, карточки, история повторов, пересказы, цели,
настройки; ключи API и строка подключения к облаку — в Keychain. Записи голоса
не сохраняются, используется только распознанный текст.

**С телефона уходит** только по твоему действию:

- в **Anthropic (Claude)** — текст запроса, субтитры, текст пересказа и список уже
  известных слов, когда ты просишь набор или разбор и разрешил отправку; по твоему
  ключу, напрямую, разработчик этого не получает;
- на **сервер Recap** — только с подпиской или промокодом: случайный номер устройства,
  номер серии, язык, уровень, уже известные слова, субтитры и реплики разговора.
  Сервер передаёт текст в Anthropic и не хранит его;
- в **Neon** — копия базы раз в сутки, если ты подключил свою базу;
- в **TVMaze** — название сериала, сезон и серия, чтобы найти постер и название серии.

**Сервер Recap хранит** (основание — договор, ст. 6(1)(b) GDPR, для защиты от
злоупотреблений — законный интерес, ст. 6(1)(f)):

- номер устройства и серии, к которым получены слова, — пока не удалишь данные
  или 12 месяцев после последнего выхода на связь;
- номер транзакции подписки и расход лимита — пока подписка привязана; 30 дней
  после её окончания, если устройств нет;
- число токенов по запросам, без текста, — 90 дней;
- счётчики частоты запросов — не дольше суток.

**Обработчики:** Cloudflare (сервер), Anthropic (модель Claude; данные API не идут
на обучение), Apple (оплата, возвраты, НДС). Cloudflare и Anthropic — в США; передача
защищена стандартными договорными условиями ЕС.

**Твои права:** доступ, исправление, удаление, ограничение, перенос, возражение.
Удалить всё: Настройки → Конфиденциальность и удаление данных → «Удалить все
данные». Остальное — письмом на CONTACT_EMAIL, ответ в течение месяца. Жалоба —
в CNPD ([www.cnpd.pt](https://www.cnpd.pt)) или в орган своей страны.

**ИИ:** слова, разборы и реплики Мончика создаёт модель Claude, в них бывают
ошибки. Перед первым запросом приложение спрашивает разрешение.

Приложение не предназначено для детей младше 13 лет.
