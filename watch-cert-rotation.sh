#!/bin/bash

set -euo pipefail

HOST_CERT="vault-agent-config/host.pem"
START_EPOCH="$(date +%s)"
LAST_SERIAL=""
LAST_ACCESSOR=""

export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

token_accessor() {
    local token
    token="$(docker exec vault-agent-cert cat /tmp/vault-token-cert 2>/dev/null || true)"
    if [ -z "$token" ]; then
        echo ""
        return
    fi
    VAULT_TOKEN=myroot vault token lookup -format=json "$token" 2>/dev/null | jq -r '.data.accessor // empty'
}

echo "Watching cert-auth Vault Agent client certificate rotation."
echo "Press Ctrl+C to stop."
echo

while true; do
    if [ ! -s "$HOST_CERT" ]; then
        echo "Waiting for ${HOST_CERT}..."
        sleep 5
        continue
    fi

    SERIAL="$(openssl x509 -in "$HOST_CERT" -noout -serial 2>/dev/null | cut -d= -f2 || true)"
    NOT_AFTER="$(openssl x509 -in "$HOST_CERT" -noout -enddate 2>/dev/null | cut -d= -f2- || true)"
    ACCESSOR="$(token_accessor)"
    ELAPSED="$(($(date +%s) - START_EPOCH))"

    if [ "$SERIAL" != "$LAST_SERIAL" ]; then
        printf '[T+%02ds] Agent cert serial: %s NotAfter: %s\n' "$ELAPSED" "$SERIAL" "$NOT_AFTER"
        LAST_SERIAL="$SERIAL"
    fi

    if [ -n "$ACCESSOR" ] && [ "$ACCESSOR" != "$LAST_ACCESSOR" ]; then
        printf '[T+%02ds] Agent re-authenticated (token accessor %s)\n' "$ELAPSED" "$ACCESSOR"
        LAST_ACCESSOR="$ACCESSOR"
    fi

    sleep 5
done
