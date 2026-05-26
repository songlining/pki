#!/bin/bash

set -euo pipefail

HOST_COMMON_NAME="${HOST_COMMON_NAME:-host-01.trading.demo.internal}"
INITIAL_HOST_CERT_TTL="${INITIAL_HOST_CERT_TTL:-60s}"

export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

CONFIG_DIR="vault-agent-config"
HOST_PEM="${CONFIG_DIR}/host.pem"
HOST_CA="${CONFIG_DIR}/pki-ca.crt"
ISSUE_JSON="$(mktemp)"
HOST_PEM_TMP="$(mktemp "${CONFIG_DIR}/host.pem.XXXXXX")"
HOST_CA_TMP="$(mktemp "${CONFIG_DIR}/pki-ca.crt.XXXXXX")"

cleanup() {
    rm -f "$ISSUE_JSON" "$HOST_PEM_TMP" "$HOST_CA_TMP"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR"

echo "Provisioning initial host certificate for ${HOST_COMMON_NAME}."
echo "This simulates the one-time GitLab/CI enrolment step; later rotations are agent-driven."

vault write -format=json pki/issue/host-role \
    common_name="$HOST_COMMON_NAME" \
    ttl="$INITIAL_HOST_CERT_TTL" \
    > "$ISSUE_JSON"

{
    jq -r .data.certificate "$ISSUE_JSON"
    jq -r .data.private_key "$ISSUE_JSON"
} > "$HOST_PEM_TMP"
jq -r .data.issuing_ca "$ISSUE_JSON" > "$HOST_CA_TMP"

chmod 600 "$HOST_PEM_TMP"
chmod 644 "$HOST_CA_TMP"
mv "$HOST_PEM_TMP" "$HOST_PEM"
mv "$HOST_CA_TMP" "$HOST_CA"

echo "Initial host credential written to ${HOST_PEM}."
openssl x509 -in "$HOST_PEM" -noout -subject -serial -dates
