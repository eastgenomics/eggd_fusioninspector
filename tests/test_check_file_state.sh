#!/bin/bash

# Mock sleep, so we don't have to wait 30 seconds every time
sleep() {
    ((SLEEP_CALLED++))
    return 0
}

# Resolve paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${TEST_DIR%/tests}"

# Extract check_file_state function by name from src/code.sh
source <(awk '/^check_file_state\(\) \{/,/^}$/' "$ROOT_DIR/src/code.sh")

# Run tests
echo "Testing with 'open' state:"
SLEEP_CALLED=0
check_file_state "open"
[[ $SLEEP_CALLED -eq 1 ]] || { echo "FAIL: sleep should have been called for 'open' state"; exit 1; }

echo -e "\nTesting with 'closing' state:"
SLEEP_CALLED=0
check_file_state "closing"
[[ $SLEEP_CALLED -eq 1 ]] || { echo "FAIL: sleep should have been called for 'closing' state"; exit 1; }

echo -e "\nTesting with 'closed' state:"
SLEEP_CALLED=0
check_file_state "closed"
[[ $SLEEP_CALLED -eq 0 ]] || { echo "FAIL: sleep NOT should have been called for 'closed' state"; exit 1; }

echo "All tests passed."