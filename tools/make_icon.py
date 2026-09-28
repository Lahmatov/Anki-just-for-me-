"""Иконка приложения в пиксельном стиле: колода карточек со звуковой волной.

Рисуется на сетке 32×32 и увеличивается без сглаживания — каждая клетка
становится квадратом 32×32 пикселя, как в пиксель-арте. Палитра — та же,
что у интерфейса (RetroUI): кремовый фон, чёрные рамки, фиолетовый акцент.
Три варианта — светлый, тёмный и тинтованный, как требует iOS 18+.

    pip install pillow
    python3 tools/make_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset
"""
import os
import sys

from PIL import Image

GRID = 32
OUT = 1024


def hexc(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def pixel_card(px, x0, y0, x1, y1, fill, border):
    """Карточка со ступенчатыми углами: угловая клетка рамки пропущена."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            corner = (x in (x0, x1)) and (y in (y0, y1))
            if corner:
                continue
            edge = x in (x0, x1) or y in (y0, y1)
            px[x, y] = border if edge else fill


def draw(palette):
    img = Image.new('RGBA', (GRID, GRID), palette['bg'])
    px = img.load()
    # Задняя карточка с жёсткой тенью.
    pixel_card(px, 10, 7, 27, 20, palette['shadow'], palette['shadow'])
    pixel_card(px, 9, 6, 26, 19, palette['back'], palette['border'])
    # Передняя карточка и её тень.
    pixel_card(px, 6, 12, 23, 26, palette['shadow'], palette['shadow'])
    pixel_card(px, 5, 11, 22, 25, palette['front'], palette['border'])
    # Две строки «текста».
    for x in range(8, 14):
        px[x, 15] = palette['border']
        px[x, 16] = palette['border']
    for x in range(8, 12):
        px[x, 19] = palette['accent']
    # Звуковая волна: столбики разной высоты вокруг строки 18.
    for x, half in ((15, 1), (17, 3), (19, 4), (21, 2)):
        for y in range(18 - half, 18 + half + 1):
            px[x, y] = palette['accent']
    return img.resize((OUT, OUT), Image.NEAREST)


PALETTES = {
    'icon-light.png': dict(bg=hexc('#FEFCD0'), back=hexc('#C381B5'), front=hexc('#FFFFFF'),
                           border=hexc('#000000'), shadow=hexc('#000000'),
                           accent=hexc('#A2559A')),
    'icon-dark.png': dict(bg=hexc('#16120A'), back=hexc('#C381B5'), front=hexc('#1C1C1E'),
                          border=hexc('#FEFCD0'), shadow=hexc('#6B5A3A'),
                          accent=hexc('#C381B5')),
    # Тинтованный: система красит яркость, поэтому — оттенки серого на чёрном.
    'icon-tinted.png': dict(bg=hexc('#000000'), back=hexc('#7A7A7A'), front=hexc('#303030'),
                            border=hexc('#FFFFFF'), shadow=hexc('#1A1A1A'),
                            accent=hexc('#D0D0D0')),
}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    for name, palette in PALETTES.items():
        # Иконке iOS не нужен альфа-канал: прозрачность там запрещена.
        draw(palette).convert('RGB').save(os.path.join(out_dir, name))
        print(name)


if __name__ == '__main__':
    main()
