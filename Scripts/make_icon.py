#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns.

Written against the standard library only (zlib + struct for the PNG, then the
system `sips`/`iconutil` for the .icns), so building the icon needs no image
library installed. Shapes are drawn from signed distance fields, which gives
clean antialiasing from a single sample per pixel.
"""
import math
import os
import struct
import subprocess
import sys
import tempfile
import zlib

SIZE = 1024


def sdf_round_rect(px, py, cx, cy, hw, hh, r):
    """Signed distance to a rounded rectangle. Negative inside."""
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax, ay = max(qx, 0.0), max(qy, 0.0)
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - r


def coverage(d, softness=1.0):
    """Antialiased inside-ness from a distance, via a 1px linear ramp."""
    return min(1.0, max(0.0, 0.5 - d / softness))


def over(dst, src, alpha):
    """Source-over compositing of a solid colour onto an RGB tuple."""
    return tuple(s * alpha + d * (1.0 - alpha) for d, s in zip(dst, src))


def build_pixels():
    # Palette: an indigo-to-violet vertical gradient, light foreground.
    top = (88, 101, 242)
    bottom = (147, 91, 226)

    rows = []
    half = SIZE / 2.0
    corner = SIZE * 0.2237          # macOS squircle-ish corner radius

    # Geometry of the "snapped windows" motif.
    screen_hw = SIZE * 0.295
    screen_hh = SIZE * 0.225
    pane_gap = SIZE * 0.022
    pane_r = SIZE * 0.028
    left_w = screen_hw * 0.92
    right_w = screen_hw * 2 - left_w - pane_gap * 2

    for y in range(SIZE):
        row = bytearray()
        t = y / (SIZE - 1)
        bg = tuple(top[i] + (bottom[i] - top[i]) * t for i in range(3))
        for x in range(SIZE):
            px, py = x + 0.5, y + 0.5

            outer = sdf_round_rect(px, py, half, half, half, half, corner)
            a = coverage(outer, 1.4)
            if a <= 0.0:
                row += bytes((0, 0, 0, 0))
                continue

            colour = bg

            # Subtle top highlight so the tile does not read as flat.
            sheen = max(0.0, 1.0 - (py / (SIZE * 0.55)))
            colour = over(colour, (255, 255, 255), 0.10 * sheen * sheen)

            # Left pane: a window snapped to the left half, drawn solid.
            lcx = half - screen_hw + left_w / 2
            dl = sdf_round_rect(px, py, lcx, half, left_w / 2, screen_hh, pane_r)
            colour = over(colour, (255, 255, 255), coverage(dl) * 0.97)

            # Right column: two stacked panes, slightly recessed.
            rcx = half - screen_hw + left_w + pane_gap * 2 + right_w / 2
            pane_hh = (screen_hh * 2 - pane_gap * 2) / 4
            for sign in (-1, 1):
                cy = half + sign * (pane_hh + pane_gap)
                d = sdf_round_rect(px, py, rcx, cy, right_w / 2, pane_hh, pane_r)
                colour = over(colour, (255, 255, 255), coverage(d) * 0.62)

            r, g, b = (int(max(0, min(255, round(c)))) for c in colour)
            row += bytes((r, g, b, int(round(a * 255))))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + r for r in rows)      # filter type 0 per scanline

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
    os.makedirs(out_dir, exist_ok=True)
    icns = os.path.abspath(os.path.join(out_dir, "AppIcon.icns"))

    print("drawing 1024x1024…")
    rows = build_pixels()

    with tempfile.TemporaryDirectory() as tmp:
        master = os.path.join(tmp, "icon_1024.png")
        write_png(master, rows)

        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        # The sizes `iconutil` expects, each as 1x and 2x.
        for size in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                px = size * scale
                name = "icon_{}x{}{}.png".format(size, size, suffix)
                subprocess.run(
                    ["sips", "-z", str(px), str(px), master, "--out", os.path.join(iconset, name)],
                    check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)

    print("wrote", icns, os.path.getsize(icns), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
