#!/usr/bin/env python3
"""
verify-icons.py

Measures the actual pixel dimensions of every icon asset and checks them
against what Contents.json declares (for AppIcon.appiconset) and what
`iconutil`/`sips` report (for DeviceIcon.icns), instead of trusting the
filenames or assuming a generation script did the right thing. Run after
regenerating any icon.

Exit 0 and prints "PASS" per check if everything measured matches what's
declared. Exit 1 and prints the specific mismatch otherwise.
"""

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APPICONSET = REPO_ROOT / "BGMApp/BGMApp/Images.xcassets/AppIcon.appiconset"
DEVICE_ICNS = REPO_ROOT / "BGMDriver/BGMDriver/DeviceIcon.icns"

failures = []


def get_png_dimensions(path):
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        capture_output=True, text=True, check=True,
    )
    width = height = None
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            width = int(line.split(":")[1].strip())
        elif line.startswith("pixelHeight:"):
            height = int(line.split(":")[1].strip())
    if width is None or height is None:
        raise RuntimeError(f"sips didn't report both dimensions for {path}")
    return width, height


def check_appiconset():
    contents_path = APPICONSET / "Contents.json"
    if not contents_path.exists():
        failures.append(f"Contents.json missing at {contents_path}")
        return

    with open(contents_path) as f:
        manifest = json.load(f)

    # Each entry declares a logical "size" (points) and a "scale" (1x/2x).
    # The actual pixel dimensions a file must have are size * scale.
    checked_files = set()
    for entry in manifest["images"]:
        filename = entry["filename"]
        size_str = entry["size"]
        scale_str = entry["scale"]

        logical_size = int(size_str.split("x")[0])
        scale = int(scale_str.rstrip("x"))
        expected_px = logical_size * scale

        file_path = APPICONSET / filename
        if not file_path.exists():
            failures.append(f"{filename}: declared in Contents.json but file doesn't exist")
            continue

        actual_w, actual_h = get_png_dimensions(file_path)

        if actual_w != expected_px or actual_h != expected_px:
            failures.append(
                f"{filename}: Contents.json entry ({size_str} @{scale_str}) implies "
                f"{expected_px}x{expected_px}px, but the file measures {actual_w}x{actual_h}px"
            )
        else:
            print(f"PASS: {filename} measures {actual_w}x{actual_h}px, matches {size_str} @{scale_str}")

        checked_files.add(filename)

    # Catch stray/unreferenced files too -- an icon that was regenerated at
    # the wrong size and left behind wouldn't show up as a Contents.json
    # mismatch, since nothing declares it.
    for png in APPICONSET.glob("*.png"):
        if png.name not in checked_files:
            failures.append(f"{png.name}: exists in the iconset but isn't referenced by Contents.json")


def check_device_icns():
    if not DEVICE_ICNS.exists():
        failures.append(f"DeviceIcon.icns missing at {DEVICE_ICNS}")
        return

    result = subprocess.run(["file", str(DEVICE_ICNS)], capture_output=True, text=True, check=True)
    if "Mac OS X icon" not in result.stdout:
        failures.append(f"DeviceIcon.icns doesn't look like a valid icns file: {result.stdout.strip()}")
    else:
        print(f"PASS: DeviceIcon.icns is a valid icns container ({result.stdout.strip().split(': ', 1)[1]})")

    # Round-trip through iconutil to confirm it actually contains readable
    # image data, not just a file with the right magic bytes.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        out_iconset = Path(tmp) / "roundtrip.iconset"
        proc = subprocess.run(
            ["iconutil", "-c", "iconset", str(DEVICE_ICNS), "-o", str(out_iconset)],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            failures.append(f"DeviceIcon.icns failed to unpack via iconutil: {proc.stderr.strip()}")
        else:
            extracted = list(out_iconset.glob("*.png"))
            if not extracted:
                failures.append("DeviceIcon.icns unpacked but contained no PNG images")
            else:
                print(f"PASS: DeviceIcon.icns unpacks to {len(extracted)} real image(s) via iconutil")


if __name__ == "__main__":
    check_appiconset()
    check_device_icns()

    print()
    if failures:
        print(f"FAIL: {len(failures)} icon check(s) failed:")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print("All icon checks passed.")
        sys.exit(0)
