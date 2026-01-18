#!/usr/bin/env python3
"""
Flag Checker - Validates planted flags for attack/defend scoring.

==============================================================================
WHAT IS THIS?
==============================================================================
In attack/defend CTF competitions, Red Team earns points by:
1. Compromising a Blue Team box (gaining access)
2. Planting a "flag" file containing their secret token
3. Keeping that flag in place while the service stays UP

This script validates flags by checking three things:
1. Is the associated service UP? (queries the scoring database)
2. Does a flag file exist in the search path?
3. Does the flag contain the correct Red team token?

WHY REQUIRE SERVICE UP?
Without this check, Red Team could just destroy services to deny Blue Team
points, then plant flags on broken boxes. By requiring the service to be UP,
Red Team must be stealthy - they need to maintain access WITHOUT breaking
the service. This creates a more interesting competition!

==============================================================================
PYTHON CONCEPTS USED
==============================================================================

1. ARGPARSE MODULE
   Handles command-line arguments professionally. Instead of manually parsing
   sys.argv, argparse gives us --help for free, validates inputs, and makes
   the script self-documenting.

2. SQLITE3 MODULE
   SQLite is a simple file-based database. The scoring engine stores results
   in a .db file. We query it to check if services are up.

3. OS.WALK()
   Recursively walks through a directory tree. For each directory, it gives
   us: (current_path, subdirectories, files). Perfect for finding files
   anywhere in a directory hierarchy.

4. TYPE HINTS (str, int, bool, etc.)
   The ": str" and "-> bool" annotations tell readers (and tools) what types
   are expected. Python doesn't enforce these, but they make code clearer.

5. TRY/EXCEPT (Exception Handling)
   When something might fail (file not found, database error), we "try" it
   and "except" (catch) specific errors to handle them gracefully.

==============================================================================
USAGE
==============================================================================
    check_flag.py --service webserver-web --path /var/www/html

OUTPUT (one of these strings):
    FLAG_VALID      - Flag found, service up, Red Team scores!
    SERVICE_DOWN    - Service failed its check, no flag points
    FLAG_NOT_FOUND  - No valid flag file in the search path
    SKIP_INTERVAL   - Not time to check yet (rate limiting)
    TOKEN_FILE_MISSING - Server misconfigured, no token file
"""

# ==============================================================================
# IMPORTS
# ==============================================================================
# Standard library modules - these come with Python, no pip install needed

import argparse      # Command-line argument parsing
import os            # Operating system interface (files, directories)
import sqlite3       # SQLite database access
import sys           # System-specific parameters and functions
from pathlib import Path  # Object-oriented filesystem paths (unused but useful)

# ==============================================================================
# CONFIGURATION CONSTANTS
# ==============================================================================
# Constants are typically UPPERCASE by Python convention.
# These are default values that can be overridden via command-line arguments.

# Path to the scoring engine's SQLite database file
# The scoring engine (DWAYNE-INATOR-5000) stores all results here
DB_PATH = '/opt/scoring-engine/dwayne.db'

# Path to the Red team's secret token file
# This file contains the random string Red Team must put in their flags
TOKEN_FILE = '/opt/scoring-engine/red-token.txt'

# Directory where we store round counters for rate limiting
# Each service gets a file like "webserver_web.count" with a number
STATE_DIR = '/opt/scoring-engine/flag-state'


# ==============================================================================
# DATABASE FUNCTIONS
# ==============================================================================

def get_service_status(db_path: str, service_name: str) -> bool:
    """
    Check if a service passed its most recent check in the scoring database.

    HOW THE SCORING DATABASE WORKS:
    The DWAYNE-INATOR-5000 scoring engine stores results in SQLite tables:
    - team_records: One row per team per round (round number, team ID, etc.)
    - result_entries: One row per service check (service name, status, etc.)

    The status field is stored as an integer:
    - 1 = UP (service passed the check)
    - 0 = DOWN (service failed the check)

    SQL EXPLAINED:
    The query joins team_records and result_entries to find the most recent
    status for a specific service. The subquery finds the maximum round
    number, ensuring we get the latest result.

    Args:
        db_path: Full filesystem path to the SQLite database file
        service_name: The name of the service check (e.g., "webserver-web")
                     This matches the "name" field in result_entries

    Returns:
        True if the service is UP, False if DOWN or we can't determine status
    """
    try:
        # Connect to SQLite database with a 5-second timeout
        # timeout prevents hanging if database is locked by another process
        conn = sqlite3.connect(db_path, timeout=5)

        # A cursor is like a pointer for executing SQL and fetching results
        cursor = conn.cursor()

        # Execute our SQL query
        # The ? is a parameter placeholder - NEVER use string formatting for SQL!
        # String formatting leads to SQL injection vulnerabilities.
        cursor.execute("""
            SELECT re.status
            FROM result_entries re
            JOIN team_records tr ON tr.id = re.team_record_id
            WHERE re.name = ?
              AND tr.round = (SELECT MAX(round) FROM team_records)
            LIMIT 1
        """, (service_name,))
        # Note: (service_name,) is a tuple with one element - the comma is required!

        # fetchone() gets one row, or None if no results
        row = cursor.fetchone()

        # Always close database connections when done
        conn.close()

        # If we got a row, check if status is 1 (UP)
        # row[0] accesses the first (and only) column we selected
        return row[0] == 1 if row else False

    except sqlite3.Error as e:
        # Database errors (file not found, corruption, locked, etc.)
        # Print to stderr so it doesn't interfere with stdout output
        print(f"DB_ERROR: {e}", file=sys.stderr)
        return False  # Assume service status unknown = not up


# ==============================================================================
# RATE LIMITING / INTERVAL CHECKING
# ==============================================================================

def should_check_this_round(state_file: str, interval: int) -> bool:
    """
    Determine if we should check flags this round based on a counter.

    WHY RATE LIMIT?
    Checking flags is more expensive than simple service checks (requires
    filesystem scanning). We don't need to check every single round.
    This function implements a simple counter that returns True every
    N calls, effectively checking flags every N service check rounds.

    HOW IT WORKS:
    1. Read counter from state file (or start at 0)
    2. Increment counter
    3. Write updated counter back to file
    4. Return True if counter is divisible by interval

    Example with interval=5:
    - Round 1: count=1, 1%5=1, return False (skip)
    - Round 2: count=2, 2%5=2, return False (skip)
    - Round 3: count=3, 3%5=3, return False (skip)
    - Round 4: count=4, 4%5=4, return False (skip)
    - Round 5: count=5, 5%5=0, return True (CHECK!)
    - Round 6: count=6, 6%5=1, return False (skip)
    ...and so on

    Args:
        state_file: Filename (not path) for this service's counter
        interval: Check every N rounds (e.g., 5 = every 5th round)

    Returns:
        True if this is a check round, False to skip checking
    """
    # Create state directory if it doesn't exist
    # exist_ok=True means don't error if directory already exists
    os.makedirs(STATE_DIR, exist_ok=True)

    # Build full path: /opt/scoring-engine/flag-state/webserver_web.count
    state_path = os.path.join(STATE_DIR, state_file)

    # Try to read the current counter value
    try:
        with open(state_path, 'r') as f:
            count = int(f.read().strip())
    except FileNotFoundError:
        # File doesn't exist yet - this is the first check
        count = 0
    except ValueError:
        # File exists but doesn't contain a valid integer
        count = 0

    # Increment the counter
    count += 1

    # Write the new counter value back to the file
    with open(state_path, 'w') as f:
        f.write(str(count))

    # Check if this round is a "check round"
    # The modulo operator (%) gives the remainder of division
    # count % interval == 0 means count is evenly divisible by interval
    return count % interval == 0


# ==============================================================================
# FLAG FILE SEARCHING
# ==============================================================================

def find_valid_flag(search_path: str, filename: str, expected_token: str) -> bool:
    """
    Recursively search a directory tree for a valid flag file.

    HOW OS.WALK WORKS:
    os.walk() is a generator that yields (dirpath, dirnames, filenames) for
    each directory in the tree. It's like doing 'find /path' in bash.

    Example for /var/www:
    - First yield: ('/var/www', ['html', 'logs'], ['index.html'])
    - Second yield: ('/var/www/html', ['images'], ['page.html', 'flag.txt'])
    - Third yield: ('/var/www/html/images', [], ['logo.png'])
    - Fourth yield: ('/var/www/logs', [], ['access.log'])

    WHY RECURSIVE SEARCH?
    Red Team might hide flags in subdirectories. We search everywhere
    in the configured path to find them wherever they're hidden.

    Args:
        search_path: Root directory to start searching from
        filename: The flag filename to look for (e.g., "flag.txt")
        expected_token: The token string that must be in the flag file

    Returns:
        True if a valid flag was found, False otherwise
    """
    try:
        # os.walk() yields tuples of (current_dir, subdirs, files)
        for root, dirs, files in os.walk(search_path):
            # Check if the flag file exists in this directory
            if filename in files:
                # Build the full path to the flag file
                flag_path = os.path.join(root, filename)

                try:
                    # Try to read and validate the flag
                    with open(flag_path, 'r') as f:
                        content = f.read().strip()

                        # Check if the content matches the expected token
                        if content == expected_token:
                            return True  # Valid flag found!

                except (IOError, PermissionError):
                    # Can't read this particular file - maybe permissions issue
                    # Continue searching, there might be another flag file
                    continue

    except (IOError, PermissionError):
        # Can't access the search path at all
        # This is fine - just means no flag can be found
        pass

    return False  # No valid flag found anywhere


# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

def main():
    """
    Main entry point - parse arguments and run the flag check.

    ARGPARSE EXPLAINED:
    argparse is Python's standard library for command-line interfaces.
    It automatically:
    - Parses sys.argv into named arguments
    - Generates --help output
    - Validates required arguments
    - Provides type conversion (e.g., type=int)
    """

    # Create the argument parser with a description
    parser = argparse.ArgumentParser(
        description='Check for planted flags in attack/defend scoring'
    )

    # Define command-line arguments
    # required=True means the script will error if this isn't provided
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

    # Optional arguments have default values
    parser.add_argument(
        '--filename',
        default='flag.txt',
        help='Flag filename to search for (default: flag.txt)'
    )
    parser.add_argument(
        '--interval',
        type=int,  # Automatically converts string argument to integer
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

    # Parse the command line arguments
    # args is a Namespace object where args.service, args.path, etc. are accessible
    args = parser.parse_args()

    # -------------------------------------------------------------------------
    # STEP 1: Load the expected token from file
    # -------------------------------------------------------------------------
    try:
        with open(args.token_file, 'r') as f:
            expected_token = f.read().strip()
    except FileNotFoundError:
        # Token file doesn't exist - server is misconfigured
        print("TOKEN_FILE_MISSING")
        sys.exit(0)  # Exit code 0 because this isn't a script error

    # -------------------------------------------------------------------------
    # STEP 2: Check if this is a flag-check round (rate limiting)
    # -------------------------------------------------------------------------
    # Create a safe filename from the service name
    # Replace - and . with _ to avoid filesystem issues
    state_file = f"{args.service.replace('-', '_').replace('.', '_')}.count"

    if not should_check_this_round(state_file, args.interval):
        print("SKIP_INTERVAL")
        sys.exit(0)

    # -------------------------------------------------------------------------
    # STEP 3: Check if the associated service is UP
    # -------------------------------------------------------------------------
    if not get_service_status(args.db, args.service):
        print("SERVICE_DOWN")
        sys.exit(0)

    # -------------------------------------------------------------------------
    # STEP 4: Search for a valid flag file
    # -------------------------------------------------------------------------
    if find_valid_flag(args.path, args.filename, expected_token):
        print("FLAG_VALID")  # Red Team scores!
    else:
        print("FLAG_NOT_FOUND")


# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================
# This is a Python idiom: only run main() if this script is executed directly.
# If someone imports this file as a module, main() won't run automatically.
#
# __name__ is a special variable:
# - When script is run directly: __name__ == '__main__'
# - When script is imported: __name__ == 'check_flag' (the module name)

if __name__ == '__main__':
    main()
