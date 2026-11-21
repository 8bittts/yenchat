"""Compare focused outline heights in single and split captures of the same window.

Use the same window size, theme and focus color for both captures.
Keep the right pane focused in the split capture.
"""
import sys

from PIL import Image


def outline_top(path):
    with Image.open(path) as image:
        pixels = image.convert("RGB")
        # Sample the full stroke so a tab label or icon cannot count as an outline.
        samples = range(pixels.width * 2 // 3, pixels.width * 9 // 10, 8)
        for y in range(2, pixels.height // 3):
            if all(max(a - b for a, b in zip(pixels.getpixel((x, y)),
                                             pixels.getpixel((x, y - 1)))) > 96
                   for x in samples):
                return (pixels.size, y)
    raise ValueError(f"No contrasting top outline in {path}")


single, split = map(outline_top, sys.argv[1:])
print(f"Single {single}, split {split}")
if single != split:
    sys.exit("The focused pane moves when the window splits.")
