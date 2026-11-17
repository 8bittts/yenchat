#!/usr/bin/env python3
"""Reverse YEN's documented build.zig customizations so the overlay can be
diffed against pristine upstream in 10-update-ghostty.sh [3a/5].

Only these exact, intentional customizations are normalized:
  1. The "// YEN Custom Resources" block through "yen_custom.install();".
  2. "// YEN:" comment runs (the first line carries the marker; following
     "//" lines belong to the same comment).
  3. Branded literals: yen-vt-static.lib, libyen-vt.a, include/yen paths,
     install_subdir "yen", <yen/vt.h>, and the c_deps header keys
     .@"yen-h" / .@"yen-vt-h" (c_deps.zig is branded; this overlay is not).
Anything else left over is upstream drift and the caller fails closed.

Usage: normalize-overlay-buildzig.py <overlay build.zig>  (writes to stdout)
"""
import re
import sys

LITERALS = (
    ('"yen-vt-static.lib"', '"ghostty-vt-static.lib"'),
    ('"libyen-vt.a"', '"libghostty-vt.a"'),
    ('b.path("include/yen")', 'b.path("include/ghostty")'),
    ('b.path("include/yen/', 'b.path("include/ghostty/'),
    ('.@"yen-vt-h"', '.@"ghostty-vt-h"'),
    ('.@"yen-h"', '.@"ghostty-h"'),
    ('.install_subdir = "yen",', '.install_subdir = "ghostty",'),
    ("#include <yen/vt.h>", "#include <ghostty/vt.h>"),
)
COMMENT = re.compile(r"^\s*//")


def normalize(text: str) -> str:
    out = []
    in_block = False
    in_yen_comment = False
    for line in text.splitlines():
        if "// YEN Custom Resources" in line:
            in_block = True
        if in_block:
            if "yen_custom.install();" in line:
                in_block = False
            continue
        if re.match(r"^\s*// YEN:", line):
            in_yen_comment = True
            continue
        if in_yen_comment and COMMENT.match(line):
            continue
        in_yen_comment = False
        for yen, upstream in LITERALS:
            line = line.replace(yen, upstream)
        out.append(line)
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as fh:
        sys.stdout.write(normalize(fh.read()))
