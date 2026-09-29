# Recap — Privacy Policy

_Last updated: 30 September 2026_

Recap is a flashcard app for learning American English from TV shows. It is built
by one person and has no ads, no analytics and no tracking. An account is optional.

## Who is responsible

The controller of the personal data described here is **CONTROLLER_NAME**,
CONTROLLER_ADDRESS, Portugal. Contact: **CONTACT_EMAIL**.

## What stays on your phone

Everything the app keeps is stored on your device only, and the developer has no
access to it:

- words, cards, review history and learning progress;
- retellings and their reviews;
- goals, rewards and settings;
- your profile name and avatar photo;
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
| **Apple** (only if you sign in) | You tap “Sign in with Apple” | Apple confirms who you are to the Recap server. We ask only for your name, and it stays on your phone. We never ask for your e-mail. |
| **Recap server: cloud backup** (optional) | Once a day, only if you turned on Cloud backup | A compressed copy of your learning database: decks, words, progress. Encrypted on the server. |
| **TVmaze** | You look up a show or make a deck for it | The show name, season and episode number — to find the poster and episode title. |

Nothing is sold or shared for advertising.

## What the Recap server keeps, why, and for how long

The server is used only by people with Recap Plus, a promo code or an account. It
never receives your name, e-mail or photo.

| Data | Why | Legal basis (GDPR) | Kept |
|---|---|---|---|
| Random device ID and a hash of its access token | To recognize your phone | Contract — Art. 6(1)(b) | Until you delete your data, or 12 months after the phone last contacted the server |
| Account: a keyed hash of your Apple user ID | To find your account the next time you sign in | Contract — Art. 6(1)(b) | Until you delete the account, or 12 months after the last sign-in if no phone is linked |
| Account: Apple sign-in token, encrypted | Only to revoke Sign in with Apple when you delete the account | Legal obligation to Apple's platform rules; contract | Until you delete the account |
| Subscription transaction ID, product, period, allowance used | To check the subscription with Apple and apply the monthly limit | Contract — Art. 6(1)(b) | While the subscription is linked to a device or account; 30 days after it ends otherwise |
| Episodes you got words for | Chat with Monchik is allowed only about these episodes | Contract — Art. 6(1)(b) | Same as the device ID |
| Token counts per request (no content) | To see costs and detect abuse | Legitimate interest — Art. 6(1)(f) | 90 days |
| Cloud backup: compressed, encrypted copies of your learning database with date, word count and device name | To restore on a new phone | Contract — Art. 6(1)(b) | The last 7 copies; erased when you tap Delete all copies, delete your data or account, or together with the device or account under the periods above |
| Request counters keyed by device ID or a keyed hash of the IP address | To stop abuse (rate limits, promo-code guessing) | Legitimate interest — Art. 6(1)(f) | Until the counter's window ends (at most 24 hours) |

The text of your requests, subtitles, retellings and chat lines is never stored on
the server or in its logs. Cloud backup is the only exception, and only if you turned
it on.

## Who processes data for us

- **Cloudflare, Inc.** hosts the Recap server and its database.
- **Anthropic, PBC** runs the Claude model that generates words and Monchik's
  replies. Under Anthropic's commercial terms, API data is not used to train models
  and is deleted after a limited period (currently up to 30 days).
- **Apple** sells the subscription, handles payment, refunds and VAT, confirms the
  subscription status and your sign-in to the server. Apple is an independent
  controller for purchases and your Apple ID.

Cloudflare and Anthropic are based in the United States. Transfers are protected by
the European Commission's Standard Contractual Clauses in their data processing
terms and, where the provider is certified, by the EU–US Data Privacy Framework.

## Your rights

You have the right to access, correct, delete, restrict and port your data and to
object to processing based on legitimate interest.

- **See and download:** Profile → My data on the server shows everything the server
  keeps about your phone and lets you save it as a file.
- **Delete the account:** Profile → Delete account. The account is erased and Sign
  in with Apple is revoked.
- **Delete everything:** Profile → Privacy and data deletion → **Delete all data**
  removes everything on the phone, your account and device record on the server,
  and, if you choose, the cloud backup copies on the Recap server. Deleting the app also
  deletes all local data. A subscription belongs to your Apple ID and is cancelled in
  Apple's settings.
- **Anything else:** write to CONTACT_EMAIL and include the support code from
  Profile — without accounts by e-mail, it is the only way to find your record.

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
cryptographic hashes, your Apple user ID and IP addresses only as keyed hashes, and
the Apple sign-in token only encrypted. If a breach affecting your data happens, we
will notify the CNPD within 72 hours and tell you when the law requires it.

## Changes

If this policy changes, the new version appears here and in the app with a new date.
