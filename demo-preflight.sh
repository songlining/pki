#!/bin/bash

set -euo pipefail

# Load container engine definition (Podman Desktop by default, Docker fallback).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/engine.sh"

STATUS=0
MODE="${1:-default}"

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

# Engine-agnostic “is this named container currently running?” check.
container_running() {
    local name="$1"
    "$CONTAINER_ENGINE" ps --filter "name=^${name}$" --filter status=running -q | grep -q .
}

if [ "$MODE" = "cert" ]; then
    echo "=== Vault Cert-auth PKI Demo Preflight ==="
else
    echo "=== Vault CE PKI Demo Preflight ==="
fi
echo "Checking whether the demo environment is ready to present."
echo

for cmd in "$CONTAINER_ENGINE" vault openssl jq curl; do
    check_command "$cmd"
done

if "$CONTAINER_ENGINE" compose version >/dev/null 2>&1; then
    ok "$CONTAINER_ENGINE compose is available"
else
    fail "$CONTAINER_ENGINE compose is not available (install podman-compose, or Docker Desktop for the fallback)"
fi

if container_running vault; then
    ok "Vault container is running"
else
    if [ "$MODE" = "cert" ]; then
        fail "Vault container is not running. Run 'make setup-cert' first."
    else
        fail "Vault container is not running. Run 'make setup' first."
    fi
fi

if [ "$MODE" = "cert" ]; then
    if container_running vault-agent-cert; then
        ok "Cert-auth Vault Agent container is running"
    else
        warn "Cert-auth Vault Agent container is not running yet"
    fi
elif container_running vault-agent; then
    ok "Vault Agent container is running"
else
    warn "Vault Agent container is not running yet"
fi

if [ "$MODE" = "cert" ]; then
    HEALTH_URL="https://localhost:8200/v1/sys/health"
    CURL_OPTS=(-fsSk)
else
    HEALTH_URL="http://localhost:8200/v1/sys/health"
    CURL_OPTS=(-fsS)
fi

if curl "${CURL_OPTS[@]}" "$HEALTH_URL" >/dev/null 2>&1; then
    ok "Vault API is reachable on ${HEALTH_URL%/v1/sys/health}"
else
    fail "Vault API is not reachable on ${HEALTH_URL%/v1/sys/health}"
fi

if [ "$STATUS" -eq 0 ]; then
    if [ "$MODE" = "cert" ]; then
        export VAULT_ADDR=https://localhost:8200
        export VAULT_SKIP_VERIFY=true
    else
        export VAULT_ADDR=http://localhost:8200
    fi
    export VAULT_TOKEN=myroot

    LOCAL_VAULT_VERSION=$(vault version 2>/dev/null | head -1 || true)
    SERVER_VAULT_VERSION=$("$CONTAINER_ENGINE" exec vault vault version 2>/dev/null | head -1 || true)

    if [ -n "$LOCAL_VAULT_VERSION" ]; then
        echo "INFO: Local Vault CLI: $LOCAL_VAULT_VERSION"
    fi
    if [ -n "$SERVER_VAULT_VERSION" ]; then
        echo "INFO: Vault server container: $SERVER_VAULT_VERSION"
    fi

    if [ "$MODE" = "cert" ]; then
        if vault auth list | grep -q "cert/"; then
            ok "TLS certificate auth method is enabled"
        else
            fail "TLS certificate auth method is missing. Run 'make setup-cert'."
        fi

        if vault read pki/roles/host-role >/dev/null 2>&1; then
            ok "Host certificate issuance role 'host-role' is configured"
        else
            fail "Host certificate issuance role 'host-role' is missing. Run 'make setup-cert'."
        fi

        if vault read auth/cert/certs/host-role >/dev/null 2>&1; then
            ok "cert-auth role 'host-role' is configured"
        else
            fail "cert-auth role 'host-role' is missing. Run 'make setup-cert'."
        fi

        if vault auth list 2>/dev/null | grep -q "^jwt-gitlab/"; then
            ok "JWT auth method 'jwt-gitlab/' is enabled"
        else
            fail "JWT auth method 'jwt-gitlab/' is missing. Run 'make setup-cert'."
        fi

        if vault read auth/jwt-gitlab/role/gitlab-host-bootstrap >/dev/null 2>&1; then
            ok "JWT role 'gitlab-host-bootstrap' is configured"
        else
            fail "JWT role 'gitlab-host-bootstrap' is missing. Run 'make setup-cert'."
        fi

        if vault read pki/roles/host-bootstrap-role >/dev/null 2>&1; then
            ok "PKI role 'host-bootstrap-role' is configured"
        else
            fail "PKI role 'host-bootstrap-role' is missing. Run 'make setup-cert'."
        fi

        if vault policy read pki-bootstrap-policy >/dev/null 2>&1; then
            ok "Policy 'pki-bootstrap-policy' exists"
        else
            fail "Policy 'pki-bootstrap-policy' is missing. Run 'make setup-cert'."
        fi

        if container_running mock-oidc; then
            ok "mock-oidc container is running"
            if curl -fsS http://localhost:8080/healthz >/dev/null 2>&1; then
                ok "mock-oidc is responding on http://localhost:8080"
            else
                fail "mock-oidc is not responding on http://localhost:8080"
            fi
            if "$CONTAINER_ENGINE" exec vault wget -qO- http://mock-oidc:8080/.well-known/jwks.json 2>/dev/null | grep -q '"keys"'; then
                ok "Vault can reach mock-oidc JWKS over the container network"
            else
                fail "Vault cannot reach mock-oidc JWKS. Check the vault-network."
            fi
        else
            fail "mock-oidc container is not running. Run 'make setup-cert'."
        fi

        if [ -s "vault-agent-config/host.pem" ] && [ -s "vault-agent-config/pki-ca.crt" ]; then
            ok "Initial host certificate bundle and PKI CA are present"
            if openssl x509 -in vault-agent-config/host.pem -noout -checkend 1 >/dev/null 2>&1; then
                ok "Initial host certificate is not expired"
            else
                fail "Initial host certificate is expired. Re-run 'make setup-cert'."
            fi

            CERT_PUB="$(openssl x509 -in vault-agent-config/host.pem -noout -pubkey 2>/dev/null | openssl sha256 | awk '{print $2}')"
            KEY_PUB="$(openssl pkey -in vault-agent-config/host.pem -pubout 2>/dev/null | openssl sha256 | awk '{print $2}')"
            if [ -n "$CERT_PUB" ] && [ "$CERT_PUB" = "$KEY_PUB" ]; then
                ok "Initial host certificate and private key match"
            else
                fail "Initial host certificate and private key do not match"
            fi

            if openssl verify -CAfile vault-agent-config/pki-ca.crt vault-agent-config/host.pem >/dev/null 2>&1; then
                ok "Initial host certificate chains to the Vault PKI CA"
            else
                fail "Initial host certificate does not chain to vault-agent-config/pki-ca.crt"
            fi

            if curl -sSk --cert vault-agent-config/host.pem --key vault-agent-config/host.pem \
                --request POST --data '{"name":"host-role"}' \
                https://localhost:8200/v1/auth/cert/login | jq -e '.auth.client_token' >/dev/null 2>&1; then
                ok "Initial host certificate can authenticate through auth/cert"
            else
                fail "Initial host certificate cannot authenticate through auth/cert"
            fi
        else
            fail "Initial host certificate files are missing. Run 'make setup-cert'."
        fi

        if container_running vault-agent-cert; then
            if "$CONTAINER_ENGINE" exec vault-agent-cert test -s /tmp/vault-token-cert; then
                ok "Cert-auth Vault Agent already has an authenticated token"
            else
                warn "Cert-auth Vault Agent token file is missing or empty"
            fi

            if "$CONTAINER_ENGINE" exec vault-agent-cert sh -c 'test -s /vault/agent/app.crt && test -s /vault/agent/app.key && test -s /vault/agent/ca.crt' >/dev/null 2>&1; then
                ok "Cert-auth Vault Agent has rendered application certificate, key, and CA files"
            else
                warn "Cert-auth Vault Agent has not rendered all application output files yet"
            fi
        fi
    elif vault read pki/roles/web-server >/dev/null 2>&1; then
        ok "Manual PKI role 'web-server' is configured"
    else
        warn "Manual PKI role 'web-server' is missing. Run 'make demo' or './vault-init.sh'."
    fi

    if [ "$MODE" != "cert" ] && vault read auth/approle/role/vault-agent-role >/dev/null 2>&1; then
        ok "Vault Agent AppRole is configured"
    elif [ "$MODE" != "cert" ]; then
        warn "Vault Agent AppRole is missing. Run 'make setup-agent'."
    fi

    if [ "$MODE" != "cert" ] && vault read pki/roles/web-server >/dev/null 2>&1; then
        ok "Vault Agent issuance role 'web-server' is configured"
    elif [ "$MODE" != "cert" ]; then
        warn "Vault Agent issuance role 'web-server' is missing. 'make agent-demo' will create it."
    fi

    if [ "$MODE" != "cert" ] && container_running vault-agent; then
        if "$CONTAINER_ENGINE" exec vault-agent test -s /tmp/vault-token; then
            ok "Vault Agent already has an authenticated token"
        else
            warn "Vault Agent token file is missing or empty"
        fi

        if "$CONTAINER_ENGINE" exec vault-agent sh -c 'test -s /vault/agent/app.crt && test -s /vault/agent/app.key && test -s /vault/agent/ca.crt' >/dev/null 2>&1; then
            ok "Vault Agent has rendered certificate, key, and CA files"
        else
            warn "Vault Agent has not rendered all output files yet"
        fi
    fi

    if [ "$MODE" != "cert" ] && [ ! -f "vault-agent-config/secret-id" ]; then
        echo "INFO: Host secret-id file may disappear after Vault Agent consumes it for bootstrap."
    fi
fi

echo
if [ "$STATUS" -eq 0 ]; then
    ok "Demo environment is ready"
    if [ "$MODE" = "cert" ]; then
        echo "Suggested entrypoints:"
        echo "  - Cert-auth story:  make agent-demo-cert"
        echo "  - Rotation watch:   make watch-cert-rotation"
    else
        echo "Suggested entrypoints:"
        echo "  - Live story:       make live-demo"
        echo "  - Hands-on path:    make workshop-demo"
        echo "  - Operator path:    make operator-demo"
        echo "  - Safe reset path:  make reset-demo"
    fi
else
    if [ "$MODE" = "cert" ]; then
        echo "Fix the errors above, then re-run 'make preflight-cert' or 'make setup-cert'."
    else
        echo "Fix the errors above, then re-run 'make preflight' or 'make setup'."
    fi
fi

exit "$STATUS"
