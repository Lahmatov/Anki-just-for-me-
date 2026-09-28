#!/usr/bin/env python3
"""Позы Мончика из листов персонажа → PNG с прозрачным фоном в каталоге ассетов.

Исходники — листы, сгенерированные по docs/mascot-prompt.md, лежат в
design/mascot/Monchik_*.jpg. У каждой позы здесь записано, из какого листа
и какого прямоугольника её брать.

Фон убирается заливкой от краёв: у лося толстый тёмный контур, поэтому
заливка не проникает внутрь — белая карточка в копытах и белки глаз
остаются. Светлая тень под ногами тоже уходит: на тёмной теме серое
пятно выглядело бы грязью. Полупрозрачные пиксели контура «отмываются»
от цвета фона, чтобы на тёмном не было светлой каймы.

    pip install pillow numpy scipy
    python3 tools/cut_mascot.py
"""
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "mascot"
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"

# Имя ассета → (лист, прямоугольник x0, y0, x1, y1).
POSES = {
    "MascotHello": ("Monchik_waving.jpg", (390, 35, 1018, 745)),
    "MascotThinking": ("Monchik_thinking.jpg", (30, 388, 365, 745)),
    "MascotCheer": ("Monchik_celebrating.jpg", (330, 25, 1078, 745)),
    "MascotSleepy": ("Monchik_sleeping.jpg", (20, 388, 378, 745)),
    "MascotOops": ("Monchik_confused.jpg", (400, 60, 1010, 745)),
    "MascotCards": ("Monchik_holding_card.jpg", (428, 35, 980, 745)),
}

# Всё ближе к фону, чем HIGH, может быть фоном; ближе LOW — фон целиком.
LOW, HIGH = 16, 80


def cut(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB")).astype(float)
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))

    # Серые светлые пиксели — фон или тень под ногами.
    saturation = rgb.max(axis=2) - rgb.min(axis=2)
    greyish = (saturation < 22) & (rgb.mean(axis=2) > 170)
    candidate = (dist < HIGH) | greyish

    labels, _ = ndimage.label(candidate)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    background = np.isin(labels, edge[edge > 0])

    alpha = np.ones((h, w))
    ramp = np.clip((dist - LOW) / (HIGH - LOW), 0, 1)
    alpha[background] = ramp[background]
    alpha[background & greyish] = 0

    # Отмыть цвет фона из полупрозрачных пикселей контура.
    a = alpha[..., None]
    safe = np.where(a > 0.02, a, 1)
    color = np.clip((rgb - (1 - a) * bg) / safe, 0, 255)

    out = np.dstack([color, alpha * 255]).astype(np.uint8)
    result = Image.fromarray(out, "RGBA")
    return result.crop(result.getbbox())


def square(figure: Image.Image, margin: float = 0.04) -> Image.Image:
    """Квадратный холст, фигура по центру и стоит на нижнем крае —
    так все позы одного роста и не прыгают при смене настроения."""
    side = int(max(figure.size) * (1 + 2 * margin))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    x = (side - figure.width) // 2
    y = side - figure.height - int(side * margin)
    canvas.paste(figure, (x, y), figure)
    return canvas


def imageset(name: str, image: Image.Image) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    for old in folder.iterdir():
        old.unlink()
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def main() -> None:
    for name, (sheet, box) in POSES.items():
        figure = cut(Image.open(SOURCE / sheet).crop(box))
        result = square(figure)
        imageset(name, result)
        print(f"{name}: {result.size[0]}×{result.size[1]}")


if __name__ == "__main__":
    main()
