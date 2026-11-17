#!/usr/bin/env python3
"""
patch-file.py - shared patch-and-replace utility for overlay scripts.
"""

import argparse
import os
import sys


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        return handle.read()


def write_text(path, content):
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as handle:
        handle.write(content)


def resolve_block(value):
    if value.startswith("@"):
        return read_text(value[1:])
    return value


def fail(label, message):
    print("  ERROR: {} {}".format(label, message))
    return 1


def find_anchor_index(lines, anchor):
    for idx, line in enumerate(lines):
        if anchor in line:
            return idx
    return -1


def find_in_proximity(lines, anchor_idx, target, window):
    limit = min(anchor_idx + window + 1, len(lines))
    for idx in range(anchor_idx, limit):
        if target in lines[idx]:
            return idx
    return -1


def has_required_range_patterns(content, start, end, patterns):
    if not start or not end or not patterns:
        return False

    start_idx = content.find(start)
    if start_idx == -1:
        return False

    end_idx = content.find(end, start_idx)
    if end_idx == -1:
        return False

    segment = content[start_idx:end_idx]
    for pattern in patterns:
        if pattern not in segment:
            return False
    return True


def parse_extra_replace(spec, label):
    if ":::" not in spec:
        raise ValueError(
            "invalid --extra-replace value '{}' (expected <old>:::<new>)".format(spec)
        )
    old_value, new_value = spec.split(":::", 1)
    old_text = resolve_block(old_value).rstrip("\n")
    new_text = resolve_block(new_value).rstrip("\n")
    if not old_text:
        raise ValueError(
            "invalid --extra-replace value '{}' (old block resolved empty)".format(spec)
        )
    return old_text, new_text


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--mode", required=True, choices=["exact", "proximity"])
    parser.add_argument("--label")
    parser.add_argument("--marker")
    parser.add_argument("--marker-all", action="append", default=[])
    parser.add_argument("--marker-proximity-anchor")
    parser.add_argument("--marker-proximity-window", type=int, default=5)
    parser.add_argument("--marker-proximity-substring")

    parser.add_argument("--old-block")
    parser.add_argument("--new-block")

    parser.add_argument("--proximity-anchor")
    parser.add_argument("--proximity-window", type=int, default=5)
    parser.add_argument("--proximity-old")
    parser.add_argument("--proximity-new")

    parser.add_argument("--already-valid-pattern", action="append", default=[])
    parser.add_argument("--already-valid-range-start")
    parser.add_argument("--already-valid-range-end")
    parser.add_argument("--already-valid-range-require", action="append", default=[])

    parser.add_argument("--post-verify", action="append", default=[])
    parser.add_argument("--post-verify-proximity-anchor")
    parser.add_argument("--post-verify-proximity-window", type=int, default=5)
    parser.add_argument("--post-verify-proximity-substring")
    parser.add_argument("--old-absent-ok", action="store_true")
    parser.add_argument("--old-absent-drift-pattern")

    parser.add_argument("--extra-replace", action="append", default=[])

    args = parser.parse_args(argv)

    if args.proximity_window < 0:
        parser.error("--proximity-window must be >= 0")
    if args.marker_proximity_window < 0:
        parser.error("--marker-proximity-window must be >= 0")
    if args.post_verify_proximity_window < 0:
        parser.error("--post-verify-proximity-window must be >= 0")

    marker_proximity_fields = [
        args.marker_proximity_anchor,
        args.marker_proximity_substring,
    ]
    if any(marker_proximity_fields) and not all(marker_proximity_fields):
        parser.error(
            "marker proximity requires both --marker-proximity-anchor and --marker-proximity-substring"
        )

    if args.mode == "exact":
        if args.old_block is None or args.new_block is None:
            parser.error("exact mode requires --old-block and --new-block")
    else:
        missing = []
        if args.proximity_anchor is None:
            missing.append("--proximity-anchor")
        if args.proximity_old is None:
            missing.append("--proximity-old")
        if args.proximity_new is None:
            missing.append("--proximity-new")
        if missing:
            parser.error("proximity mode requires {}".format(", ".join(missing)))

    verify_proximity_fields = [
        args.post_verify_proximity_anchor,
        args.post_verify_proximity_substring,
    ]
    if any(verify_proximity_fields) and not all(verify_proximity_fields):
        parser.error(
            "post-verify proximity requires both --post-verify-proximity-anchor and --post-verify-proximity-substring"
        )

    return args


def main(argv=None):
    args = parse_args(argv)
    label = args.label if args.label else os.path.basename(args.file)

    try:
        content = read_text(args.file)
    except OSError as exc:
        return fail(label, "failed to read {}: {}".format(args.file, exc))

    if args.marker and args.marker in content:
        print("    {} already applied (idempotent skip)".format(label))
        return 0

    if args.marker_all:
        has_all_markers = True
        for marker in args.marker_all:
            if marker not in content:
                has_all_markers = False
                break
        if has_all_markers:
            print("    {} already applied (idempotent skip)".format(label))
            return 0

    if args.marker_proximity_anchor and args.marker_proximity_substring:
        lines = content.split("\n")
        anchor_idx = find_anchor_index(lines, args.marker_proximity_anchor)
        if anchor_idx != -1:
            marker_idx = find_in_proximity(
                lines,
                anchor_idx,
                args.marker_proximity_substring,
                args.marker_proximity_window,
            )
            if marker_idx != -1:
                print("    {} already applied (idempotent skip)".format(label))
                return 0

    for pattern in args.already_valid_pattern:
        if pattern in content:
            print("    {} already present upstream (idempotent skip)".format(label))
            return 0

    if has_required_range_patterns(
        content,
        args.already_valid_range_start,
        args.already_valid_range_end,
        args.already_valid_range_require,
    ):
        print("    {} already present upstream (idempotent skip)".format(label))
        return 0

    if args.mode == "exact":
        old_block = resolve_block(args.old_block)
        new_block = resolve_block(args.new_block)
        if old_block not in content:
            if args.old_absent_ok:
                if (
                    args.old_absent_drift_pattern
                    and args.old_absent_drift_pattern in content
                ):
                    return fail(label, "patch anchor changed shape")
                print("    {} already applied (idempotent skip)".format(label))
                return 0
            return fail(label, "patch anchor not found")
        content = content.replace(old_block, new_block, 1)
    else:
        lines = content.split("\n")
        anchor_idx = find_anchor_index(lines, args.proximity_anchor)
        if anchor_idx == -1:
            return fail(label, "proximity anchor not found")

        patch_idx = find_in_proximity(
            lines, anchor_idx, args.proximity_old, args.proximity_window
        )
        if patch_idx == -1:
            return fail(label, "proximity target not found near anchor")

        lines[patch_idx] = lines[patch_idx].replace(
            args.proximity_old, args.proximity_new, 1
        )
        content = "\n".join(lines)

    for replace_spec in args.extra_replace:
        try:
            old_value, new_value = parse_extra_replace(replace_spec, label)
        except ValueError as exc:
            return fail(label, str(exc))
        if old_value not in content:
            anchor = old_value.split("\n", 1)[0]
            if len(anchor) > 120:
                anchor = "{}...".format(anchor[:120])
            return fail(
                label,
                "extra-replace anchor not found: '{}'".format(anchor),
            )
        content = content.replace(old_value, new_value)

    try:
        write_text(args.file, content)
    except OSError as exc:
        return fail(label, "failed to write {}: {}".format(args.file, exc))

    try:
        verify_content = read_text(args.file)
    except OSError as exc:
        return fail(label, "failed to verify {}: {}".format(args.file, exc))

    for pattern in args.post_verify:
        if pattern not in verify_content:
            return fail(
                label,
                "post-patch verification failed: '{}' not found".format(pattern),
            )

    if args.post_verify_proximity_anchor and args.post_verify_proximity_substring:
        verify_lines = verify_content.split("\n")
        anchor_idx = find_anchor_index(verify_lines, args.post_verify_proximity_anchor)
        if anchor_idx == -1:
            return fail(label, "post-verify anchor not found")

        verify_idx = find_in_proximity(
            verify_lines,
            anchor_idx,
            args.post_verify_proximity_substring,
            args.post_verify_proximity_window,
        )
        if verify_idx == -1:
            return fail(label, "post-verify proximity target not found near anchor")

    print("    Applied {}".format(label))
    return 0


if __name__ == "__main__":
    sys.exit(main())
