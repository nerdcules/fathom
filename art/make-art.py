#!/usr/bin/env python3
"""Draw Fathom's wallpapers, theme preview and boot unlock logo (with the
picture of the unlock screen that Omarchy's Appearance > Unlock shows).

Writes SVG into a temporary folder, renders it with rsvg-convert and
converts wallpapers to WebP with ImageMagick. Output lands in ../theme.

    ./art/make-art.py            # everything
    ./art/make-art.py preview    # one piece: horizon, eclipse, hexgrid, preview, unlock
"""

import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEME = ROOT / "theme"
BACKGROUNDS = THEME / "backgrounds"

# Wallpapers are 3:2 like the Surface Laptop 3 panel; wider screens crop the sides.
WALL_W, WALL_H = 3840, 2560

BG = "#060a13"
GRID = "#0e1828"
CYAN = "#4cc9f0"
VIOLET = "#9d8cff"
MONO = "JetBrainsMono Nerd Font"


def hexagon(cx, cy, r):
    pts = []
    for i in range(6):
        a = math.radians(-90 + 60 * i)
        pts.append(f"{cx + r * math.cos(a):.1f},{cy + r * math.sin(a):.1f}")
    return " ".join(pts)


def stars(w, h, max_y, count, seed):
    rnd = random.Random(seed)
    out = []
    for _ in range(count):
        x = rnd.uniform(0, w)
        y = rnd.uniform(0, max_y)
        r = rnd.choice([1, 1, 1.5, 2, 2.5]) * w / 3840
        o = rnd.uniform(0.15, 0.75)
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.2f}" fill="#cfe6ff" opacity="{o:.2f}"/>')
    return "\n".join(out)


def grid_defs(w):
    cell = w / 40
    return (
        f'<pattern id="grid" width="{cell:.2f}" height="{cell:.2f}" patternUnits="userSpaceOnUse">'
        f'<path d="M{cell:.2f} 0H0V{cell:.2f}" fill="none" stroke="{GRID}" stroke-width="{max(1, w / 1920):.2f}"/>'
        f"</pattern>"
    )


def svg(w, h, body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
        f"<defs>{defs}</defs>{body}</svg>"
    )


def horizon(w, h):
    """A dark planet's rim glowing on the horizon, under a fading grid."""
    top = h * 0.74
    r = w * 1.6
    cx, cy = w / 2, top + r
    defs = grid_defs(w) + f"""
<radialGradient id="sky" cx="{cx:.0f}" cy="{top:.0f}" r="{w * 0.65:.0f}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#10284a" stop-opacity="0.9"/>
  <stop offset="1" stop-color="{BG}" stop-opacity="0"/>
</radialGradient>
<linearGradient id="gridfade" x1="0" y1="0" x2="0" y2="{top:.0f}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#fff" stop-opacity="0.12"/>
  <stop offset="1" stop-color="#fff" stop-opacity="1"/>
</linearGradient>
<mask id="gridmask"><rect width="{w}" height="{h}" fill="url(#gridfade)"/></mask>
<filter id="glow1" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="{w * 0.010:.1f}"/></filter>
<filter id="glow2" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="{w * 0.030:.1f}"/></filter>
"""
    body = f"""
<rect width="{w}" height="{h}" fill="{BG}"/>
<rect width="{w}" height="{h}" fill="url(#sky)"/>
<rect width="{w}" height="{h}" fill="url(#grid)" mask="url(#gridmask)"/>
{stars(w, h, top * 0.85, 160, 7)}
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="none" stroke="{VIOLET}" stroke-width="{w * 0.05:.0f}" opacity="0.28" filter="url(#glow2)"/>
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="#03060d"/>
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="none" stroke="{CYAN}" stroke-width="{w * 0.012:.0f}" opacity="0.75" filter="url(#glow1)"/>
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="none" stroke="{CYAN}" stroke-width="{max(2, w * 0.0012):.1f}"/>
"""
    return svg(w, h, body, defs)


def eclipse(w, h):
    """A black disc with a cyan-to-violet corona: a nod to Nord's black moon."""
    cx, cy, r = w * 0.66, h * 0.42, h * 0.2
    a = math.radians(-40)
    sx, sy = cx + r * math.cos(a), cy + r * math.sin(a)
    defs = grid_defs(w) + f"""
<linearGradient id="corona" x1="{cx - r:.0f}" y1="{cy + r:.0f}" x2="{cx + r:.0f}" y2="{cy - r:.0f}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{VIOLET}"/>
  <stop offset="1" stop-color="{CYAN}"/>
</linearGradient>
<radialGradient id="vignette" cx="{cx:.0f}" cy="{cy:.0f}" r="{w * 0.7:.0f}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#fff" stop-opacity="0.9"/>
  <stop offset="1" stop-color="#fff" stop-opacity="0.05"/>
</radialGradient>
<mask id="gridmask"><rect width="{w}" height="{h}" fill="url(#vignette)"/></mask>
<filter id="wide" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{r * 0.14:.1f}"/></filter>
<filter id="tight" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{r * 0.025:.1f}"/></filter>
<filter id="spark" x="-200%" y="-200%" width="500%" height="500%"><feGaussianBlur stdDeviation="{r * 0.05:.1f}"/></filter>
"""
    body = f"""
<rect width="{w}" height="{h}" fill="#05080f"/>
<rect width="{w}" height="{h}" fill="url(#grid)" mask="url(#gridmask)" opacity="0.8"/>
{stars(w, h, h, 220, 11)}
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="none" stroke="url(#corona)" stroke-width="{r * 0.30:.0f}" opacity="0.55" filter="url(#wide)"/>
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="none" stroke="url(#corona)" stroke-width="{r * 0.05:.0f}" opacity="0.9" filter="url(#tight)"/>
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r * 0.995:.0f}" fill="#020409"/>
<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="none" stroke="url(#corona)" stroke-width="{max(2, r * 0.006):.1f}" opacity="0.85"/>
<circle cx="{sx:.0f}" cy="{sy:.0f}" r="{r * 0.06:.0f}" fill="#d9f6ff" filter="url(#spark)"/>
<circle cx="{sx:.0f}" cy="{sy:.0f}" r="{r * 0.012:.1f}" fill="#ffffff"/>
"""
    return svg(w, h, body, defs)


def hexgrid(w, h):
    """Quiet working wallpaper: grid, faint Fathom hexagon, thin horizon."""
    cx, cy = w / 2, h * 0.46
    R = h * 0.30
    defs = grid_defs(w) + f"""
<radialGradient id="pool" cx="{cx:.0f}" cy="{cy:.0f}" r="{w * 0.45:.0f}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#0c1830"/>
  <stop offset="1" stop-color="#070c18"/>
</radialGradient>
"""
    body = f"""
<rect width="{w}" height="{h}" fill="url(#pool)"/>
<rect width="{w}" height="{h}" fill="url(#grid)" opacity="0.7"/>
<polygon points="{hexagon(cx, cy, R)}" fill="none" stroke="#16304f" stroke-width="{w * 0.003:.1f}" stroke-linejoin="round"/>
<polygon points="{hexagon(cx, cy, R * 0.42)}" fill="none" stroke="#1b3a5e" stroke-width="{w * 0.003:.1f}" stroke-linejoin="round"/>
<line x1="0" y1="{h * 0.86:.0f}" x2="{w}" y2="{h * 0.86:.0f}" stroke="{CYAN}" stroke-opacity="0.35" stroke-width="{max(2, w * 0.0008):.1f}"/>
"""
    return svg(w, h, body, defs)


def preview(w=2560, h=1440):
    """Theme-picker preview: the horizon wallpaper with two tiled windows."""
    base = horizon(w, h)
    inner = base[base.index("<defs>") + 6 : base.index("</defs>")]
    scene = base[base.index("</defs>") + 7 : base.rindex("</svg>")]
    defs = inner + f"""
<linearGradient id="border" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="{CYAN}"/>
  <stop offset="1" stop-color="{VIOLET}"/>
</linearGradient>
"""
    fs = 26
    lh = 44

    def line(x, y, parts):
        spans = "".join(f'<tspan fill="{c}">{t}</tspan>' for t, c in parts)
        return f'<text x="{x}" y="{y}" font-family="{MONO}" font-size="{fs}" xml:space="preserve">{spans}</text>'

    p = [("~/Work/shop ", CYAN), ("main ", "#3ddc97"), ("❯ ", CYAN)]
    term = [
        p + [("dotnet test", "#e6f0ff")],
        [("  Shop.Api.Tests -> bin/Debug/net10.0/Shop.Api.Tests.dll", "#8fa3bf")],
        [("Passed!", "#3ddc97"), (" - Failed: 0, Passed: 248, Skipped: 0", "#e6f0ff")],
        p + [("docker compose ps", "#e6f0ff")],
        [("api        ", "#e6f0ff"), ("running   ", "#3ddc97"), (":8080", "#8fa3bf")],
        [("postgres   ", "#e6f0ff"), ("running   ", "#3ddc97"), (":5432", "#8fa3bf")],
        [("ollama     ", "#e6f0ff"), ("running   ", "#3ddc97"), (":11434", "#8fa3bf")],
        [("worker     ", "#e6f0ff"), ("restarting", "#ffb547"), ("", "#8fa3bf")],
        p + [("█", "#e6f0ff")],
    ]
    term_svg = "\n".join(line(64, 150 + i * lh, parts) for i, parts in enumerate(term))

    swatches = ["#ff6b81", "#ffb547", "#3ddc97", CYAN, "#5b8cff", VIOLET, "#e6f0ff", "#8fa3bf"]
    sw = "\n".join(
        f'<rect x="{1560 + i * 118}" y="1180" width="96" height="96" rx="14" fill="{c}"/>'
        for i, c in enumerate(swatches)
    )
    bars = "\n".join(
        f'<text x="1560" y="{170 + i * 70}" font-family="{MONO}" font-size="24" fill="#8fa3bf">{name}</text>'
        f'<rect x="1700" y="{150 + i * 70}" width="760" height="18" rx="9" fill="#13203a"/>'
        f'<rect x="1700" y="{150 + i * 70}" width="{760 * v:.0f}" height="18" rx="9" fill="{c}"/>'
        for i, (name, v, c) in enumerate(
            [("cpu", 0.18, CYAN), ("gpu", 0.41, CYAN), ("mem", 0.34, VIOLET), ("vram", 0.59, VIOLET), ("disk", 0.82, "#ffb547")]
        )
    )
    body = f"""{scene}
<rect x="0" y="0" width="{w}" height="44" fill="#070c18" fill-opacity="0.9"/>
<text x="24" y="30" font-family="{MONO}" font-size="20" font-weight="bold" fill="{CYAN}" letter-spacing="3">FATHOM</text>
<text x="170" y="30" font-family="{MONO}" font-size="20" fill="#8fa3bf">1  <tspan fill="{CYAN}">2</tspan>  3  4</text>
<text x="{w - 24}" y="30" font-family="{MONO}" font-size="20" fill="#e6f0ff" text-anchor="end">16:04</text>
<rect x="24" y="68" width="1488" height="1348" rx="14" fill="#0a1020" fill-opacity="0.9" stroke="url(#border)" stroke-width="3"/>
{term_svg}
<rect x="1536" y="68" width="1000" height="560" rx="14" fill="#0a1020" fill-opacity="0.9" stroke="#1f3350" stroke-width="2"/>
{bars}
<rect x="1536" y="652" width="1000" height="764" rx="14" fill="#0a1020" fill-opacity="0.9" stroke="#1f3350" stroke-width="2"/>
<polygon points="{hexagon(2036, 900, 150)}" fill="none" stroke="{CYAN}" stroke-width="5" stroke-linejoin="round"/>
<polygon points="{hexagon(2036, 900, 62)}" fill="none" stroke="{CYAN}" stroke-width="5" stroke-linejoin="round"/>
{sw}
"""
    return svg(w, h, body, defs)


def unlock(w=800, h=188):
    """Boot unlock logo (Plymouth): hexagon mark and FATHOM wordmark."""
    hx, hy = 140, h / 2
    body = f"""
<polygon points="{hexagon(hx, hy, 78)}" fill="none" stroke="{CYAN}" stroke-width="10" stroke-linejoin="round"/>
<polygon points="{hexagon(hx, hy, 32)}" fill="none" stroke="{CYAN}" stroke-width="10" stroke-linejoin="round"/>
<text x="258" y="{hy + 40:.0f}" font-family="{MONO}" font-weight="bold" font-size="112" letter-spacing="16" fill="{CYAN}">FATHOM</text>
"""
    return svg(w, h, body)


PIECES = {
    "horizon": (lambda: horizon(WALL_W, WALL_H), BACKGROUNDS / "1-horizon.webp", WALL_W, WALL_H),
    "eclipse": (lambda: eclipse(WALL_W, WALL_H), BACKGROUNDS / "2-eclipse.webp", WALL_W, WALL_H),
    "hexgrid": (lambda: hexgrid(WALL_W, WALL_H), BACKGROUNDS / "3-hexgrid.webp", WALL_W, WALL_H),
    "preview": (preview, THEME / "preview.png", 2560, 1440),
    "unlock": (unlock, THEME / "unlock.png", 800, 188),
}


def render(name, tmp):
    make, out, w, h = PIECES[name]
    src = tmp / f"{name}.svg"
    png = tmp / f"{name}.png"
    src.write_text(make())
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(src), "-o", str(png)], check=True)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.suffix == ".webp":
        # A little grain hides the banding that dark gradients get in 8 bits.
        subprocess.run(
            ["magick", str(png), "-seed", "3", "-attenuate", "0.12", "+noise", "Gaussian", "-quality", "94", str(out)],
            check=True,
        )
    else:
        shutil.copyfile(png, out)
    print(f"{name:8} -> {out.relative_to(ROOT)}")
    if name == "unlock":
        unlock_preview(tmp)


def theme_color(key):
    for line in (THEME / "colors.toml").read_text().splitlines():
        k, _, v = line.partition("=")
        if k.strip() == key:
            return v.strip().strip('"')
    raise SystemExit(f"make-art: no {key} in colors.toml")


def unlock_preview(tmp):
    """The disk-unlock screen as Omarchy will draw it, from Omarchy's own
    omarchy-plymouth-preview. Omarchy offers a theme under Appearance > Unlock
    only if it has this picture. The tool ends by opening the picture in imv;
    a stand-in imv that does nothing keeps it from doing that here."""
    tool = shutil.which("omarchy-plymouth-preview")
    out = THEME / "preview-unlock.png"
    if not tool:
        print(f"{'unlock':8} -> skipped {out.relative_to(ROOT)}: omarchy-plymouth-preview not found")
        return
    stub = tmp / "bin"
    stub.mkdir(exist_ok=True)
    (stub / "imv").write_text("#!/bin/sh\nexit 0\n")
    (stub / "imv").chmod(0o755)
    env = dict(os.environ, PATH=f"{stub}{os.pathsep}{os.environ.get('PATH', '')}")
    subprocess.run([tool, theme_color("background"), theme_color("foreground"), str(THEME / "unlock.png"), str(out)],
                   check=True, env=env)
    print(f"{'unlock':8} -> {out.relative_to(ROOT)}")


def main():
    for tool in ("rsvg-convert", "magick"):
        if not shutil.which(tool):
            sys.exit(f"make-art: {tool} is needed (pacman -S librsvg imagemagick)")
    names = sys.argv[1:] or list(PIECES)
    unknown = [n for n in names if n not in PIECES]
    if unknown:
        sys.exit(f"make-art: unknown piece(s): {', '.join(unknown)}; choose from {', '.join(PIECES)}")
    with tempfile.TemporaryDirectory() as d:
        for name in names:
            render(name, Path(d))


if __name__ == "__main__":
    main()
