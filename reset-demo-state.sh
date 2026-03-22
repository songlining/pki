#!/bin/bash

set -euo pipefail

echo "=== Safe Demo Reset ==="
echo "Removing known generated demo artifacts without broad wildcard deletion."

for artifact in \
    root-ca.crt \
    intermediate.csr \
    intermediate.crt \
    app-cert.pem \
    api-private-key.pem \
    ca-chain.pem \
    csr-app-key.pem \
    csr-app.csr \
    csr-app-cert.pem \
    serial.txt \
    vault-agent-output/app.crt \
    vault-agent-output/app.key \
    vault-agent-output/ca.crt \
    vault-agent-output/app.env \
    vault-agent-output/myapp.log; do
    if [ -e "$artifact" ]; then
        rm -f "$artifact"
        echo "Removed $artifact"
    fi
done

echo "Stopping demo containers without deleting volumes..."
docker compose down >/dev/null 2>&1 || true

echo
echo "Reset complete."
echo "Next steps:"
echo "  - make setup      # Rebuild the demo environment"
echo "  - make preflight  # Check readiness without changing state"
