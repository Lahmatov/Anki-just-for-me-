#!/usr/bin/env python3
"""Собирает шрифты приложения: статические начертания из вариативных файлов.

Manrope — спокойный гротеск, Pixelify Sans — пиксельные заголовки ретро-темы,
Rubik — читаемый основной текст к ним, Press Start 2P — крупные цифры.

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
    "Manrope": ("manrope/Manrope%5Bwght%5D.ttf",
                [(400, "Regular"), (500, "Medium"), (600, "SemiBold"),
                 (700, "Bold"), (800, "ExtraBold")]),
    "PixelifySans": ("pixelifysans/PixelifySans%5Bwght%5D.ttf",
                     [(400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold")]),
    "Rubik": ("rubik/Rubik%5Bwght%5D.ttf",
              [(400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold")]),
}
STATIC = {"PressStart2P": "pressstart2p/PressStart2P-Regular.ttf"}
LICENSES = {"Manrope": "manrope", "PixelifySans": "pixelifysans", "Rubik": "rubik",
            "PressStart2P": "pressstart2p"}


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
