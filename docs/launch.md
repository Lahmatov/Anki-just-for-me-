# Запуск Recap: чек-лист

_Октябрь 2026. Отмечай `[x]` по мере выполнения. Код готов; ниже — то, что
делается руками в аккаунтах. Подробности — в ссылках на документы._

**Короткий путь к первому пользователю:** раздел 2 (сервер) → раздел 3
(Apple Developer и TestFlight) → приложение 3–5 знакомым → обращения → выпуск.

## 1. Сейчас, бесплатно

- [ ] Поставить свежую сборку на свой iPhone и пройти ручной список
      (docs/next-steps.md, раздел 1): микрофон, озвучка, фото урока, тёмная
      тема, крупный шрифт, без сети.
- [ ] Вписать данные продавца в `project.yml` вместо `CHANGE-ME`:
  - [ ] `RecapSellerName` — имя или фирма;
  - [ ] `RecapSellerAddress` — адрес в Португалии;
  - [ ] `RecapContactEmail` — почта поддержки (лучше отдельный ящик).

## 2. Сервер (docs/backend.md, docs/server-updates.md)

- [ ] Аккаунт Cloudflare, `npx wrangler login`.
- [ ] Создать базы и хранилище (в папке `backend`):
  - [ ] `npx wrangler d1 create recap`
  - [ ] `npx wrangler d1 create recap-staging`
  - [ ] `npx wrangler r2 bucket create recap-backups`
  - [ ] вписать оба id баз в `wrangler.toml` и раскомментировать блок R2
        (или прислать id — впишу сам).
- [ ] Секреты: `npx wrangler secret put ИМЯ` — список в docs/backend.md
      (ключ Anthropic, перец промокодов и остальные).
- [ ] GitHub → Settings → Environments:
  - [ ] окружения `staging` и `production`, у `production` — обязательное
        подтверждение;
  - [ ] секреты `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`;
  - [ ] переменная `RECAP_URL` — адрес сервера в каждом окружении.
- [ ] Actions → **Deploy server** → staging, проверить; затем production.
- [ ] Вписать адреса серверов в `RECAP_BACKEND_URL` в `project.yml` (Debug — staging, Release — production) (или прислать).
- [ ] По желанию — почта об обращениях: Email Routing на своём домене
      (docs/support.md, раздел «Почта»).

## 3. Apple

- [ ] Apple Developer Program (99 $ в год).
- [ ] App Store Connect:
  - [ ] приложение с Bundle ID `com.lahmatov.ajfm`;
  - [ ] подписки «месяц» и «год» с идентификаторами из `backend/wrangler.toml`
        (`SUBSCRIPTION_PRODUCTS`);
  - [ ] данные продавца для DSA — те же, что в разделе 1;
  - [ ] ключ In-App Purchase и ключ Sign in with Apple → секретами на сервер.
- [ ] Включить вход через Apple в `Config/Signing.xcconfig`.
- [ ] Ключ App Store Connect API (Users and Access → Integrations → Keys,
      роль App Manager) → секреты репозитория `ASC_KEY_ID`, `ASC_ISSUER_ID`,
      `ASC_KEY_P8` (содержимое файла .p8). Команда подписи уже
      в `Config/Signing.xcconfig`.
- [ ] Actions → **Release to TestFlight** → версия (например, 1.0): сборка уходит
      в TestFlight сама, номер сборки — номер прогона.
- [ ] TestFlight: сборка себе и 3–5 знакомым; проверить покупку в песочнице,
      вход, выход, удаление аккаунта.

## 4. Юридическое и деньги (Португалия)

- [ ] Спросить бухгалтера (contabilista) про открытие деятельности
      (atividade aberta) для продажи подписок.
- [ ] Пробежать docs/security.md: перед выпуском — `npm audit` в `backend/`.
- [ ] Перечитать политику и условия (docs/legal) с подставленными данными
      продавца — внутри приложения: «Профиль → Документы».
- [ ] Держать под рукой docs/gdpr.md: запросы людей — месяц, утечка — CNPD
      за 72 часа. Для США — docs/us-privacy.md (тот же порядок, плюс прокурор
      Калифорнии при утечке у 500+ жителей).
- [ ] Проверка возраста (Техас): в песочнице Apple тестовыми Apple ID 12, 15
      и 25 лет — заслонка, подросток, взрослый (docs/us-privacy.md, раздел 3).
- [ ] Поставить лимиты расходов: Anthropic (месячный лимит в консоли),
      Cloudflare (уведомления о счёте).

## 5. Выпуск

- [ ] Скриншоты: Actions → Devices → артефакты (iPhone и iPad, ru/pt/en).
- [ ] Описание в App Store на ru/pt/en — готово в `fastlane/metadata`
      (название, подзаголовок, описание, ключевые слова); скопировать
      в App Store Connect или поправить там.
- [ ] Возрастной рейтинг, категория «Образование», ссылка на политику.
- [ ] Отправить на проверку Apple (обычно 1–3 дня).

## 6. После выпуска — постоянно

- [ ] Раз в пару дней: `npm run support` — ответить на обращения
      (шаблоны — docs/support.md).
- [ ] Обновления сервера — только кнопкой Deploy, сначала staging.
      Горит — `DISABLED_FEATURES` или откат (docs/server-updates.md).
- [ ] Раз в месяц: частые вопросы из обращений — в «Помощь»; расходы
      Anthropic и Cloudflare.
- [ ] Аналитика PostHog — когда решишь: согласие, сервер в ЕС, без записи
      сессий по умолчанию (docs/gdpr.md, раздел «Обработчики»).
- [ ] Android — тот же сервер; начать, когда iOS устоится.
