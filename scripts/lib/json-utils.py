#!/usr/bin/env python3
"""
json-utils.py — Shared JSON manipulation utilities

Usage:
    python3 json-utils.py get <file> <key>
    python3 json-utils.py set <file> <key> <value>
    python3 json-utils.py update <file> <key1>=<value1> [key2=value2 ...]

Examples:
    python3 json-utils.py get version.json version
    python3 json-utils.py set package.json version "0.43"
    python3 json-utils.py update version.json sha256=abc123 url=https://...
"""

import json
import sys
from pathlib import Path


def read_json(filepath: str) -> dict:
    """Read JSON file and return dict."""
    with open(filepath, 'r') as f:
        return json.load(f)


def write_json(filepath: str, data: dict, indent: str = '  '):
    """Write dict to JSON file with trailing newline."""
    with open(filepath, 'w') as f:
        # Detect if file uses tabs (like package.json)
        json.dump(data, f, indent=indent)
        f.write('\n')


def get_value(filepath: str, key: str) -> str:
    """Get a value from JSON file."""
    data = read_json(filepath)
    if key in data:
        return str(data[key])
    else:
        raise KeyError(f"Key '{key}' not found in {filepath}")


def set_value(filepath: str, key: str, value: str):
    """Set a single value in JSON file."""
    data = read_json(filepath)

    # Try to preserve original value type
    if key in data:
        original = data[key]
        if isinstance(original, bool):
            value = value.lower() in ('true', '1', 'yes')
        elif isinstance(original, int):
            value = int(value)
        elif isinstance(original, float):
            value = float(value)

    data[key] = value

    # Detect indent style
    indent = '\t' if 'package.json' in filepath else '  '
    write_json(filepath, data, indent)


def update_values(filepath: str, updates: list):
    """Update multiple values in JSON file."""
    data = read_json(filepath)

    for update in updates:
        if '=' not in update:
            raise ValueError(f"Invalid update format: {update} (expected key=value)")
        key, value = update.split('=', 1)

        # Try to preserve original value type
        if key in data:
            original = data[key]
            if isinstance(original, bool):
                value = value.lower() in ('true', '1', 'yes')
            elif isinstance(original, int):
                value = int(value)
            elif isinstance(original, float):
                value = float(value)

        data[key] = value

    # Detect indent style
    indent = '\t' if 'package.json' in filepath else '  '
    write_json(filepath, data, indent)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]
    filepath = sys.argv[2]

    if not Path(filepath).exists():
        print(f"Error: File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    try:
        if command == 'get':
            if len(sys.argv) < 4:
                print("Usage: json-utils.py get <file> <key>", file=sys.stderr)
                sys.exit(1)
            key = sys.argv[3]
            print(get_value(filepath, key))

        elif command == 'set':
            if len(sys.argv) < 5:
                print("Usage: json-utils.py set <file> <key> <value>", file=sys.stderr)
                sys.exit(1)
            key = sys.argv[3]
            value = sys.argv[4]
            set_value(filepath, key, value)

        elif command == 'update':
            if len(sys.argv) < 4:
                print("Usage: json-utils.py update <file> key=value [key=value ...]", file=sys.stderr)
                sys.exit(1)
            updates = sys.argv[3:]
            update_values(filepath, updates)

        else:
            print(f"Unknown command: {command}", file=sys.stderr)
            print(__doc__)
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
