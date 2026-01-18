#!/usr/bin/env python3
"""
Scoreboard Validation Script for DWAYNE-INATOR-5000

This script queries the scoring engine's scoreboard and validates that all
services are reporting as UP. It's designed to be run by Ansible as a
post-deployment validation check.

Usage:
    python3 validate_scoreboard.py --url http://localhost:8080
    python3 validate_scoreboard.py --url http://localhost:8080 --wait 300 --interval 10

Exit codes:
    0 - All services are UP
    1 - One or more services are DOWN
    2 - Could not connect to scoring engine
    3 - Invalid arguments
"""

import argparse
import json
import re
import sys
import time
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError


def parse_scoreboard(html_content):
    """
    Parse the scoreboard HTML to extract service names and their status.

    Returns a list of dicts: [{"name": "dc01-ping", "status": "up"}, ...]
    """
    services = []

    # Extract check names from the HTML
    # Pattern: checkname"><div><p>SERVICE_NAME</p>
    check_pattern = r'checkname"><div><p>([^<]+)</p>'
    check_names = re.findall(check_pattern, html_content)

    # Extract status indicators (up.png or down.png)
    status_pattern = r'(up|down)\.png'
    statuses = re.findall(status_pattern, html_content)

    # Match names to statuses
    for i, name in enumerate(check_names):
        if i < len(statuses):
            services.append({
                "name": name,
                "status": statuses[i]
            })

    return services


def get_scoreboard(base_url, timeout=30):
    """
    Fetch the scoreboard page from the scoring engine.

    Returns the HTML content as a string.
    Raises URLError on connection failure.
    """
    url = f"{base_url.rstrip('/')}/scoreboard"
    request = Request(url, headers={"User-Agent": "Ansible-Validation/1.0"})

    with urlopen(request, timeout=timeout) as response:
        return response.read().decode('utf-8')


def validate_services(services):
    """
    Check if all services are UP.

    Returns a tuple: (all_passing, down_services)
    """
    down_services = [s for s in services if s["status"] == "down"]
    return len(down_services) == 0, down_services


def wait_for_green(base_url, max_wait=300, interval=10, verbose=True):
    """
    Wait for all services to report as UP.

    Args:
        base_url: Scoring engine URL
        max_wait: Maximum seconds to wait
        interval: Seconds between checks
        verbose: Print status updates

    Returns:
        Tuple of (success, services, elapsed_time)
    """
    start_time = time.time()
    last_down_count = None

    while True:
        elapsed = time.time() - start_time

        if elapsed > max_wait:
            if verbose:
                print(f"Timeout after {int(elapsed)}s waiting for services")
            return False, [], elapsed

        try:
            html = get_scoreboard(base_url)
            services = parse_scoreboard(html)
            all_passing, down_services = validate_services(services)

            current_down = len(down_services)

            if verbose and current_down != last_down_count:
                up_count = len(services) - current_down
                print(f"[{int(elapsed)}s] Services: {up_count}/{len(services)} UP")
                if down_services:
                    for svc in down_services:
                        print(f"  - {svc['name']}: DOWN")
                last_down_count = current_down

            if all_passing:
                return True, services, elapsed

            time.sleep(interval)

        except (URLError, HTTPError) as e:
            if verbose:
                print(f"[{int(elapsed)}s] Connection error: {e}")
            time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(
        description="Validate DWAYNE-INATOR-5000 scoreboard shows all services UP"
    )
    parser.add_argument(
        "--url", "-u",
        default="http://localhost:8080",
        help="Scoring engine base URL (default: http://localhost:8080)"
    )
    parser.add_argument(
        "--wait", "-w",
        type=int,
        default=0,
        help="Max seconds to wait for all services to be UP (0=no wait)"
    )
    parser.add_argument(
        "--interval", "-i",
        type=int,
        default=10,
        help="Seconds between checks when waiting (default: 10)"
    )
    parser.add_argument(
        "--json", "-j",
        action="store_true",
        help="Output results as JSON"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Suppress progress output (only show final result)"
    )

    args = parser.parse_args()

    try:
        if args.wait > 0:
            # Wait mode: keep checking until all green or timeout
            success, services, elapsed = wait_for_green(
                args.url,
                max_wait=args.wait,
                interval=args.interval,
                verbose=not args.quiet
            )
        else:
            # Single check mode
            html = get_scoreboard(args.url)
            services = parse_scoreboard(html)
            success, down_services = validate_services(services)
            elapsed = 0

        # Prepare result
        up_count = sum(1 for s in services if s["status"] == "up")
        down_count = len(services) - up_count

        result = {
            "success": success,
            "total_services": len(services),
            "up_count": up_count,
            "down_count": down_count,
            "services": services,
            "elapsed_seconds": round(elapsed, 1)
        }

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print()
            print("=" * 50)
            print("SCOREBOARD VALIDATION RESULT")
            print("=" * 50)
            print(f"Total Services: {len(services)}")
            print(f"UP:   {up_count}")
            print(f"DOWN: {down_count}")
            print()

            if success:
                print("STATUS: ALL SERVICES PASSING")
            else:
                print("STATUS: SERVICES FAILING")
                print("\nFailing services:")
                for svc in services:
                    if svc["status"] == "down":
                        print(f"  - {svc['name']}")

            print("=" * 50)

        sys.exit(0 if success else 1)

    except (URLError, HTTPError) as e:
        error_result = {
            "success": False,
            "error": f"Could not connect to scoring engine: {e}",
            "url": args.url
        }
        if args.json:
            print(json.dumps(error_result, indent=2))
        else:
            print(f"ERROR: Could not connect to scoring engine at {args.url}")
            print(f"Details: {e}")
        sys.exit(2)

    except Exception as e:
        error_result = {
            "success": False,
            "error": str(e)
        }
        if args.json:
            print(json.dumps(error_result, indent=2))
        else:
            print(f"ERROR: {e}")
        sys.exit(3)


if __name__ == "__main__":
    main()
