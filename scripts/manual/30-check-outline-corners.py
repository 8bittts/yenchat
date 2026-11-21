"""Check a shadowless window screenshot with a solid, contrasting outline.

Usage: uv run --with Pillow python scripts/manual/30-check-outline-corners.py window.png
Use a plain theme, focus the window, and capture it with screencapture -o -l.
"""

import sys

from PIL import Image, ImageDraw, ImageOps


def distance(a, b):
    return max(abs(x - y) for x, y in zip(a[:3], b[:3]))


def connects(corner):
    """Find the outline beside the left edge and follow it to the bottom."""
    size = corner.width
    background = corner.getpixel((size // 2, 0))
    candidates = [corner.getpixel((x, 0)) for x in range(size // 4)]
    opaque = [color for color in candidates if color[3] >= 240]
    if not opaque:
        return False
    ink = max(opaque, key=lambda color: distance(color, background))
    if distance(ink, background) < 55:
        return False
    mask = Image.new("L", corner.size)
    mask.putdata([int(a >= 180 and distance((r, g, b), ink) < 45)
                  for r, g, b, a in corner.getdata()])
    for x in range(size // 4):
        if mask.getpixel((x, 0)) == 1:
            ImageDraw.floodfill(mask, (x, 0), 2)
    return any(mask.getpixel((size - 1, y)) == 2 for y in range(3 * size // 4, size))


if __name__ == "__main__":
    with Image.open(sys.argv[1]) as source:
        image = source.convert("RGBA")
    size = 80
    if min(image.size) < size * 2:
        sys.exit("Capture the full window without a drop shadow.")
    results = []
    for name, frame in [("left", image), ("right", ImageOps.mirror(image))]:
        connected = connects(frame.crop((0, frame.height - size, size, frame.height)))
        print(f"bottom-{name} connected={connected}")
        results.append(connected)
    sys.exit(0 if all(results) else 1)
