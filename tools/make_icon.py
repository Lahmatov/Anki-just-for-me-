#!/usr/bin/env python3
"""Иконка приложения: лось Мончик под северным сиянием над Мончетундрой.

Лось берётся из tools/make_mascot.py, чтобы на иконке и в приложении был
один и тот же персонаж. Три варианта — светлый, тёмный и тинтованный,
как требует iOS 18+. Растеризует headless Chromium (он есть в окружении
разработки), результат — PNG 1024×1024 без прозрачности.

    python3 tools/make_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_mascot as m  # noqa: E402

SHELL = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell"

PALETTES = {
    "icon-light.png": {"sky": ("#0E6E5C", "#0B3F52"), "hills": "#0A3342",
                       "aurora": m.AURORA, "gray": False},
    "icon-dark.png": {"sky": ("#08201F", "#050D14"), "hills": "#030A0E",
                      "aurora": m.AURORA, "gray": False},
    "icon-tinted.png": {"sky": ("#000000", "#000000"), "hills": "#101010",
                        "aurora": ["#6A6A6A", "#555555", "#444444"], "gray": True},
}


def moose_bust() -> str:
    """Лось без рук и эмоций-добавок: голова, рога и плечи в шарфе."""
    return (m.antler(False) + m.antler(True) + m.ear(False) + m.ear(True)
            + m.body(scarf_tail=False) + m.head() + m.eyes("normal")
            + m.brows("raised") + m.mouth("smile"))


def icon_svg(palette: dict) -> str:
    top, bottom = palette["sky"]
    a = palette["aurora"]
    ribbons = "".join(
        f'<path d="M-40 {y} C220 {y - 120} 420 {y + 90} 640 {y - 40} S960 {y - 150} 1080 {y - 60}" '
        f'stroke="{color}" stroke-width="{w}" fill="none" stroke-linecap="round" opacity="{o}"/>'
        for y, color, w, o in ((250, a[0], 90, 0.55), (330, a[1], 60, 0.45), (190, a[2], 44, 0.4)))
    hills = (f'<path d="M0 760 L180 600 L300 690 L470 540 L640 700 L780 590 L1024 760 '
             f'L1024 1024 L0 1024 Z" fill="{palette["hills"]}"/>')
    # Лось 400×400 → 1040×1040, низом к краю иконки: бюст «вырастает» снизу.
    bust = f'<g transform="translate(-8 96) scale(2.6)">{moose_bust()}</g>'
    gray = ('<filter id="g"><feColorMatrix type="saturate" values="0"/></filter>'
            if palette["gray"] else "")
    group = '<g filter="url(#g)">' if palette["gray"] else "<g>"
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
            'width="1024" height="1024">'
            f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>'
            f'</linearGradient>{gray}</defs>'
            f'<rect width="1024" height="1024" fill="url(#sky)"/>'
            f'{ribbons}{hills}{group}{bust}</g></svg>')


def render(svg: str, out: pathlib.Path) -> None:
    html = out.with_suffix(".html")
    html.write_text(f"<body style='margin:0'>{svg}</body>")
    subprocess.run([SHELL, "--no-sandbox", "--hide-scrollbars", "--window-size=1024,1024",
                    f"--screenshot={out}", f"file://{html}"], check=True, capture_output=True)
    html.unlink()
    # Иконка App Store — без альфа-канала, иначе загрузка отклоняется.
    from PIL import Image
    Image.open(out).convert("RGB").save(out)


def main() -> None:
    out_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    for name, palette in PALETTES.items():
        render(icon_svg(palette), out_dir / name)
        print(name)


if __name__ == "__main__":
    main()
