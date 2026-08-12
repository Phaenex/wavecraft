#!/usr/bin/env python3
"""
generate-icons.py

Regenerates Wavecraft's icon assets from the "four flat-colored rounded bars at uneven heights on
a dark charcoal ground" design (see the commit that introduced them,
"Replace app + device icon with a fork-specific design", and CLAUDE.md's Icons section):

  - AppIcon.appiconset's 7 PNG sizes (BGMApp/BGMApp/Images.xcassets/AppIcon.appiconset/)
  - DeviceIcon.icns, built from the same master art via `iconutil`
  - WavecraftIcon.pdf, the monochrome menu-bar status icon
    (BGMApp/BGMApp/Images.xcassets/WavecraftIcon.imageset/)

The exact colors and bar geometry below were reverse-derived by measuring the actual pixels of the
currently-shipped appicon_1024.png (color-matching against the background fill to find each bar's
bounding box), not guessed or copied from an earlier, uncommitted version of this script -- see
docs/LESSONS.md for why that distinction matters here (the original generator was never committed,
only described in a commit message, which is exactly the gap this script exists to close). Re-running
this WILL NOT necessarily produce byte-identical output to what's currently shipped -- antialiasing
and exact corner rendering can differ slightly by Pillow/reportlab version -- so treat its output as
a faithful regeneration of the design, not a guaranteed no-op diff. Run tools/verify-icons.py after
regenerating to confirm the results are structurally correct (dimensions, valid icns), and actually
look at the output before committing it -- verify-icons.py checks sizes, not that it still looks right.

Usage:
    python3 tools/generate-icons.py [--out-dir DIR]

By default writes directly into the real asset locations. Pass --out-dir to render into a scratch
directory instead, for reviewing before overwriting anything real.

Requires: Pillow, reportlab (`pip install pillow reportlab`), and `iconutil` (part of Xcode's
command line tools, only used for the .icns step). If run inside a sandboxed environment (e.g. an
AI coding agent's shell), `iconutil` can fail with a bare "Failed to generate ICNS." and no other
detail -- that's a sandbox permission issue, not a real iconutil failure; run unsandboxed instead
of debugging the .icns generation code.
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent

# Colors measured directly from BGMApp/BGMApp/Images.xcassets/AppIcon.appiconset/appicon_1024.png.
BACKGROUND = (0x1A, 0x18, 0x16)
BAR_COLORS = [
    (0xE8, 0xB0, 0x4B),  # gold -- leftmost bar
    (0xD6, 0x5A, 0x44),  # red -- tallest bar
    (0x4A, 0x9B, 0x8E),  # teal -- shortest bar
    (0x8B, 0x4A, 0x6B),  # mauve -- rightmost bar
]

# Bar geometry as a fraction of canvas size, measured the same way (bar width, gap, and each bar's
# height as fractions of the 1024px master this was derived from -- scale-independent).
BAR_WIDTH_FRAC = 106 / 1024
GAP_FRAC = 64 / 1024
BOTTOM_MARGIN_FRAC = 206 / 1024
CORNER_RADIUS_FRAC = 20 / 1024
BAR_HEIGHT_FRACS = [318 / 1024, 538 / 1024, 232 / 1024, 416 / 1024]  # gold, red, teal, mauve, in order

APPICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# Menu-bar status icon canvas -- see CLAUDE.md's Icons section for why this exact point size
# matches upstream's original FermataIcon.pdf canvas.
STATUS_ICON_POINTS = 283.46


def render_bars_rgba(size_px, background, bar_colors, monochrome=False):
    """Renders the four-bar glyph at size_px x size_px and returns a Pillow RGBA Image.

    monochrome=True draws solid black bars (no background fill, transparent elsewhere) for the
    menu-bar status icon; monochrome=False draws the full-color app/device icon with its
    background fill.
    """
    scale = 4  # Supersample then downsample for clean anti-aliasing, same as the original.
    hi_res = size_px * scale

    img = Image.new("RGBA", (hi_res, hi_res), background + (255,) if not monochrome else (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    bar_width = BAR_WIDTH_FRAC * hi_res
    gap = GAP_FRAC * hi_res
    bottom_margin = BOTTOM_MARGIN_FRAC * hi_res
    radius = CORNER_RADIUS_FRAC * hi_res
    total_width = 4 * bar_width + 3 * gap
    left_margin = (hi_res - total_width) / 2
    baseline_y = hi_res - bottom_margin

    fill_color = (0, 0, 0, 255) if monochrome else None

    for i, height_frac in enumerate(BAR_HEIGHT_FRACS):
        height = height_frac * hi_res
        x0 = left_margin + i * (bar_width + gap)
        x1 = x0 + bar_width
        y1 = baseline_y
        y0 = baseline_y - height
        color = fill_color if monochrome else bar_colors[i] + (255,)
        draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=color)

    return img.resize((size_px, size_px), Image.LANCZOS)


def generate_app_icon_pngs(out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    for size in APPICON_SIZES:
        img = render_bars_rgba(size, BACKGROUND, BAR_COLORS, monochrome=False)
        path = out_dir / f"appicon_{size}.png"
        img.save(path)
        print(f"Wrote {path} ({size}x{size})")


def generate_device_icns(appiconset_dir, out_path):
    # .icns needs its own iconset directory with Apple's exact filename convention -- distinct
    # from AppIcon.appiconset's own naming, even though the source renders are the same images.
    icns_sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    with tempfile.TemporaryDirectory() as tmp:
        iconset_dir = Path(tmp) / "DeviceIcon.iconset"
        iconset_dir.mkdir()

        for filename, size in icns_sizes.items():
            src = appiconset_dir / f"appicon_{size}.png"
            if not src.exists():
                raise FileNotFoundError(
                    f"{src} doesn't exist -- generate_app_icon_pngs must run first"
                )
            shutil.copyfile(src, iconset_dir / filename)

        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(out_path)],
            check=True,
        )
        print(f"Wrote {out_path}")


def generate_status_bar_icon_pdf(out_path):
    from reportlab.pdfgen import canvas as pdfcanvas

    c = pdfcanvas.Canvas(str(out_path), pagesize=(STATUS_ICON_POINTS, STATUS_ICON_POINTS))
    c.setFillColorRGB(0, 0, 0)

    bar_width = BAR_WIDTH_FRAC * STATUS_ICON_POINTS
    gap = GAP_FRAC * STATUS_ICON_POINTS
    bottom_margin = BOTTOM_MARGIN_FRAC * STATUS_ICON_POINTS
    radius = CORNER_RADIUS_FRAC * STATUS_ICON_POINTS
    total_width = 4 * bar_width + 3 * gap
    left_margin = (STATUS_ICON_POINTS - total_width) / 2

    for i, height_frac in enumerate(BAR_HEIGHT_FRACS):
        height = height_frac * STATUS_ICON_POINTS
        x = left_margin + i * (bar_width + gap)
        y = bottom_margin  # PDF's origin is bottom-left, same direction as our baseline.
        c.roundRect(x, y, bar_width, height, radius, stroke=0, fill=1)

    c.showPage()
    c.save()
    print(f"Wrote {out_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Render into this scratch directory instead of overwriting the real assets.",
    )
    args = parser.parse_args()

    if args.out_dir:
        appiconset_dir = args.out_dir / "AppIcon.appiconset"
        device_icns_path = args.out_dir / "DeviceIcon.icns"
        status_icon_pdf_path = args.out_dir / "WavecraftIcon.pdf"
    else:
        appiconset_dir = REPO_ROOT / "BGMApp/BGMApp/Images.xcassets/AppIcon.appiconset"
        device_icns_path = REPO_ROOT / "BGMDriver/BGMDriver/DeviceIcon.icns"
        status_icon_pdf_path = (
            REPO_ROOT / "BGMApp/BGMApp/Images.xcassets/WavecraftIcon.imageset/WavecraftIcon.pdf"
        )

    generate_app_icon_pngs(appiconset_dir)
    generate_device_icns(appiconset_dir, device_icns_path)
    generate_status_bar_icon_pdf(status_icon_pdf_path)

    print()
    print("Done. Run tools/verify-icons.py and actually look at the results before committing.")


if __name__ == "__main__":
    sys.exit(main())
