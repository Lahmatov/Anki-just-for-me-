#!/usr/bin/env python3
"""Собирает статические начертания Manrope из вариативного шрифта.

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

SOURCE = "https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope%5Bwght%5D.ttf"
LICENSE = "https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/OFL.txt"
OUT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Resources" / "Fonts"
WEIGHTS = [(400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold")]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    variable = OUT / "Manrope-variable.ttf"
    urllib.request.urlretrieve(SOURCE, variable)
    urllib.request.urlretrieve(LICENSE, OUT / "Manrope-OFL.txt")

    for weight, style in WEIGHTS:
        font = instancer.instantiateVariableFont(
            TTFont(variable), {"wght": weight}, updateFontNames=True)
        names = font["name"]
        for name_id, value in [
            (1, "Manrope"), (2, style), (4, f"Manrope {style}"),
            (6, f"Manrope-{style}"), (16, "Manrope"), (17, style),
        ]:
            names.setName(value, name_id, 3, 1, 0x409)
        font["OS/2"].usWeightClass = weight
        font.save(OUT / f"Manrope-{style}.ttf")
        print(f"Manrope-{style}.ttf")

    variable.unlink()


if __name__ == "__main__":
    main()
