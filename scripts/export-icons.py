#!/usr/bin/env python3
"""Re-export TezKetKaz launcher icons from the master SVG.

Reads design/logo-concepts/concept-3-pin-bolt.svg and writes:
- assets/launcher/icon-{1024,512,256,192,144,96,72,48}.png  — full icon at each size
- assets/launcher/icon-fg-{1024,432}.png                    — adaptive-icon foreground (transparent bg)
- assets/launcher/icon-bg-1024.png                          — solid navy background
- assets/launcher/splash-logo.png                           — 512x512 splash logo

Run once after editing the master SVG:
    python3 scripts/export-icons.py

Dependencies:
    pip install cairosvg pillow
"""
import sys
from pathlib import Path

try:
    import cairosvg
    from PIL import Image
except ImportError:
    print("Install deps: pip install cairosvg pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "design" / "logo-concepts" / "concept-3-pin-bolt.svg"
OUT = ROOT / "assets" / "launcher"
OUT.mkdir(parents=True, exist_ok=True)

BG_HEX = "#1A237E"
BG_RGB = (26, 35, 126)

# Background-rect line in the SVG (strip for adaptive foreground)
BG_RECT_TAG = '<rect width="1024" height="1024" rx="224" ry="224" fill="url(#g3)"/>'


def main() -> None:
    if not SRC.exists():
        print(f"Source SVG not found: {SRC}", file=sys.stderr)
        sys.exit(1)
    svg = SRC.read_bytes()

    for size in (1024, 512, 256, 192, 144, 96, 72, 48):
        png = cairosvg.svg2png(bytestring=svg, output_width=size, output_height=size)
        (OUT / f"icon-{size}.png").write_bytes(png)
        print(f"icon-{size}.png")

    svg_fg = svg.decode("utf-8").replace(BG_RECT_TAG, "")
    for size in (1024, 432):
        png = cairosvg.svg2png(bytestring=svg_fg.encode("utf-8"), output_width=size, output_height=size)
        (OUT / f"icon-fg-{size}.png").write_bytes(png)
        print(f"icon-fg-{size}.png")

    Image.new("RGB", (1024, 1024), BG_RGB).save(OUT / "icon-bg-1024.png")
    print("icon-bg-1024.png")

    png = cairosvg.svg2png(bytestring=svg, output_width=512, output_height=512)
    (OUT / "splash-logo.png").write_bytes(png)
    print("splash-logo.png")

    print(f"\nDone. {len(list(OUT.glob('*.png')))} PNGs in {OUT}")
    print("Next: flutter pub get && dart run flutter_launcher_icons && dart run flutter_native_splash:create")


if __name__ == "__main__":
    main()
