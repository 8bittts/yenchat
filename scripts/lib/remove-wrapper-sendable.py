#!/usr/bin/env python3
"""Remove unsafe Sendable conformance from YEN wrapper classes."""

import os
import re
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: remove-wrapper-sendable.py <Ghostty.Surface.swift|Ghostty.Inspector.swift>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    class_name = {
        "Ghostty.Surface.swift": "Surface",
        "Ghostty.Inspector.swift": "Inspector",
    }.get(os.path.basename(path))

    if class_name is None:
        print(f"  ERROR: Unknown wrapper class file for Sendable removal: {path}")
        return 1

    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        content = handle.read()

    changed = False
    sendable_decl = f"final class {class_name}: Sendable {{"
    plain_decl = f"final class {class_name} {{"
    class_decl_pattern = re.compile(rf"final\s+class\s+{re.escape(class_name)}\b[^\{{\n]*\{{")

    if sendable_decl in content:
        content = content.replace(sendable_decl, plain_decl, 1)
        changed = True

    declarations = [match.group(0) for match in class_decl_pattern.finditer(content)]
    if not declarations:
        print(f"  ERROR: {class_name} wrapper class declaration missing after Sendable patch in {path}")
        return 1
    if len(declarations) != 1:
        print(f"  ERROR: {class_name} wrapper class declaration count changed after Sendable patch in {path}")
        return 1
    if "Sendable" in declarations[0]:
        print(f"  ERROR: {class_name} wrapper Sendable conformance changed shape in {path}; update patch anchor")
        return 1
    if re.search(rf"\b{re.escape(class_name)}\s*:\s*[^\{{\n]*\bSendable\b", content):
        print(f"  ERROR: {class_name} wrapper Sendable conformance remains in {path}; update patch anchor")
        return 1
    if plain_decl not in content:
        print(f"  ERROR: {class_name} wrapper class declaration changed shape in {path}; update patch anchor")
        return 1

    if changed:
        with open(path, "w", encoding="utf-8", errors="surrogateescape") as handle:
            handle.write(content)
        print(f"    Removed Sendable conformance from {class_name} wrapper class in {path}")
    else:
        print(f"    {class_name} wrapper class Sendable conformance already removed in {path} (idempotent skip)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
