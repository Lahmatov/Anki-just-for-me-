#!/usr/bin/env python3
"""Маскот — лось Мончик из Мончегорска. Рисуется векторно, в SVG.

Мончегорск стоит между озёрами Имандра и Лумболка у подножия
Мончетундры — по-саамски «красивые горы». Отсюда образ: мультяшный лось
(их там больше, чем светофоров) в вязаном шарфе цветов северного сияния.

Позы собираются из общих деталей, поэтому лось во всех одинаковый.
SVG кладётся в каталог ассетов как вектор: Xcode сам растеризует его
под любой размер, а приложение не тащит пачку PNG.

    python3 tools/make_mascot.py              # SVG в Assets.xcassets
    python3 tools/make_mascot.py --preview D  # плюс PNG-превью в папку D
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"

FUR = "#8E5B3D"
FUR_DARK = "#6B4029"
FUR_LIGHT = "#A8744F"
MUZZLE = "#C99A72"
MUZZLE_DARK = "#B07F58"
NOSTRIL = "#5A3421"
ANTLER = "#F3DEB2"
ANTLER_DARK = "#DDBF88"
INK = "#2B1B12"
CHEEK = "#F28C7A"
# Шарф — зелёный, бирюзовый и фиолетовый, как сияние над Имандрой.
AURORA = ["#2BC39A", "#1C9FEF", "#A873F2"]


def antler(mirror: bool) -> str:
    # Лопата лосиного рога: широкая пластина с отростками поверху.
    d = ("M166 112 C150 104 128 104 108 104 C84 104 60 96 50 76 "
         "C44 64 44 50 50 38 C56 46 62 54 70 58 C70 44 74 30 84 20 "
         "C88 34 92 46 100 54 C104 40 110 28 122 20 C124 36 126 50 132 60 "
         "C138 50 146 42 156 38 C154 54 152 70 158 84 C164 94 170 102 166 112 Z")
    shade = ("M166 112 C150 104 128 104 108 104 C84 104 60 96 50 76 "
             "C70 88 96 92 122 90 C142 88 158 96 166 112 Z")
    t = ' transform="translate(400 0) scale(-1 1)"' if mirror else ""
    return (f'<g{t}><path d="{d}" fill="{ANTLER}"/>'
            f'<path d="{shade}" fill="{ANTLER_DARK}"/></g>')


def ear(mirror: bool) -> str:
    t = ' transform="translate(400 0) scale(-1 1)"' if mirror else ""
    return (f'<g{t}><ellipse cx="116" cy="146" rx="36" ry="17" fill="{FUR}" '
            f'transform="rotate(-22 116 146)"/>'
            f'<ellipse cx="120" cy="146" rx="22" ry="8" fill="{MUZZLE}" '
            f'transform="rotate(-22 120 146)"/></g>')


def body(scarf_tail: bool = True) -> str:
    parts = [
        # Плечи и грудь.
        f'<path d="M84 400 C84 330 120 292 200 292 C280 292 316 330 316 400 Z" fill="{FUR}"/>',
        f'<path d="M150 400 C150 350 170 322 200 322 C230 322 250 350 250 400 Z" fill="{FUR_LIGHT}"/>',
        # Шарф: три полосы вокруг шеи.
        f'<path d="M122 286 C150 306 250 306 278 286 L282 310 C252 332 148 332 118 310 Z" fill="{AURORA[0]}"/>',
        f'<path d="M120 298 C150 318 250 318 280 298 L281 306 C250 326 150 326 119 306 Z" fill="{AURORA[1]}"/>',
    ]
    if scarf_tail:
        parts += [
            f'<path d="M244 312 C250 336 248 360 238 384 L266 390 C274 364 272 336 262 310 Z" fill="{AURORA[0]}"/>',
            f'<path d="M246 340 L270 344 L269 354 L244 350 Z" fill="{AURORA[2]}"/>',
            f'<path d="M242 366 L266 372 L264 380 L240 375 Z" fill="{AURORA[1]}"/>',
            f'<circle cx="252" cy="312" r="13" fill="{AURORA[2]}"/>',
        ]
    return "".join(parts)


def head() -> str:
    return "".join([
        # Лоб и щёки.
        f'<ellipse cx="200" cy="168" rx="76" ry="70" fill="{FUR}"/>',
        # Чёлка-хохолок между ушами.
        f'<path d="M184 104 C190 88 206 86 214 100 C220 92 230 96 228 108 Z" fill="{FUR_DARK}"/>',
        # Большой лосиный нос-«губа».
        f'<ellipse cx="200" cy="238" rx="64" ry="50" fill="{MUZZLE}"/>',
        f'<ellipse cx="200" cy="222" rx="50" ry="26" fill="{MUZZLE}" opacity="0.6"/>',
        # Ноздри.
        f'<ellipse cx="178" cy="238" rx="9" ry="12" fill="{NOSTRIL}" transform="rotate(12 178 238)"/>',
        f'<ellipse cx="222" cy="238" rx="9" ry="12" fill="{NOSTRIL}" transform="rotate(-12 222 238)"/>',
        # Румянец.
        f'<ellipse cx="140" cy="196" rx="15" ry="9" fill="{CHEEK}" opacity="0.55"/>',
        f'<ellipse cx="260" cy="196" rx="15" ry="9" fill="{CHEEK}" opacity="0.55"/>',
    ])


def eyes(kind: str) -> str:
    if kind == "closed":
        return (f'<path d="M154 156 Q170 168 186 156" stroke="{INK}" stroke-width="6" '
                f'fill="none" stroke-linecap="round"/>'
                f'<path d="M214 156 Q230 168 246 156" stroke="{INK}" stroke-width="6" '
                f'fill="none" stroke-linecap="round"/>')
    if kind == "happy":
        return (f'<path d="M154 160 Q170 142 186 160" stroke="{INK}" stroke-width="7" '
                f'fill="none" stroke-linecap="round"/>'
                f'<path d="M214 160 Q230 142 246 160" stroke="{INK}" stroke-width="7" '
                f'fill="none" stroke-linecap="round"/>')
    dx, dy = {"up": (4, -7), "worried": (0, 3)}.get(kind, (2, 2))
    out = []
    for cx, side in ((170, -1), (230, 1)):
        px = cx + (dx if kind == "up" else -side * dx)
        out.append(f'<ellipse cx="{cx}" cy="152" rx="19" ry="23" fill="#FFFFFF"/>')
        out.append(f'<circle cx="{px}" cy="{154 + dy}" r="11" fill="{INK}"/>')
        out.append(f'<circle cx="{px + 4}" cy="{149 + dy}" r="4" fill="#FFFFFF"/>')
    return "".join(out)


def brows(kind: str) -> str:
    shapes = {
        "normal": ("M154 124 Q170 116 186 124", "M214 124 Q230 116 246 124"),
        "raised": ("M152 118 Q170 104 186 116", "M214 124 Q230 116 246 124"),
        "worried": ("M154 120 Q168 122 186 130", "M214 130 Q232 122 246 120"),
        "up": ("M152 116 Q170 106 188 114", "M212 114 Q230 106 248 116"),
    }
    left, right = shapes[kind]
    return "".join(f'<path d="{d}" stroke="{FUR_DARK}" stroke-width="7" fill="none" '
                   f'stroke-linecap="round"/>' for d in (left, right))


def mouth(kind: str) -> str:
    if kind == "open":
        return (f'<path d="M176 262 Q200 300 224 262 Z" fill="{NOSTRIL}"/>'
                f'<path d="M186 276 Q200 292 214 276 Q200 284 186 276 Z" fill="#E86F6F"/>')
    if kind == "flat":
        return (f'<path d="M184 268 Q200 262 216 268" stroke="{NOSTRIL}" stroke-width="5" '
                f'fill="none" stroke-linecap="round"/>')
    if kind == "o":
        return f'<ellipse cx="200" cy="268" rx="7" ry="8" fill="{NOSTRIL}"/>'
    return (f'<path d="M178 262 Q200 282 222 262" stroke="{NOSTRIL}" stroke-width="5" '
            f'fill="none" stroke-linecap="round"/>')


def hoof(x: float, y: float, angle: float) -> str:
    """Передняя нога с раздвоенным копытом; (x, y) — копыто, угол от вертикали."""
    return (f'<g transform="rotate({angle} {x} {y})">'
            f'<rect x="{x - 17}" y="{y}" width="34" height="96" rx="17" fill="{FUR}"/>'
            f'<path d="M{x - 17} {y + 14} C{x - 17} {y - 6} {x + 17} {y - 6} {x + 17} {y + 14} '
            f'L{x + 17} {y + 18} L{x - 17} {y + 18} Z" fill="{FUR_DARK}"/>'
            f'<path d="M{x} {y - 2} L{x} {y + 18}" stroke="{INK}" stroke-width="3"/>'
            f'</g>')


def sparkle(x: float, y: float, r: float, color: str) -> str:
    return (f'<path d="M{x} {y - r} Q{x + r * 0.2} {y - r * 0.2} {x + r} {y} '
            f'Q{x + r * 0.2} {y + r * 0.2} {x} {y + r} Q{x - r * 0.2} {y + r * 0.2} {x - r} {y} '
            f'Q{x - r * 0.2} {y - r * 0.2} {x} {y - r} Z" fill="{color}"/>')


def zed(x: float, y: float, size: float, color: str) -> str:
    w = size * 0.18
    return (f'<path d="M{x} {y} h{size} L{x + w} {y + size} h{size - w}" stroke="{color}" '
            f'stroke-width="{w}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')


def card(x: float, y: float, angle: float) -> str:
    return (f'<g transform="rotate({angle} {x} {y})">'
            f'<rect x="{x - 34}" y="{y - 24}" width="68" height="48" rx="8" fill="#FFFFFF" '
            f'stroke="#E1E6E4" stroke-width="3"/>'
            f'<rect x="{x - 22}" y="{y - 10}" width="44" height="6" rx="3" fill="{AURORA[0]}"/>'
            f'<rect x="{x - 22}" y="{y + 2}" width="30" height="6" rx="3" fill="#C9D1CE"/></g>')


def moose(eye: str, brow: str, mouth_kind: str, extras_back: str = "",
          extras_front: str = "", scarf_tail: bool = True) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" '
            'width="400" height="400">'
            + extras_back + antler(False) + antler(True) + ear(False) + ear(True)
            + body(scarf_tail) + head() + eyes(eye) + brows(brow) + mouth(mouth_kind)
            + extras_front + "</svg>")


POSES = {
    # Приветствие: машет копытом.
    "MascotHello": lambda: moose(
        "normal", "raised", "smile",
        extras_front=hoof(330, 206, 18)),
    # Думает: копыто у подбородка, взгляд вверх — тест, загрузка.
    "MascotThinking": lambda: moose(
        "up", "up", "flat",
        extras_back=sparkle(358, 160, 16, AURORA[1]) + sparkle(378, 124, 9, AURORA[2]),
        extras_front=hoof(246, 268, -40)),
    # Радуется: обе ноги вверх, рот открыт — награды, конец сессии.
    "MascotCheer": lambda: moose(
        "happy", "up", "open",
        extras_back=(sparkle(40, 150, 18, AURORA[0]) + sparkle(362, 140, 16, "#FFC800")
                     + sparkle(70, 230, 10, AURORA[2]) + sparkle(338, 236, 11, AURORA[1])),
        extras_front=hoof(74, 214, -24) + hoof(326, 214, 24)),
    # Спит — повторять нечего.
    "MascotSleepy": lambda: moose(
        "closed", "normal", "o",
        # Буквы «z» — контурами, а не текстом: шрифта в SVG на телефоне нет.
        extras_back=(zed(330, 168, 34, AURORA[1]) + zed(362, 124, 22, AURORA[2]))),
    # Растерян — ошибка, пустой результат.
    "MascotOops": lambda: moose("worried", "worried", "flat"),
    # С карточкой — наборы, импорт.
    "MascotCards": lambda: moose(
        "normal", "normal", "smile",
        extras_front=card(300, 250, 12) + hoof(292, 262, 8)),
}


def imageset(name: str, svg: str) -> None:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    (folder / f"{name}.svg").write_text(svg)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        # Вектор сохраняется: Xcode растеризует под нужный размер без мыла.
        "properties": {"preserves-vector-representation": True},
    }, indent=2) + "\n")


def preview(folder: pathlib.Path, svgs: dict) -> None:
    """PNG-превью через Chromium: так видно лося без Xcode."""
    shell = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell"
    folder.mkdir(parents=True, exist_ok=True)
    cells = "".join(f'<div style="display:inline-block;margin:6px;background:#F7F9F8;'
                    f'border-radius:24px"><img src="{n}.svg" width="300"></div>'
                    for n in svgs)
    for name, svg in svgs.items():
        (folder / f"{name}.svg").write_text(svg)
    (folder / "sheet.html").write_text(f"<body style='margin:0;background:#ddd'>{cells}</body>")
    subprocess.run([shell, "--no-sandbox", "--hide-scrollbars", "--window-size=960,660",
                    f"--screenshot={folder / 'sheet.png'}", f"file://{folder / 'sheet.html'}"],
                   check=True, capture_output=True)


def main() -> None:
    svgs = {name: make() for name, make in POSES.items()}
    for name, svg in svgs.items():
        imageset(name, svg)
    if "--preview" in sys.argv:
        preview(pathlib.Path(sys.argv[sys.argv.index("--preview") + 1]), svgs)


if __name__ == "__main__":
    main()
