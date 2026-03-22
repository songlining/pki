#!/bin/bash

set -euo pipefail

STATUS=0

ok() {
    echo "OK: $1"
}

warn() {
    echo "WARNING: $1"
}

fail() {
    echo "ERROR: $1"
    STATUS=1
}

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "Found required command: $1"
    else
        fail "Missing required command: $1"
    fi
}

echo "=== Vault CE PKI Demo Preflight ==="
echo "Checking whether the demo environment is ready to present."
echo

for cmd in docker vault openssl jq curl; do
    check_command "$cmd"
done

if docker compose version >/dev/null 2>&1; then
    ok "docker compose is available"
else
    fail "docker compose is not available"
fi

if docker compose ps --status running --services 2>/dev/null | grep -qx "vault"; then
    ok "Vault container is running"
else
    fail "Vault container is not running. Run 'make setup' first."
fi

if docker compose ps --status running --services 2>/dev/null | grep -qx "vault-agent"; then
    ok "Vault Agent container is running"
else
    warn "Vault Agent container is not running yet"
fi

if curl -fsS http://localhost:8200/v1/sys/health >/dev/null 2>&1; then
    ok "Vault API is reachable on http://localhost:8200"
else
    fail "Vault API is not reachable on http://localhost:8200"
fi

if [ "$STATUS" -eq 0 ]; then
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=myroot

    LOCAL_VAULT_VERSION=$(vault version 2>/dev/null | head -1 || true)
    SERVER_VAULT_VERSION=$(docker exec vault vault version 2>/dev/null | head -1 || true)

    if [ -n "$LOCAL_VAULT_VERSION" ]; then
        echo "INFO: Local Vault CLI: $LOCAL_VAULT_VERSION"
    fi
    if [ -n "$SERVER_VAULT_VERSION" ]; then
        echo "INFO: Vault server container: $SERVER_VAULT_VERSION"
    fi

    if vault read pki/roles/web-server >/dev/null 2>&1; then
        ok "Manual PKI role 'web-server' is configured"
    else
        warn "Manual PKI role 'web-server' is missing. Run 'make demo' or './vault-init.sh'."
    fi

    if vault read auth/approle/role/vault-agent-role >/dev/null 2>&1; then
        ok "Vault Agent AppRole is configured"
    else
        warn "Vault Agent AppRole is missing. Run 'make setup-agent'."
    fi

    if vault read pki/roles/example-role >/dev/null 2>&1; then
        ok "Vault Agent issuance role 'example-role' is configured"
    else
        warn "Vault Agent issuance role 'example-role' is missing. 'make agent-demo' will create it."
    fi

    if docker compose ps --status running --services 2>/dev/null | grep -qx "vault-agent"; then
        if docker exec vault-agent test -s /tmp/vault-token; then
            ok "Vault Agent already has an authenticated token"
        else
            warn "Vault Agent token file is missing or empty"
        fi

        if docker exec vault-agent sh -c 'test -s /vault/agent/app.crt && test -s /vault/agent/app.key && test -s /vault/agent/ca.crt' >/dev/null 2>&1; then
            ok "Vault Agent has rendered certificate, key, and CA files"
        else
            warn "Vault Agent has not rendered all output files yet"
        fi
    fi

    if [ ! -f "vault-agent-config/secret-id" ]; then
        echo "INFO: Host secret-id file may disappear after Vault Agent consumes it for bootstrap."
    fi
fi

echo
if [ "$STATUS" -eq 0 ]; then
    ok "Demo environment is ready"
    echo "Suggested entrypoints:"
    echo "  - Live story:       make live-demo"
    echo "  - Hands-on path:    make workshop-demo"
    echo "  - Operator path:    make operator-demo"
    echo "  - Safe reset path:  make reset-demo"
else
    echo "Fix the errors above, then re-run 'make preflight' or 'make setup'."
fi

exit "$STATUS"
