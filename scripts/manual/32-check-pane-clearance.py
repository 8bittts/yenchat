"""Check a right split with cyan-background TEST cells at all four grid corners.

Capture a shadowless two-pane window at 2x with the focused border set to 8 pt.
Print TEST at columns 1 and (columns - 3) on the first and last terminal rows.
Run with uv run --with pillow python scripts/manual/32-check-pane-clearance.py capture.png.
"""
import sys

from PIL import Image

with Image.open(sys.argv[1]) as source:
    image = source.convert("RGB")
width, height = image.size
middle = 3 * width // 4
background = image.getpixel((middle, height // 2))

def is_border(x, y):
    color = image.getpixel((x, y))
    return max(abs(a - b) for a, b in zip(color, background)) > 60

top = next(y for y in range(70, height // 3) if is_border(middle, y))
bottom = next(y for y in reversed(range(height // 2, height)) if is_border(middle, y))
left = next(x for x in range(width // 2, middle) if is_border(x, height // 2))
right = next(x for x in reversed(range(middle, width)) if is_border(x, height // 2))
stroke = next(dx for dx in range(1, 32) if not is_border(left + dx, height // 2))
assert 14 <= stroke <= 18, f"Use an 8 pt border at 2x (found {stroke} pixels)"
for x0, x1 in [(left, middle), (middle, right)]:
    for y0, y1 in [(top, height // 2), (height // 2, bottom)]:
        cyan = []
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b = image.getpixel((x, y))
                if g > r + 50 and b > g and b - g < 30:
                    cyan.append((x, y))
        assert cyan, "Missing corner label"
        gap = min(min(x-left, right-x, y-top, bottom-y) for x, y in cyan) - stroke
        print(f"Corner ({x0}, {y0}) clearance: {gap} pixels")
        if gap < 4:
            sys.exit("A corner cell needs at least two points inside the stroke.")
