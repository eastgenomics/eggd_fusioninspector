#!/bin/bash

# Mock sleep, so we don't have to wait 30 seconds every time
sleep() {
    return 0
}

# Extract check_file_state function by name from src/code.sh
source <(awk '/^check_file_state\(\) \{/,/^}$/' ../src/code.sh)

# Run tests
echo "Testing with 'open' state:"
check_file_state "open"

echo -e "\nTesting with 'closing' state:"
check_file_state "closing"

echo -e "\nTesting with 'closed' state:"
check_file_state "closed"