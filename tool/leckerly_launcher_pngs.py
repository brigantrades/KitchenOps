#!/usr/bin/env python3
"""Rebuild leckerly_logo.png and leckerly_logo_foreground.png from leckerly_logo_mark.png.

Requires Pillow:  python3 -m pip install pillow
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image


def build_launcher_square(
    src_path: Path,
    out_path: Path,
    *,
    safe_radius_ratio: float = 0.325,
) -> None:
    im = Image.open(src_path).convert("RGB")
    g = im.convert("L")
    mask = g.point(lambda p: 0 if p > 242 else 255)
    bbox = mask.getbbox()
    if not bbox:
        raise SystemExit("Could not detect logo; check source image.")
    x0, y0, x1, y1 = bbox
    pad = max(10, int(min(x1 - x0, y1 - y0) * 0.03))
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad)
    y1 = min(im.height, y1 + pad)
    crop = im.crop((x0, y0, x1, y1))
    w, h = crop.size
    r = safe_radius_ratio * 1024
    s = (r * 2 / (w * w + h * h) ** 0.5) * 0.985
    nw, nh = max(1, int(w * s)), max(1, int(h * s))
    resized = crop.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (1024, 1024), (255, 255, 255))
    ox = (1024 - nw) // 2
    oy = (1024 - nh) // 2
    canvas.paste(resized, (ox, oy))
    canvas.save(out_path, optimize=True)


def main() -> None:
    base = Path(__file__).resolve().parent.parent / "assets/images/branding"
    mark = base / "leckerly_logo_mark.png"
    if not mark.exists():
        raise SystemExit(f"Missing {mark}")
    build_launcher_square(mark, base / "leckerly_logo.png")
    build_launcher_square(mark, base / "leckerly_logo_foreground.png")
    print("Wrote leckerly_logo.png and leckerly_logo_foreground.png")


if __name__ == "__main__":
    main()
