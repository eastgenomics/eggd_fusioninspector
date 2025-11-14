#!/bin/bash

# Mock sleep, so we don't have to wait 30 seconds every time
sleep() {
    return 0
}

check_file_state() {
       local file_state="$1"
    
       if [[ $file_state != "closed" ]]; then
              echo "Notice: File state is not closed. State is '$file_state' - calling sleep 30"
              sleep 30
              echo "Notice: Sleep completed, continuing execution"
       else
              echo "File state is 'closed' - no sleep needed"
       fi
}

echo "==== Testing 'open' file state: ===="
check_file_state "open"
echo ""
echo "==== Testing 'closing' file state: ===="
check_file_state "closing"
echo ""
echo "==== Testing 'closed' file state: ===="
check_file_state "closed"