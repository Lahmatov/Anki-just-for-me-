# Промпт для графики маскота

Для генераторов картинок: Midjourney, ChatGPT (GPT Image), Gemini (Imagen / Nano Banana),
Ideogram, Recraft. Промпты на английском — на нём генераторы понимают точнее всего.

Как пользоваться:

1. Сначала **лист персонажа** (блок 1): один лось в нескольких ракурсах. Он задаёт внешность.
2. Лучший вариант загрузить как референс и по нему делать **позы** (блок 2) — так лось
   останется одним и тем же. В Midjourney: `--cref <ссылка> --cw 100`; в ChatGPT и Gemini —
   приложить картинку и написать «same character as in the image».
3. Стиль — подставить одну из строк блока 3 вместо `[STYLE]`.
4. Иконка — блок 4.

Что прислать обратно для приложения: **PNG 1024×1024 с прозрачным фоном** (или SVG из
Recraft/Illustrator), по файлу на позу. Иконку — PNG 1024×1024 **без** прозрачности.

---

## 1. Лист персонажа

```
Mascot character sheet for a mobile language-learning app.
Character: "Monchik", a friendly cartoon moose from Monchegorsk, a small town in the
Russian Arctic between Lake Imandra and the Monchetundra hills, under the northern lights.
He learns American English by watching TV shows.

Look: chunky, rounded, huggable proportions; big head (about half of the body height);
large friendly eyes with a white highlight; big soft moose nose with two nostrils;
small rosy cheeks; wide palmate moose antlers; warm brown fur with a lighter beige muzzle.
Signature item: a knitted scarf striped in northern-lights colors
(emerald green #2BC39A, sky blue #1C9FEF, violet #A873F2).

Style: [STYLE]
Show: front view, 3/4 view, side view, back view, plus 3 facial expressions
(happy, thinking, surprised). Same character, same proportions and colors in every view.
Clean flat background #F7F9F8, even spacing, no text, no labels, no watermark.
```

## 2. Позы (по одной картинке на позу)

Общий хвост для каждой позы:

```
Same character as the reference: Monchik the cartoon moose with the northern-lights scarf.
[STYLE]
Full body, centered, a little empty space around. Transparent background (or plain white).
No text, no logos, no watermark, no extra characters.
```

И перед ним — одна из строк:

| Файл | Где в приложении | Строка |
|---|---|---|
| `hello` | заставка, знакомство | `Waving hello with one front hoof raised, big warm smile.` |
| `thinking` | тест уровня, подбор слов | `Thinking: hoof under his chin, eyes looking up, one eyebrow raised, small sparkles nearby.` |
| `cheer` | цель выполнена, награда | `Celebrating: both front hooves up, mouth open in joy, confetti in green, blue and violet.` |
| `sleepy` | повторять нечего | `Sleeping peacefully sitting down, eyes closed, a small "zz" above, cozy and calm.` |
| `oops` | ошибка | `Confused and slightly embarrassed: worried eyebrows, awkward smile, one hoof scratching his head.` |
| `cards` | наборы, импорт | `Proudly holding up a white flashcard with both hooves, smiling.` |
| `listening` | сериалы, аудирование | `Wearing big headphones, eyes closed, enjoying the sound, small music notes in aurora colors.` |
| `reading` | карточки, слова | `Reading a small open book, curious expression, antlers slightly glowing with aurora colors.` |

## 3. Стиль — подставить вместо `[STYLE]`

Номера — как в набросках, которые уже были.

| № | Вариант | Строка стиля |
|---|---|---|
| 1 | Пончик | `Kawaii style, almost spherical body, tiny stubby legs, tiny antlers, small dot eyes, soft pastel shading.` |
| 2 | Геометрия | `Flat geometric low-poly style made of simple triangles and facets, two-tone shading, crisp edges.` |
| 3 | Сияние-силуэт | `Silhouette filled with a glowing northern-lights gradient (green to blue to violet) on a dark starry sky, minimal white eyes.` |
| 4 | Носатый профиль | `Classic cartoon caricature, side profile, oversized droopy moose nose and dewlap, expressive and goofy.` |
| 5 | Лосёнок | `Baby moose calf without antlers (just two small nubs), huge sparkling eyes, freckles, very cute.` |
| 6 | В ушанке | `Wearing a violet Russian ushanka fur hat with ear flaps down, antlers poking out through the hat.` |
| 7 | Линия | `Minimal line art: white body, thick uniform dark outline, antlers drawn as lines in an aurora gradient.` |
| 8 | Как Дуо | `Duolingo-like flat vector style: the moose's fur itself is emerald green #2BC39A, sky-blue antlers, bold simple shapes, no outlines.` |
| 9 | Плюшевый | `Plush toy look: soft felt texture, visible stitched seams, button eyes, a small violet patch.` |
| 10 | В наушниках | `Always wears big headphones in an aurora gradient, antlers glowing in green-blue-violet.` |

Общий вариант, если нужен просто «как у приложений для языков»:

```
Modern flat vector mascot illustration in the style of popular language-learning apps
(Duolingo, Busuu): bold simple rounded shapes, no outlines or very soft ones,
subtle flat shading, bright friendly colors, high readability at small sizes.
```

## 4. Иконка приложения

```
iOS app icon, 1024x1024, square, no rounded corners (iOS adds them), no text.
Monchik the cartoon moose (same character as the reference), head and shoulders,
facing the viewer, large and centered, filling about 80% of the icon.
Background: night sky with northern lights ribbons in emerald green #2BC39A,
sky blue #1C9FEF and violet #A873F2, dark silhouette of rounded Arctic hills at the bottom.
[STYLE]
Simple, bold, readable even at 60x60 pixels. No small details, no letters, no border.
```

## 5. Чего избегать

Для полей «negative prompt» / `--no` (Midjourney) или просто в конце промпта:

```
Avoid: realistic or photographic style, 3D render (unless asked), scary or angry face,
sharp teeth, reindeer or deer (must be a moose: broad palmate antlers, big droopy nose),
Christmas themes, Santa hats, text, letters, logos, watermark, busy background,
extra limbs, inconsistent colors between images.
```

## Палитра

| Цвет | HEX | Где |
|---|---|---|
| Зелёный сияния | `#2BC39A` | главный цвет, шарф |
| Бирюзовый | `#1C9FEF` | шарф, рога в стилях 8 и 10 |
| Фиолетовый | `#A873F2` | шарф, ушанка |
| Розовый | `#FF7EB6` | щёки |
| Шерсть | `#8E5B3D` | лось |
| Морда | `#C99A72` | нос и морда |
| Рога | `#F3DEB2` | рога в классическом варианте |
| Ночь | `#0E2A3B` | фон иконки |
| Фон приложения | `#F7F9F8` | светлый фон экранов |
