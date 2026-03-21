#!/bin/bash
# Simple app restart script for Vault Agent process supervisor

# Kill existing processes
pkill -f myapp.sh || true

# Start new process in background. Append so tail -n 0 -f can keep following
# new output across restarts without replaying old lines when monitoring starts.
nohup /bin/sh /vault/config/myapp.sh >> /tmp/myapp.log 2>&1 &

# Always exit successfully
exit 0
