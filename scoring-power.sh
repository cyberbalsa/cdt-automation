#!/bin/bash
# ==============================================================================
# SCORING ENGINE POWER CONTROL
# ==============================================================================
# Controls the scoring engine pause/unpause state via the admin web interface.
#
# Usage:
#   ./scoring-power.sh pause     - Pause scoring (stops checks, freezes scores)
#   ./scoring-power.sh unpause   - Unpause scoring (resumes checks)
#   ./scoring-power.sh status    - Show current scoring status
#
# Credentials are read from ansible/group_vars/scoring.yml
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
SCORING_YML="${ANSIBLE_DIR}/group_vars/scoring.yml"
INVENTORY="${ANSIBLE_DIR}/inventory/production.ini"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 {pause|unpause|status}"
    echo ""
    echo "Commands:"
    echo "  pause    - Pause the scoring engine (stops checks, freezes scores)"
    echo "  unpause  - Unpause the scoring engine (resumes checks)"
    echo "  status   - Show current scoring status"
    exit 1
}

# Get admin credentials from scoring.yml
get_admin_creds() {
    ADMIN_USER=$(grep -A3 "^scoring_admins:" "${SCORING_YML}" | grep "name:" | head -1 | awk '{print $NF}')
    ADMIN_PASS=$(grep -A3 "^scoring_admins:" "${SCORING_YML}" | grep "password:" | head -1 | sed 's/.*password: *//' | tr -d '"')
}

# Get scoring server internal IP from inventory
get_scoring_server() {
    SCORING_HOST=$(grep -A1 "^\[scoring\]" "${INVENTORY}" | tail -1 | awk '{print $1}')
    SCORING_IP=$(grep -A1 "^\[scoring\]" "${INVENTORY}" | tail -1 | grep -oP 'internal_ip=\K[0-9.]+')
    SCORING_PORT=$(grep "^scoring_port:" "${SCORING_YML}" | awk '{print $2}')
    SCORING_URL="http://${SCORING_IP}:${SCORING_PORT}"
}

# Python script for API interaction (handles form encoding properly)
run_scoring_api() {
    local action="$1"

    cd "${ANSIBLE_DIR}"
    ansible scoring -m shell -a "python3 << 'PYEOF'
import requests
import sys

url = '${SCORING_URL}'
username = '${ADMIN_USER}'
password = '${ADMIN_PASS}'
action = '${action}'

try:
    s = requests.Session()

    # Login
    resp = s.post(f'{url}/login', data={'username': username, 'password': password}, allow_redirects=True)
    if 'logout' not in resp.text.lower():
        print('LOGIN_FAILED')
        sys.exit(1)

    if action == 'pause':
        resp = s.post(f'{url}/settings/stop', allow_redirects=True)
        print('PAUSED' if resp.status_code == 200 else 'PAUSE_FAILED')
    elif action == 'unpause':
        resp = s.post(f'{url}/settings/start', allow_redirects=True)
        print('RUNNING' if resp.status_code == 200 else 'START_FAILED')
    elif action == 'status':
        resp = s.get(f'{url}/scoreboard')
        up = resp.text.count('assets/up.png')
        down = resp.text.count('assets/down.png')
        print(f'UP:{up} DOWN:{down}')
    else:
        print('INVALID_ACTION')
        sys.exit(1)

except Exception as e:
    print(f'ERROR:{e}')
    sys.exit(1)
PYEOF
" 2>/dev/null | tail -1
}

# Pause the scoring engine
pause_scoring() {
    echo -e "${YELLOW}Pausing scoring engine...${NC}"

    RESULT=$(run_scoring_api "pause")

    if [[ "$RESULT" == "PAUSED" ]]; then
        echo -e "${GREEN}Scoring engine PAUSED${NC}"
    elif [[ "$RESULT" == "LOGIN_FAILED" ]]; then
        echo -e "${RED}Login failed - check credentials${NC}"
        return 1
    else
        echo -e "${RED}Failed to pause: ${RESULT}${NC}"
        return 1
    fi
}

# Unpause/Start the scoring engine
unpause_scoring() {
    echo -e "${YELLOW}Unpausing scoring engine...${NC}"

    RESULT=$(run_scoring_api "unpause")

    if [[ "$RESULT" == "RUNNING" ]]; then
        echo -e "${GREEN}Scoring engine RUNNING${NC}"
    elif [[ "$RESULT" == "LOGIN_FAILED" ]]; then
        echo -e "${RED}Login failed - check credentials${NC}"
        return 1
    else
        echo -e "${RED}Failed to unpause: ${RESULT}${NC}"
        return 1
    fi
}

# Show current status
show_status() {
    echo "=============================================="
    echo -e "${BLUE}SCORING ENGINE STATUS${NC}"
    echo "=============================================="
    echo ""

    # Check service status
    echo -e "${YELLOW}Service Status:${NC}"
    cd "${ANSIBLE_DIR}" && ansible scoring -m shell -a "systemctl status dwayne-inator --no-pager | head -5" 2>/dev/null | tail -6

    echo ""
    echo -e "${YELLOW}Recent Logs:${NC}"
    cd "${ANSIBLE_DIR}" && ansible scoring -m shell -a "journalctl -u dwayne-inator --no-pager -n 5" 2>/dev/null | tail -6

    echo ""
    echo -e "${YELLOW}Scoreboard Status:${NC}"
    RESULT=$(run_scoring_api "status")

    if [[ "$RESULT" == "LOGIN_FAILED" ]]; then
        echo -e "  ${RED}Could not login to get status${NC}"
    elif [[ "$RESULT" =~ ^UP:([0-9]+)\ DOWN:([0-9]+)$ ]]; then
        UP_COUNT="${BASH_REMATCH[1]}"
        DOWN_COUNT="${BASH_REMATCH[2]}"
        TOTAL=$((UP_COUNT + DOWN_COUNT))
        echo "  Total Services: ${TOTAL}"
        echo -e "  UP:   ${GREEN}${UP_COUNT}${NC}"
        echo -e "  DOWN: ${RED}${DOWN_COUNT}${NC}"
    else
        echo "  Result: ${RESULT}"
    fi

    echo ""
    echo "=============================================="
}

# Main
if [ $# -lt 1 ]; then
    usage
fi

# Load configuration
get_admin_creds
get_scoring_server

echo "Scoring Server: ${SCORING_URL}"
echo ""

case "$1" in
    pause)
        pause_scoring
        ;;
    unpause)
        unpause_scoring
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac
