#!/usr/bin/env python3
"""Rewrite YEN pbxproj membership exclusions after branding path restores."""

import sys


def normalize_entry(value):
    if value.endswith(","):
        value = value[:-1]
    if (" " in value or "+" in value) and not value.startswith('"'):
        value = f'"{value}"'
    return value


def rewrite_membership_exclusions(content, target_id, remove_entries=(), add_entries=()):
    target_marker = f"\t\t\ttarget = {target_id} /*"
    target_index = content.find(target_marker)
    if target_index == -1:
        print(f"  ERROR: Could not find PBXFileSystemSynchronizedBuildFileExceptionSet for target {target_id}")
        return None

    body_start_marker = "\t\t\tmembershipExceptions = (\n"
    body_start = content.rfind(body_start_marker, 0, target_index)
    body_end = content.rfind("\t\t\t);\n", 0, target_index)
    if body_start == -1 or body_end == -1 or body_end < body_start:
        print(f"  ERROR: Could not locate membershipExceptions body for target {target_id}")
        return None

    body_start += len(body_start_marker)
    body = content[body_start:body_end]

    normalized_lines = []
    for raw_line in body.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        stripped = normalize_entry(stripped)
        if stripped not in normalized_lines:
            normalized_lines.append(stripped)

    remove_set = {normalize_entry(entry) for entry in remove_entries}
    normalized_lines = [line for line in normalized_lines if line not in remove_set]

    for entry in add_entries:
        normalized_entry = normalize_entry(entry)
        if normalized_entry not in normalized_lines:
            normalized_lines.append(normalized_entry)

    body = "".join(f"\t\t\t\t{line},\n" for line in normalized_lines)
    return content[:body_start] + body + content[body_end:]


def main():
    if len(sys.argv) != 2:
        print("usage: rewrite-pbxproj-membership-exclusions.py <project.pbxproj>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        content = handle.read()

    content = rewrite_membership_exclusions(
        content,
        "A5B30530299BEAAA0047F10C",
        remove_entries=[
            "App/AppDelegate+Ghostty.swift",
            "Features/App Intents/GhosttyIntentError.swift",
            "YEN/Ghostty.ConfigTypes.swift",
            "YEN/GhosttyPackageMeta.swift",
            "YEN/Ghostty.Error.swift",
            "YEN/Ghostty.Event.swift",
            "YEN/Ghostty.Input.swift",
            "YEN/Ghostty.Surface.swift",
        ],
        add_entries=[
            "YEN/YEN.ConfigTypes.swift",
            "YEN/YENPackageMeta.swift",
        ],
    )
    if content is None:
        return 1

    with open(path, "w", encoding="utf-8", errors="surrogateescape") as handle:
        handle.write(content)
    return 0


if __name__ == "__main__":
    sys.exit(main())
