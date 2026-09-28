#!/usr/bin/env python3
"""Цвета темы → colorset'ы каталога ассетов, с проверкой контраста.

Палитра — «Мончегорск»: зелёный северного сияния как главный цвет,
озёрный синий, тёплый коричневый лося. У каждого цвета светлый и тёмный
вариант; пары «текст — фон» проверяются по WCAG до записи, чтобы
нечитаемое сочетание не доехало до телефона.

    python3 tools/make_theme.py
"""
import json
import pathlib
import sys

ASSETS = pathlib.Path(__file__).resolve().parent.parent / "App" / "Resources" / "Assets.xcassets"

# Имя → (светлый, тёмный).
PALETTE = {
    "ThemeBackground": ("#F7F9F8", "#111B20"),
    "ThemeSurface": ("#FFFFFF", "#1A272E"),
    "ThemeBorder": ("#E1E6E4", "#2E3F47"),
    "ThemeInk": ("#2B3137", "#ECF2F4"),
    "ThemeMuted": ("#6B7378", "#9AABB3"),
    "ThemePrimary": ("#0F9373", "#2BC39A"),
    "ThemePrimaryLip": ("#0A6B54", "#1C8B6D"),
    "ThemeOnPrimary": ("#FFFFFF", "#0B1F19"),
    "ThemeTint": ("#E3F4EE", "#173630"),
    "AccentColor": ("#0F9373", "#2BC39A"),
    "LaunchBackground": ("#F7F9F8", "#111B20"),
}

# (текст, фон, минимум). 4.5 — обычный текст, 3 — крупный жирный
# (надписи на кнопках набраны Nunito Black от 17 pt).
CHECKS = [
    ("ThemeInk", "ThemeBackground", 4.5),
    ("ThemeInk", "ThemeSurface", 4.5),
    ("ThemeMuted", "ThemeBackground", 4.5),
    ("ThemeMuted", "ThemeSurface", 4.5),
    ("ThemeOnPrimary", "ThemePrimary", 3.0),
    ("ThemeInk", "ThemeTint", 4.5),
]


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    channels = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(a: str, b: str) -> float:
    high, low = sorted([luminance(a), luminance(b)], reverse=True)
    return (high + 0.05) / (low + 0.05)


def component(hex_color: str) -> dict:
    h = hex_color.lstrip("#")
    return {"red": f"0x{h[0:2]}", "green": f"0x{h[2:4]}", "blue": f"0x{h[4:6]}", "alpha": "1.000"}


def colorset(light: str, dark: str) -> dict:
    return {
        "colors": [
            {"idiom": "universal", "color": {"color-space": "srgb", "components": component(light)}},
            {"idiom": "universal",
             "appearances": [{"appearance": "luminosity", "value": "dark"}],
             "color": {"color-space": "srgb", "components": component(dark)}},
        ],
        "info": {"author": "xcode", "version": 1},
    }


def main() -> int:
    failed = False
    for text, background, minimum in CHECKS:
        for mode in (0, 1):
            ratio = contrast(PALETTE[text][mode], PALETTE[background][mode])
            mark = "ok" if ratio >= minimum else "МАЛО"
            print(f"{text} на {background} ({'тёмная' if mode else 'светлая'}): {ratio:.2f} {mark}")
            failed |= ratio < minimum
    if failed:
        print("Контраст ниже нормы — цвета не записаны.")
        return 1
    for name, (light, dark) in PALETTE.items():
        folder = ASSETS / f"{name}.colorset"
        folder.mkdir(exist_ok=True)
        (folder / "Contents.json").write_text(json.dumps(colorset(light, dark), indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
