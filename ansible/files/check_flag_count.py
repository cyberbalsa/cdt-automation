#!/usr/bin/env python3
"""
Count total planted flags for Blue team visibility.

Searches all configured flag paths and counts valid flags.
Blue team sees aggregate count but not specific locations.

Usage:
    check_flag_count.py

Output:
    "CLEAR" - No flags detected (check passes)
    "DETECTED_N" - N flags found (check fails, shown to Blue)
"""
import json
import os
import sys

CONFIG_FILE = '/opt/scoring-engine/flag-paths.json'
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'


def count_flags() -> int:
    """Count valid flags across all configured paths.

    Returns:
        Number of valid flags found
    """
    # Load token
    try:
        with open(TOKEN_FILE, 'r') as f:
            token = f.read().strip()
    except FileNotFoundError:
        return 0

    # Load flag paths configuration
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return 0

    paths = config.get('paths', {})
    filename = config.get('filename', 'flag.txt')

    count = 0
    for box_name, search_path in paths.items():
        # Search this box's flag path
        try:
            for root, dirs, files in os.walk(search_path):
                if filename in files:
                    flag_path = os.path.join(root, filename)
                    try:
                        with open(flag_path, 'r') as f:
                            if f.read().strip() == token:
                                count += 1
                                break  # Only count one flag per box
                    except (IOError, PermissionError):
                        continue
        except (IOError, PermissionError):
            continue

    return count


def main():
    count = count_flags()

    if count == 0:
        print("CLEAR")
    else:
        print(f"DETECTED_{count}")


if __name__ == '__main__':
    main()
