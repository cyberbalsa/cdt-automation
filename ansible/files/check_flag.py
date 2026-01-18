#!/usr/bin/env python3
"""
Flag checker for attack/defend scoring.

Validates that:
1. The associated service is UP (queries scoring DB)
2. A valid flag file exists in the search path
3. The flag contains the correct Red team token

Usage:
    check_flag.py --service webserver-web --path /var/www/html

Exit codes match scoring engine expectations:
- Outputs "FLAG_VALID" when flag found and service up
- Outputs "SERVICE_DOWN" when service check failed
- Outputs "FLAG_NOT_FOUND" when no valid flag exists
- Outputs "SKIP_INTERVAL" when not time to check yet
"""
import argparse
import os
import sqlite3
import sys
from pathlib import Path

# Default paths (can be overridden via arguments)
DB_PATH = '/opt/scoring-engine/dwayne.db'
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'
STATE_DIR = '/opt/scoring-engine/flag-state'


def get_service_status(db_path: str, service_name: str) -> bool:
    """Check if service passed its last check in scoring DB.

    Args:
        db_path: Path to the DWAYNE-INATOR-5000 SQLite database
        service_name: Name of the service check (e.g., "webserver-web")

    Returns:
        True if service is UP, False otherwise
    """
    try:
        conn = sqlite3.connect(db_path, timeout=5)
        cursor = conn.cursor()

        # Query the most recent result for this service
        # result_entries.status: 1 = UP, 0 = DOWN
        cursor.execute("""
            SELECT re.status
            FROM result_entries re
            JOIN team_records tr ON tr.id = re.team_record_id
            WHERE re.name = ?
              AND tr.round = (SELECT MAX(round) FROM team_records)
            LIMIT 1
        """, (service_name,))

        row = cursor.fetchone()
        conn.close()

        # status is stored as integer: 1 = true/up, 0 = false/down
        return row[0] == 1 if row else False

    except sqlite3.Error as e:
        # If we can't read the database, assume service status unknown
        print(f"DB_ERROR: {e}", file=sys.stderr)
        return False


def should_check_this_round(state_file: str, interval: int) -> bool:
    """Determine if we should check flags this round based on interval.

    Tracks a counter in a state file. Returns True every N calls.

    Args:
        state_file: Filename for state tracking (in STATE_DIR)
        interval: Check every N rounds

    Returns:
        True if this is a check round, False to skip
    """
    os.makedirs(STATE_DIR, exist_ok=True)
    state_path = os.path.join(STATE_DIR, state_file)

    try:
        with open(state_path, 'r') as f:
            count = int(f.read().strip())
    except (FileNotFoundError, ValueError):
        count = 0

    count += 1

    with open(state_path, 'w') as f:
        f.write(str(count))

    return count % interval == 0


def find_valid_flag(search_path: str, filename: str, expected_token: str) -> bool:
    """Recursively search for a valid flag file.

    Args:
        search_path: Root directory to search
        filename: Flag filename to look for
        expected_token: Expected contents of the flag file

    Returns:
        True if valid flag found, False otherwise
    """
    try:
        for root, dirs, files in os.walk(search_path):
            if filename in files:
                flag_path = os.path.join(root, filename)
                try:
                    with open(flag_path, 'r') as f:
                        content = f.read().strip()
                        if content == expected_token:
                            return True
                except (IOError, PermissionError):
                    # Can't read this file, continue searching
                    continue
    except (IOError, PermissionError):
        # Can't access search path
        pass

    return False


def main():
    parser = argparse.ArgumentParser(
        description='Check for planted flags in attack/defend scoring'
    )
    parser.add_argument(
        '--service',
        required=True,
        help='Service name to check status of (e.g., webserver-web)'
    )
    parser.add_argument(
        '--path',
        required=True,
        help='Directory to recursively search for flags'
    )
    parser.add_argument(
        '--filename',
        default='flag.txt',
        help='Flag filename to search for (default: flag.txt)'
    )
    parser.add_argument(
        '--interval',
        type=int,
        default=5,
        help='Check every N rounds (default: 5)'
    )
    parser.add_argument(
        '--db',
        default=DB_PATH,
        help='Path to scoring database'
    )
    parser.add_argument(
        '--token-file',
        default=TOKEN_FILE,
        help='Path to Red team token file'
    )

    args = parser.parse_args()

    # Load expected token
    try:
        with open(args.token_file, 'r') as f:
            expected_token = f.read().strip()
    except FileNotFoundError:
        print("TOKEN_FILE_MISSING")
        sys.exit(0)

    # Check if this is a flag-check round
    state_file = f"{args.service.replace('-', '_').replace('.', '_')}.count"
    if not should_check_this_round(state_file, args.interval):
        print("SKIP_INTERVAL")
        sys.exit(0)

    # Check if service is up
    if not get_service_status(args.db, args.service):
        print("SERVICE_DOWN")
        sys.exit(0)

    # Search for valid flag
    if find_valid_flag(args.path, args.filename, expected_token):
        print("FLAG_VALID")
    else:
        print("FLAG_NOT_FOUND")


if __name__ == '__main__':
    main()
