#!/bin/bash

set -euo pipefail

# Load container engine definition (Podman Desktop by default, Docker fallback).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/engine.sh"

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
    vault-agent-output/myapp.log \
    vault-agent-output-cert/app.crt \
    vault-agent-output-cert/app.key \
    vault-agent-output-cert/ca.crt \
    vault-agent-output-cert/app.env \
    vault-agent-output-cert/myapp.log \
    vault-agent-config/host.pem \
    vault-agent-config/pki-ca.crt \
    mock-oidc/keys/signing-key.pem; do
    if [ -e "$artifact" ]; then
        rm -f "$artifact"
        echo "Removed $artifact"
    fi
done

echo "Stopping demo containers without deleting volumes..."
"$CONTAINER_ENGINE" compose -f docker-compose.yml -f docker-compose.cert.yml down >/dev/null 2>&1 || true

# Re-create the bind-mount output dirs with container-writable permissions.
demo_ensure_dirs

echo
echo "Reset complete."
echo "Next steps:"
echo "  - make setup      # Rebuild the demo environment"
echo "  - make preflight  # Check readiness without changing state"
