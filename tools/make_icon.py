"""Иконка приложения: колода карточек со звуковой волной на фронтальной.

Рисуется в 2x и уменьшается — так края сглаживаются без артефактов.
Три варианта — светлый, тёмный и тинтованный, как требует iOS 18+.

    pip install pillow
    python3 tools/make_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset
"""
from PIL import Image, ImageDraw, ImageFilter
import math, os, sys

S = 2048           # рабочий размер
OUT = 1024

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(len(a)))
def hexc(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), a)

def gradient_fast(c1, c2):
    # Диагональный градиент через уменьшенную версию и растяжение — быстро и гладко.
    small = 256
    img = Image.new('RGBA', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            px[x, y] = lerp(c1, c2, (x + y) / (2*small - 2))
    return img.resize((S, S), Image.BICUBIC)

def glow(center, radius, color, alpha):
    layer = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), fill=color[:3] + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius*0.6))

def card(w, h, r, fill, outline=None, outline_w=0):
    layer = Image.new('RGBA', (w + 40, h + 40), (0,0,0,0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((20, 20, 20+w, 20+h), radius=r, fill=fill,
                        outline=outline, width=outline_w)
    return layer

def paste_rotated(base, layer, angle, center):
    rot = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - rot.width/2); y = int(center[1] - rot.height/2)
    base.alpha_composite(rot, (x, y))

def shadow(layer, angle, center, base, blur=40, alpha=90, dy=40):
    sh = Image.new('RGBA', layer.size, (0,0,0,0))
    mask = layer.split()[3]
    sh.paste((10, 8, 40, alpha), (0,0), mask)
    sh = sh.rotate(angle, resample=Image.BICUBIC, expand=True).filter(ImageFilter.GaussianBlur(blur))
    x = int(center[0] - sh.width/2); y = int(center[1] - sh.height/2 + dy)
    base.alpha_composite(sh, (x, y))

def build(variant):
    if variant == 'light':
        bg = gradient_fast(hexc('#5B50F0'), hexc('#8B5CF6'))
        bg.alpha_composite(glow((S*0.25, S*0.18), S*0.45, hexc('#FFFFFF'), 70))
        back_fill = [(255,255,255,70), (255,255,255,120)]
        front_fill = (255,255,255,245)
        ink = hexc('#4F46E5'); ink2 = hexc('#A5A2F5')
        shadow_alpha = 90
    elif variant == 'dark':
        bg = gradient_fast(hexc('#0E0C24'), hexc('#241E5C'))
        bg.alpha_composite(glow((S*0.3, S*0.25), S*0.5, hexc('#6361F0'), 90))
        back_fill = [(99,97,240,90), (120,118,245,140)]
        front_fill = (40,38,90,255)
        ink = hexc('#A9A7FF'); ink2 = hexc('#5E5BB8')
        shadow_alpha = 160
    else:  # tinted — только оттенки серого, систему красит сама
        bg = Image.new('RGBA', (S, S), (0,0,0,255))
        back_fill = [(255,255,255,60), (255,255,255,110)]
        front_fill = (235,235,235,255)
        ink = (60,60,60,255); ink2 = (150,150,150,255)
        shadow_alpha = 0

    base = bg.copy()
    cw, ch, cr = int(S*0.56), int(S*0.40), int(S*0.085)
    center = (S*0.525, S*0.54)

    # Две задние карточки — колода.
    for i, (angle, dx, dy) in enumerate([(14, -S*0.045, -S*0.085), (6, -S*0.02, -S*0.04)]):
        layer = card(cw, ch, cr, back_fill[i])
        paste_rotated(base, layer, angle, (center[0]+dx, center[1]+dy))

    # Фронтальная карточка.
    front = card(cw, ch, cr, front_fill)
    d = ImageDraw.Draw(front)
    pad = int(cw*0.12)
    top = 20 + int(ch*0.24)
    # Слово — жирная полоса, перевод — тонкая.
    d.rounded_rectangle((20+pad, top, 20+pad+int(cw*0.46), top+int(ch*0.13)),
                        radius=int(ch*0.065), fill=ink)
    d.rounded_rectangle((20+pad, top+int(ch*0.25), 20+pad+int(cw*0.30), top+int(ch*0.25)+int(ch*0.08)),
                        radius=int(ch*0.04), fill=ink2)
    # Звуковая волна справа — голос и произношение.
    bars = [0.22, 0.42, 0.62, 0.36]
    bw = int(cw*0.045); gap = int(cw*0.035)
    right = 20 + cw - pad
    x0 = right - len(bars)*bw - (len(bars)-1)*gap
    mid = 20 + ch//2 + int(ch*0.02)
    for i, hgt in enumerate(bars):
        hh = int(ch*hgt/1.6)
        x = x0 + i*(bw+gap)
        d.rounded_rectangle((x, mid-hh//2, x+bw, mid+hh//2), radius=bw//2, fill=ink)

    if shadow_alpha:
        shadow(front, -4, center, base, alpha=shadow_alpha)
    paste_rotated(base, front, -4, center)

    return base.resize((OUT, OUT), Image.LANCZOS).convert('RGB')

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'App/Resources/Assets.xcassets/AppIcon.appiconset')
os.makedirs(out_dir, exist_ok=True)
for v in ('light', 'dark', 'tinted'):
    build(v).save(os.path.join(out_dir, f'icon-{v}.png'), optimize=True)
    print('готово:', v)
