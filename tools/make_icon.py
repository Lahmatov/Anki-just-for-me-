#!/usr/bin/env python3
"""Иконка приложения: Мончик машет из-под северного сияния над Мончетундрой.

Лось берётся из листа персонажа (design/mascot, вырезается тем же кодом,
что и позы в tools/cut_mascot.py) — на иконке и в приложении один персонаж.
Фон — небо с сиянием и силуэт сопок — рисуется SVG и растеризуется headless
Chromium. Три варианта для iOS 18+: светлый, тёмный и тинтованный. PNG
1024×1024 без прозрачности — иначе App Store не примет.

    python3 tools/make_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset
"""
import pathlib
import subprocess
import sys

from PIL import Image, ImageOps

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import cut_mascot  # noqa: E402

SHELL = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell"
AURORA = ["#2BC39A", "#1C9FEF", "#A873F2"]
# Бюст: голова, рога, машущее копыто и шарф — без ног.
BUST = ("Monchik_waving.jpg", (390, 35, 1018, 600))

PALETTES = {
    "icon-light.png": {"sky": ("#0E6E5C", "#0B3F52"), "hills": "#0A3342",
                       "aurora": AURORA, "gray": False},
    "icon-dark.png": {"sky": ("#08201F", "#050D14"), "hills": "#030A0E",
                      "aurora": AURORA, "gray": False},
    "icon-tinted.png": {"sky": ("#000000", "#000000"), "hills": "#101010",
                        "aurora": ["#6A6A6A", "#555555", "#444444"], "gray": True},
}


def background_svg(palette: dict) -> str:
    top, bottom = palette["sky"]
    a = palette["aurora"]
    ribbons = "".join(
        f'<path d="M-40 {y} C220 {y - 120} 420 {y + 90} 640 {y - 40} S960 {y - 150} 1080 {y - 60}" '
        f'stroke="{color}" stroke-width="{w}" fill="none" stroke-linecap="round" opacity="{o}"/>'
        for y, color, w, o in ((250, a[0], 90, 0.55), (330, a[1], 60, 0.45), (190, a[2], 44, 0.4)))
    hills = (f'<path d="M0 760 L180 600 L300 690 L470 540 L640 700 L780 590 L1024 760 '
             f'L1024 1024 L0 1024 Z" fill="{palette["hills"]}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
            'width="1024" height="1024">'
            '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>'
            f'</linearGradient></defs><rect width="1024" height="1024" fill="url(#sky)"/>'
            f'{ribbons}{hills}</svg>')


def render_background(svg: str, out: pathlib.Path) -> Image.Image:
    html = out.with_suffix(".html")
    html.write_text(f"<body style='margin:0'>{svg}</body>")
    subprocess.run([SHELL, "--no-sandbox", "--hide-scrollbars", "--window-size=1024,1024",
                    f"--screenshot={out}", f"file://{html}"], check=True, capture_output=True)
    html.unlink()
    return Image.open(out).convert("RGB")


def bust() -> Image.Image:
    sheet, box = BUST
    figure = cut_mascot.cut(Image.open(cut_mascot.SOURCE / sheet).crop(box))
    # Шарф упирается в нижний край иконки: бюст «вырастает» снизу.
    scale = 960 / figure.width
    return figure.resize((960, round(figure.height * scale)), Image.LANCZOS)


def main() -> None:
    out_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    moose = bust()
    for name, palette in PALETTES.items():
        icon = render_background(background_svg(palette), out_dir / name)
        figure = moose
        if palette["gray"]:
            gray = ImageOps.grayscale(moose.convert("RGB")).convert("RGBA")
            gray.putalpha(moose.getchannel("A"))
            figure = gray
        icon.paste(figure, ((1024 - figure.width) // 2, 1024 - figure.height + 70), figure)
        icon.save(out_dir / name)
        print(name)


if __name__ == "__main__":
    main()
