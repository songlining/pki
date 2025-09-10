#!/bin/bash
# Simple app restart script for Vault Agent process supervisor

# Kill existing processes
pkill -f myapp.sh || true

# Start new process in background
nohup /bin/sh /vault/config/myapp.sh > /tmp/myapp.log 2>&1 &

# Always exit successfully
exit 0