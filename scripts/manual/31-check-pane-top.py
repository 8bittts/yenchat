"""Compare focused outline heights in single and split captures of the same window.

Use the same window size, theme and focus color for both captures.
Keep the right pane focused in the split capture.
"""
import sys

from PIL import Image


def outline_top(path):
    with Image.open(path) as image:
        pixels = image.convert("RGB")
        x = 3 * pixels.width // 4
        for y in range(2, pixels.height // 3):
            color = pixels.getpixel((x, y))
            if min(color) > 96 and min(pixels.getpixel((x, y - 1))) < 96:
                return (pixels.size, y)
    raise ValueError(f"No contrasting top outline in {path}")


single, split = map(outline_top, sys.argv[1:])
print(f"Single {single}, split {split}")
if single != split:
    sys.exit("The focused pane moves when the window splits.")
