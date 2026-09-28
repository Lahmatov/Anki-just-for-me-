#!/usr/bin/env python3
"""Собирает шрифты приложения: статические начертания из вариативных файлов.

Nunito — основной шрифт: скруглённый, крупный и очень читаемый, как принято
в обучающих приложениях. Rubik — запасной вариант в настройках.

Вариативный файл iOS регистрирует одним начертанием, и достать из него
нужную жирность по имени ненадёжно. Статические файлы с явными
PostScript-именами (Manrope-SemiBold и т. п.) находятся всегда.

    pip install fonttools
    python3 tools/make_fonts.py

Шрифт — SIL Open Font License, текст лицензии лежит рядом со шрифтами.
"""
import pathlib
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

GOOGLE = "https://raw.githubusercontent.com/google/fonts/main/ofl"
OUT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Resources" / "Fonts"

# Семейство → (путь в google/fonts, начертания для вариативного файла).
VARIABLE = {
    "Nunito": ("nunito/Nunito%5Bwght%5D.ttf",
               [(400, "Regular"), (600, "SemiBold"), (700, "Bold"),
                (800, "ExtraBold"), (900, "Black")]),
    "Rubik": ("rubik/Rubik%5Bwght%5D.ttf",
              [(400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold")]),
}
STATIC: dict = {}
LICENSES = {"Nunito": "nunito", "Rubik": "rubik"}


def instantiate(family: str, source: str, weights) -> None:
    variable = OUT / f"{family}-variable.ttf"
    urllib.request.urlretrieve(f"{GOOGLE}/{source}", variable)
    for weight, style in weights:
        font = instancer.instantiateVariableFont(
            TTFont(variable), {"wght": weight}, updateFontNames=True)
        names = font["name"]
        for name_id, value in [
            (1, family), (2, style), (4, f"{family} {style}"),
            (6, f"{family}-{style}"), (16, family), (17, style),
        ]:
            names.setName(value, name_id, 3, 1, 0x409)
        font["OS/2"].usWeightClass = weight
        font.save(OUT / f"{family}-{style}.ttf")
        print(f"{family}-{style}.ttf")
    variable.unlink()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for family, (source, weights) in VARIABLE.items():
        instantiate(family, source, weights)
    for family, source in STATIC.items():
        urllib.request.urlretrieve(f"{GOOGLE}/{source}", OUT / f"{family}-Regular.ttf")
        print(f"{family}-Regular.ttf")
    for family, folder in LICENSES.items():
        urllib.request.urlretrieve(f"{GOOGLE}/{folder}/OFL.txt", OUT / f"{family}-OFL.txt")


if __name__ == "__main__":
    main()
