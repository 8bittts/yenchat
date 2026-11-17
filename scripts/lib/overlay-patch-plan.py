#!/usr/bin/env python3
"""Run one declared overlay patch without interpreting shell arguments."""

import argparse
import importlib.util
import json
from pathlib import Path
import sys


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate patch-plan key: {key}")
        result[key] = value
    return result


def load_plan(path):
    plan = json.loads(Path(path).read_text(), object_pairs_hook=unique_object)
    if not isinstance(plan, dict) or not plan:
        raise ValueError("patch plan must contain at least one operation")
    for name, entry in plan.items():
        if not isinstance(entry, dict) or set(entry) != {"target", "arguments"}:
            raise ValueError(f"invalid patch operation: {name}")
        if not isinstance(entry["target"], str) or not entry["target"]:
            raise ValueError(f"missing patch target: {name}")
        arguments = entry["arguments"]
        if not isinstance(arguments, list) or not arguments:
            raise ValueError(f"missing patch arguments: {name}")
        if not all(isinstance(value, str) for value in arguments):
            raise ValueError(f"non-string patch argument: {name}")
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--patches-dir", required=True)
    parser.add_argument("--patch-tool", required=True)
    parser.add_argument("operation")
    args = parser.parse_args()
    try:
        plan = load_plan(args.plan)
        if args.operation not in plan:
            raise ValueError(f"unknown patch operation: {args.operation}")
        entry = plan[args.operation]
        if not Path(entry["target"]).is_file():
            raise ValueError(f"patch target missing — {entry['target']}")
        spec = importlib.util.spec_from_file_location("overlay_patch_file", args.patch_tool)
        if spec is None or spec.loader is None:
            raise ValueError("patch utility could not be loaded")
        patch_tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patch_tool)
        arguments = [value.replace("$PATCHES_DIR", args.patches_dir) for value in entry["arguments"]]
        return patch_tool.main(["--file", entry["target"], *arguments])
    except (OSError, ValueError) as error:
        print(f"  ERROR: overlay patch plan: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
