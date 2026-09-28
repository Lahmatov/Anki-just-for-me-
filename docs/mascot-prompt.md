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

## 6. Артефакты: один лось на все приложения

Мончик — общий персонаж семейства приложений. В каждом приложении или для каждого языка
у него появляется **один предмет-артефакт**, который сразу говорит, чему он учит.

**Что не меняется никогда:** лось, его пропорции, лицо, цвет шерсти и **шарф цветов
сияния**. Шарф — фирменный знак всей линейки: по нему Мончика узнают в любом приложении.

**Что меняется:** только артефакт и, если нужно, один акцентный цвет приложения.

Правила для артефакта:

- **Один предмет**, а не набор. Два предмета на маленькой иконке сливаются в кашу.
- **Всегда в одном месте** внутри одного приложения: либо в копытах, либо на голове
  (шапка, очки, наушники). Предмет на голове удобнее — копыта остаются свободными
  для поз (машет, радуется, думает).
- **Узнаётся без надписи.** Генераторы коверкают буквы; максимум — 2–3 буквы крупно
  (`EN`, `PT`), и лучше без них.
- **Язык — не страна.** Флаг подходит, только если приложение учит конкретному варианту:
  американскому английскому — звёзды и полосы, британскому — Union Jack, европейскому
  португальскому — Португалия. Иначе — символ культуры, а не флаг.
- **Без стереотипов**, над которыми смеются носители: не сомбреро и не матрёшка, а еда,
  транспорт, архитектура, привычные вещи.
- **Не повторять** артефакт дважды на одной картинке (например, книга в копытах и она же
  висит над головой).

### Шаблон промпта

Приложить картинку с обычным Мончиком как референс и написать:

```
Same character as the reference image: Monchik, the cartoon moose with the knitted
northern-lights scarf. Keep his face, body, proportions, fur color and scarf exactly
the same, same illustration style.

Add exactly ONE subject artifact: [ARTIFACT].
Placement: [PLACEMENT].
The artifact is simple and flat, in the same style, clearly readable at small sizes,
using at most 2–3 colors that harmonize with the aurora palette
(#2BC39A, #1C9FEF, #A873F2).

Pose: [POSE].
Transparent background. No text [or: only the letters "XX", large and simple],
no logos, no watermark, the artifact appears only once.
```

`[PLACEMENT]` — одно из:
- `holding it in both front hooves in front of his chest`
- `wearing it on his head, between the antlers`
- `hanging on the scarf as a small round badge`

`[POSE]` — строки поз из раздела 2.

### Языки

| Приложение | `[ARTIFACT]` |
|---|---|
| **Американский английский** (Recap — это приложение) | `a navy-blue book with a white star and red-white stripes on the cover` или, раз учим по сериалам, `a striped popcorn bucket and a TV remote` |
| Британский английский | `a book with a Union Jack cover` или `a small red double-decker bus toy` |
| Европейский португальский | `a pastel de nata on a small plate` или `a small yellow Lisbon tram (eléctrico 28)` или `a book with a blue-and-white azulejo tile pattern` |
| Испанский | `a book with a red-and-yellow cover and a small paella pan` |
| Французский | `a navy beret` или `a croissant` |
| Немецкий | `a big soft pretzel` |
| Итальянский | `a small espresso cup` или `a Vespa-style scooter keychain` |
| Японский | `an onigiri rice ball` или `a calligraphy brush` |
| Китайский | `a red paper lantern` |
| Корейский | `a bowl of bibimbap` |

### Другие предметы

| Приложение | `[ARTIFACT]` |
|---|---|
| Математика | `a wooden ruler and a pencil` или `a calculator` |
| Программирование | `a small laptop with "</>" on the lid` |
| Музыка | `a small acoustic guitar` |
| География | `a small globe` |
| История | `a rolled parchment scroll and a quill` |
| Химия / наука | `a round flask with bubbling aurora-colored liquid` |
| Теория вождения | `a small steering wheel` |
| Финансы | `a piggy bank` |
| Спорт / здоровье | `a small dumbbell and a sweatband` |
| Кулинария | `a white chef's hat` |
| Чтение / литература | `a stack of three books` |
| Шахматы | `a large white knight chess piece` |

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
