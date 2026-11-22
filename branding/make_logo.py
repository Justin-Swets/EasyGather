"""EasyGather logo, in the same fantasy-MMO style as EasyFish: writes two SVGs (icon-only avatar and with
wordmark) and renders PNGs with Edge.

Original artwork, no game assets: an ore-veined boulder with a crystal cluster, a pickaxe resting on it and
flowering herbs, in a meadow at a fantasy sunset, inside the same bevelled bronze frame as EasyFish, with
emerald corner gems. Lettering is Cinzel (SIL Open Font License, branding/fonts/OFL.txt), embedded in the
SVG so it renders the same anywhere.

Run from the repo root:  python branding/make_logo.py
"""
import base64
import math
import os
import subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
S = 1024            # design size; PNGs are downscaled from this for clean edges
IN = 50             # inner edge of the frame
HORIZON = 560

with open(os.path.join(HERE, "fonts", "Cinzel.ttf"), "rb") as f:
    FONT = base64.b64encode(f.read()).decode("ascii")


def sparkle(x, y, r, opacity, color="#fff4cc"):
    t = r * 0.2
    return (f'<path d="M{x},{y - r} Q{x + t},{y - t} {x + r},{y} Q{x + t},{y + t} {x},{y + r} '
            f'Q{x - t},{y + t} {x - r},{y} Q{x - t},{y - t} {x},{y - r}Z" fill="{color}" opacity="{opacity}"/>')


def pts(points, ox, oy):
    return " ".join(f"{ox + x:.1f},{oy + y:.1f}" for x, y in points)


def nugget(x, y, r, seed):
    """An irregular gold ore nugget set into the rock."""
    shape = [(r * (0.75 + 0.25 * math.sin(seed * 3.1 + k * 1.7)) * math.cos(k * math.pi / 3 + seed),
              r * (0.75 + 0.25 * math.cos(seed * 2.3 + k * 2.1)) * math.sin(k * math.pi / 3 + seed))
             for k in range(6)]
    return (f'<polygon points="{pts(shape, x, y)}" fill="url(#brass)" stroke="#2a1504" stroke-width="4" '
            f'stroke-linejoin="round"/>'
            f'<circle cx="{x - r * 0.25:.1f}" cy="{y - r * 0.3:.1f}" r="{r * 0.18:.1f}" fill="#fff6d0" opacity="0.85"/>')


def crystal(x, y, h, w, angle):
    """A pointed emerald crystal growing up from (x, y)."""
    return f'''<g transform="translate({x} {y}) rotate({angle})">
      <path d="M{-w},0 L{-w},{-h * 0.72} L0,{-h} L{w},{-h * 0.72} L{w},0 Z" fill="url(#crystal)"
            stroke="#062a1a" stroke-width="6" stroke-linejoin="round"/>
      <path d="M0,{-h} L0,0" stroke="#e8fff2" stroke-width="3" opacity="0.6"/>
      <path d="M{-w * 0.55},{-h * 0.1} L{-w * 0.55},{-h * 0.68}" stroke="#ffffff" stroke-width="5"
            stroke-linecap="round" opacity="0.7"/>
    </g>'''


def leaf(x, y, angle, length, width):
    L, w = length, width
    return f'''<g transform="translate({x} {y}) rotate({angle})">
      <path d="M0,0 C{w},{-L * 0.25} {w * 0.9},{-L * 0.75} 0,{-L} C{-w * 0.9},{-L * 0.75} {-w},{-L * 0.25} 0,0 Z"
            fill="url(#leaf)" stroke="#0a2410" stroke-width="6"/>
      <path d="M0,{-L * 0.08} L0,{-L * 0.9}" stroke="#e6ffcc" stroke-width="4" stroke-linecap="round" opacity="0.75"/>
    </g>'''


def flower(x, y, r, petal_grad):
    petals = "".join(
        f'<ellipse cx="0" cy="{-r * 0.62:.1f}" rx="{r * 0.36:.1f}" ry="{r * 0.62:.1f}" fill="url(#{petal_grad})" '
        f'stroke="#2a0a1e" stroke-width="5" transform="rotate({k * 72})"/>'
        for k in range(5))
    return f'''<g transform="translate({x} {y})">
      <circle r="{r * 1.9:.1f}" fill="url(#bloomGlow)"/>
      {petals}
      <circle r="{r * 0.34:.1f}" fill="url(#rivet)" stroke="#2a1504" stroke-width="4"/>
    </g>'''


def herb(x, ground, height, r, petal_grad, lean):
    """A flowering herb: curved stalk, a few leaves and a bloom on top."""
    tx, ty = x + lean, ground - height
    stalk = (f'<path d="M{x},{ground} Q{x - lean * 0.4},{ground - height * 0.55} {tx},{ty}" fill="none" '
             f'stroke="#0a2410" stroke-width="16" stroke-linecap="round"/>'
             f'<path d="M{x},{ground} Q{x - lean * 0.4},{ground - height * 0.55} {tx},{ty}" fill="none" '
             f'stroke="#4fa83c" stroke-width="8" stroke-linecap="round"/>')
    leaves = (leaf(x - 2, ground - 6, -58, height * 0.62, height * 0.16)
              + leaf(x + 2, ground - 6, 52, height * 0.56, height * 0.15)
              + leaf(x + lean * 0.2, ground - height * 0.45, -28, height * 0.4, height * 0.11))
    return stalk + leaves + flower(tx, ty, r, petal_grad)


def pickaxe(x, y, angle):
    """Handle along +x from the head at (x, y), rotated by angle degrees."""
    bands = "".join(
        f'<path d="M{gx},-17 L{gx + 14},17" stroke="#1e1208" stroke-width="5"/>' for gx in range(212, 276, 16))
    return f'''<g transform="translate({x} {y}) rotate({angle})">
      <rect x="0" y="-15" width="300" height="30" rx="12" fill="url(#wood)" stroke="#140806" stroke-width="7"/>
      <rect x="204" y="-18" width="76" height="36" rx="8" fill="url(#leather)" stroke="#140806" stroke-width="6"/>
      {bands}
      <rect x="292" y="-17" width="22" height="34" rx="6" fill="url(#steel)" stroke="#140806" stroke-width="6"/>
      <path d="M-8,-175 Q58,0 -8,175 Q22,0 -8,-175 Z" fill="url(#steel)" stroke="#140806" stroke-width="8"
            stroke-linejoin="round"/>
      <path d="M-4,-160 Q46,0 -4,160" fill="none" stroke="#ffffff" stroke-width="5" opacity="0.6"/>
      <rect x="-28" y="-36" width="52" height="72" rx="10" fill="url(#steelDark)" stroke="#140806" stroke-width="7"/>
      <circle cx="-2" cy="-18" r="7" fill="url(#rivet)" stroke="#2a1504" stroke-width="2.5"/>
      <circle cx="-2" cy="18" r="7" fill="url(#rivet)" stroke="#2a1504" stroke-width="2.5"/>
    </g>'''


def svg(wordmark: bool) -> str:
    lift = 80 if wordmark else 0
    hz = HORIZON - lift
    bx, by = 512, hz + 150         # boulder base centre

    rays = "".join(
        f'<path d="M512,{hz} L{512 + 900 * math.cos(math.radians(a - 3)):.0f},{hz - 900 * math.sin(math.radians(a - 3)):.0f} '
        f'L{512 + 900 * math.cos(math.radians(a + 3)):.0f},{hz - 900 * math.sin(math.radians(a + 3)):.0f} Z" '
        f'fill="#ffe2a8" opacity="0.07"/>'
        for a in (28, 52, 76, 104, 128, 152))

    # Mountains and pines on the horizon, leaving the sun open in the middle (same skyline as EasyFish)
    back = (f'<path d="M{IN},{hz} L{IN},{hz - 150} L140,{hz - 205} L230,{hz - 130} L300,{hz - 175} L380,{hz - 80} '
            f'L420,{hz} Z M{S - IN},{hz} L{S - IN},{hz - 140} L890,{hz - 195} L800,{hz - 120} L730,{hz - 165} '
            f'L650,{hz - 70} L610,{hz} Z" fill="#3a2a66"/>')
    front = (f'<path d="M{IN},{hz} L{IN},{hz - 90} L110,{hz - 120} L190,{hz - 70} L260,{hz - 95} L330,{hz - 30} '
             f'L360,{hz} Z M{S - IN},{hz} L{S - IN},{hz - 80} L910,{hz - 112} L840,{hz - 62} L770,{hz - 88} '
             f'L700,{hz - 26} L670,{hz} Z" fill="#1c1538"/>')
    pines = "".join(
        f'<path d="M{x},{hz - h} L{x + h * 0.28},{hz - h * 0.45} L{x + h * 0.18},{hz - h * 0.45} L{x + h * 0.34},{hz} '
        f'L{x - h * 0.34},{hz} L{x - h * 0.18},{hz - h * 0.45} L{x - h * 0.28},{hz - h * 0.45} Z" fill="#120d26"/>'
        for x, h in [(80, 150), (130, 110), (175, 135), (245, 95), (300, 70),
                     (944, 145), (895, 105), (850, 130), (780, 90), (725, 66)])

    # Meadow: a sunlit rise in the middle, darker toward the frame
    meadow = (f'<path d="M0,{hz + 4} Q256,{hz - 22} 512,{hz - 8} Q768,{hz - 22} {S},{hz + 4} V{S} H0 Z" '
              f'fill="url(#meadow)"/>'
              f'<path d="M0,{hz + 4} Q256,{hz - 22} 512,{hz - 8} Q768,{hz - 22} {S},{hz + 4}" fill="none" '
              f'stroke="#ffe1a0" stroke-width="5" opacity="0.55"/>')
    grass = "".join(
        f'<path d="M{x - 10},{y} Q{x - 6},{y - h * 0.6} {x - 18},{y - h} Q{x},{y - h * 0.5} {x + 4},{y} Z '
        f'M{x},{y} Q{x + 6},{y - h * 0.7} {x + 16},{y - h * 0.9} Q{x + 8},{y - h * 0.4} {x + 10},{y} Z" fill="#163e1a"/>'
        for x, y, h in [(120, hz + 190, 44), (210, hz + 230, 36), (830, hz + 200, 46), (905, hz + 240, 38),
                        (420, hz + 200, 30), (640, hz + 210, 32)])

    rock = [(-196, 0), (-210, -62), (-168, -146), (-92, -204), (6, -222), (104, -196), (176, -128),
            (212, -46), (198, 0), (120, 22), (-110, 22)]
    facets = (f'<path d="M{bx - 92},{by - 204} L{bx - 40},{by - 120} L{bx - 168},{by - 146} M{bx - 40},{by - 120} '
              f'L{bx + 60},{by - 92} L{bx + 176},{by - 128} M{bx + 60},{by - 92} L{bx + 40},{by + 10} '
              f'M{bx - 40},{by - 120} L{bx - 80},{by + 14}" fill="none" stroke="#1c1630" stroke-width="5" opacity="0.55"/>')
    nuggets = "".join(nugget(bx + dx, by + dy, r, s) for dx, dy, r, s in
                      [(-118, -70, 30, 1), (-52, -160, 24, 2), (70, -40, 34, 3), (128, -112, 22, 4), (-10, -60, 20, 5),
                       (-150, -18, 18, 6)])
    crystals = (crystal(bx - 54, by - 196, 120, 24, -22) + crystal(bx - 14, by - 210, 160, 28, 4)
                + crystal(bx + 30, by - 200, 104, 22, 26))

    word = ""
    if wordmark:
        text = ('font-family="EG Cinzel" font-weight="900" font-size="150" text-anchor="middle" '
                f'textLength="850" lengthAdjust="spacingAndGlyphs" x="512" y="{S - 118}"')
        word = f'''
    <rect x="{IN}" y="{S - 300}" width="{S - 2 * IN}" height="{300 - IN}" fill="url(#shade)"/>
    <path d="M150,{S - 88} H874" stroke="url(#goldLine)" stroke-width="5"/>
    <path d="M512,{S - 100} l14,12 l-14,12 l-14,-12 Z" fill="#ffd25a" stroke="#2a1504" stroke-width="3"/>
    <text {text} fill="#ff9a2e" filter="url(#glow)" opacity="0.7">EasyGather</text>
    <text {text} fill="#140a02" stroke="#140a02" stroke-width="26" stroke-linejoin="round" filter="url(#drop)">EasyGather</text>
    <text {text} fill="#6e3a0a" transform="translate(0 6)">EasyGather</text>
    <text {text} fill="url(#goldText)" stroke="#3a1f05" stroke-width="3">EasyGather</text>
    <text {text} fill="url(#gloss)">EasyGather</text>'''

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <style>@font-face {{ font-family: "EG Cinzel"; font-weight: 400 900;
      src: url(data:font/ttf;base64,{FONT}) format("truetype"); }}</style>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0a1238"/>
      <stop offset="0.45" stop-color="#3a2a80"/>
      <stop offset="0.75" stop-color="#b33f7c"/>
      <stop offset="1" stop-color="#ff9a3c"/>
    </linearGradient>
    <linearGradient id="meadow" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#5fa844"/>
      <stop offset="0.16" stop-color="#2f7a34"/>
      <stop offset="0.5" stop-color="#164a26"/>
      <stop offset="1" stop-color="#06180e"/>
    </linearGradient>
    <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#fff7c8"/>
      <stop offset="0.55" stop-color="#ffcf5a"/>
      <stop offset="1" stop-color="#ff7a2a"/>
    </radialGradient>
    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffb35a" stop-opacity="0.65"/>
      <stop offset="1" stop-color="#ff5aa0" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="stone" cx="0.35" cy="0.2" r="0.95">
      <stop offset="0" stop-color="#b8aed0"/>
      <stop offset="0.45" stop-color="#6c6290"/>
      <stop offset="1" stop-color="#241e3a"/>
    </radialGradient>
    <linearGradient id="crystal" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#d6ffe6"/>
      <stop offset="0.45" stop-color="#34d88a"/>
      <stop offset="1" stop-color="#0a5a34"/>
    </linearGradient>
    <linearGradient id="brass" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff0b0"/>
      <stop offset="0.45" stop-color="#e2a53a"/>
      <stop offset="1" stop-color="#7a4510"/>
    </linearGradient>
    <radialGradient id="rivet" cx="0.35" cy="0.3" r="0.7">
      <stop offset="0" stop-color="#fff6d0"/>
      <stop offset="1" stop-color="#a8691a"/>
    </radialGradient>
    <linearGradient id="wood" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#e0a868"/>
      <stop offset="0.45" stop-color="#9c5e2a"/>
      <stop offset="1" stop-color="#4a2810"/>
    </linearGradient>
    <linearGradient id="leather" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8a5a36"/>
      <stop offset="1" stop-color="#2e1a0c"/>
    </linearGradient>
    <linearGradient id="steel" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#f4f8ff"/>
      <stop offset="0.5" stop-color="#a6b2c6"/>
      <stop offset="1" stop-color="#4a5468"/>
    </linearGradient>
    <linearGradient id="steelDark" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#b8c2d2"/>
      <stop offset="1" stop-color="#3e4658"/>
    </linearGradient>
    <linearGradient id="leaf" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#12561e"/>
      <stop offset="0.6" stop-color="#46b84a"/>
      <stop offset="1" stop-color="#c8ff96"/>
    </linearGradient>
    <linearGradient id="petalPink" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#6a0f4a"/>
      <stop offset="0.55" stop-color="#e04aa8"/>
      <stop offset="1" stop-color="#ffd6f2"/>
    </linearGradient>
    <linearGradient id="petalGold" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#8a4e0c"/>
      <stop offset="0.6" stop-color="#ffc43d"/>
      <stop offset="1" stop-color="#fff2b8"/>
    </linearGradient>
    <radialGradient id="bloomGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffd6f2" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#ffd6f2" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="oreGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#7affc0" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#7affc0" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="frameGold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#fff2c0"/>
      <stop offset="0.25" stop-color="#f0b84a"/>
      <stop offset="0.6" stop-color="#9a5e18"/>
      <stop offset="0.8" stop-color="#d89a38"/>
      <stop offset="1" stop-color="#4a2a08"/>
    </linearGradient>
    <radialGradient id="gem" cx="0.35" cy="0.3" r="0.8">
      <stop offset="0" stop-color="#e0ffea"/>
      <stop offset="0.4" stop-color="#34d88a"/>
      <stop offset="1" stop-color="#064a2a"/>
    </radialGradient>
    <linearGradient id="goldText" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fffbe0"/>
      <stop offset="0.35" stop-color="#ffd760"/>
      <stop offset="0.7" stop-color="#e0901c"/>
      <stop offset="1" stop-color="#8e4e0a"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="0.42" stop-color="#ffffff" stop-opacity="0.1"/>
      <stop offset="0.43" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="goldLine" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ffd25a" stop-opacity="0"/>
      <stop offset="0.5" stop-color="#ffd25a"/>
      <stop offset="1" stop-color="#ffd25a" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#030a14" stop-opacity="0"/>
      <stop offset="0.4" stop-color="#030a14" stop-opacity="0.7"/>
      <stop offset="1" stop-color="#030a14" stop-opacity="0.92"/>
    </linearGradient>
    <filter id="glow" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="drop" x="-10%" y="-30%" width="120%" height="170%">
      <feDropShadow dx="0" dy="8" stdDeviation="7" flood-color="#000" flood-opacity="0.85"/>
    </filter>
    <clipPath id="inner"><rect x="{IN}" y="{IN}" width="{S - 2 * IN}" height="{S - 2 * IN}" rx="84"/></clipPath>
    <clipPath id="aboveGround"><rect x="0" y="0" width="{S}" height="{hz}"/></clipPath>
  </defs>

  <rect width="{S}" height="{S}" fill="#06080e"/>

  <!-- bevelled bronze frame -->
  <rect x="14" y="14" width="{S - 28}" height="{S - 28}" rx="116" fill="url(#frameGold)" stroke="#1a0e02" stroke-width="6"/>
  <rect x="26" y="26" width="{S - 52}" height="{S - 52}" rx="104" fill="none" stroke="#fff3c8" stroke-width="3" opacity="0.55"/>
  <rect x="{IN - 6}" y="{IN - 6}" width="{S - 2 * IN + 12}" height="{S - 2 * IN + 12}" rx="90" fill="#1a0e02"/>

  <g clip-path="url(#inner)">
    <rect width="{S}" height="{hz + 40}" fill="url(#sky)"/>
    {rays}
    <circle cx="512" cy="{hz}" r="360" fill="url(#halo)"/>
    <circle cx="512" cy="{hz + 12}" r="190" fill="url(#sun)" clip-path="url(#aboveGround)"/>
    {sparkle(200, 170 - lift * 0.4, 24, 0.95)}{sparkle(830, 240 - lift * 0.4, 17, 0.85)}{sparkle(300, 310 - lift * 0.4, 11, 0.7)}{sparkle(700, 140 - lift * 0.4, 9, 0.6)}
    {back}{front}{pines}
    {meadow}
    {grass}

    <!-- herbs behind and beside the boulder -->
    {herb(250, hz + 220, 230, 46, "petalPink", -18)}
    {herb(790, hz + 214, 190, 38, "petalGold", 16)}

    <!-- ore boulder -->
    <ellipse cx="{bx}" cy="{by + 18}" rx="250" ry="34" fill="#04120a" opacity="0.6"/>
    <circle cx="{bx - 14}" cy="{by - 250}" r="150" fill="url(#oreGlow)"/>
    {crystals}
    <polygon points="{pts(rock, bx, by)}" fill="url(#stone)" stroke="#140806" stroke-width="12" stroke-linejoin="round"/>
    {facets}
    <path d="M{bx - 150},{by - 120} Q{bx - 120},{by - 180} {bx - 60},{by - 196}" fill="none" stroke="#e8e0ff"
          stroke-width="12" stroke-linecap="round" opacity="0.45"/>
    {nuggets}

    <!-- pickaxe resting on the boulder, handle reaching to the top right -->
    {pickaxe(bx + 150, by - 150, -38)}

    {sparkle(bx - 120, by - 250, 18, 0.95, "#d6ffe6")}{sparkle(bx + 96, by - 268, 13, 0.85, "#fff4cc")}{sparkle(bx + 196, by - 40, 12, 0.8, "#fff4cc")}{sparkle(bx - 214, by - 160, 10, 0.7, "#d6ffe6")}
    {word}
  </g>

  <!-- inner rim shadow, then corner gems -->
  <rect x="{IN}" y="{IN}" width="{S - 2 * IN}" height="{S - 2 * IN}" rx="84" fill="none" stroke="#000" stroke-width="10" opacity="0.45"/>
  {"".join(f'<g transform="translate({x} {y}) rotate(45)"><rect x="-24" y="-24" width="48" height="48" rx="6" fill="url(#frameGold)" stroke="#1a0e02" stroke-width="5"/><rect x="-14" y="-14" width="28" height="28" rx="4" fill="url(#gem)" stroke="#06281a" stroke-width="3"/></g>' for x, y in [(62, 62), (S - 62, 62), (62, S - 62), (S - 62, S - 62)])}
</svg>
'''


def render(name: str, wordmark: bool):
    svg_path = os.path.join(HERE, name + ".svg")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg(wordmark))
    big = os.path.join(HERE, name + "-1024.png")
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=4000",
                    f"--window-size={S},{S}", f"--screenshot={big}", "file:///" + svg_path.replace("\\", "/")],
                   check=True, capture_output=True, timeout=90)
    img = Image.open(big).convert("RGB")
    assert img.size == (S, S), img.size
    for size in (512, 400):
        img.resize((size, size), Image.LANCZOS).save(os.path.join(HERE, f"{name}-{size}.png"), optimize=True)
    print(name, "-> SVG + PNG 1024/512/400")


if __name__ == "__main__":
    render("easygather-logo", wordmark=False)
    render("easygather-logo-wordmark", wordmark=True)
