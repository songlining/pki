#!/bin/bash
# simulate-ci-bootstrap.sh — pretends to be a GitLab CI job that mints the
# initial host credential. NO Vault root token. NO static client secret. The
# CI runner proves its identity by presenting an id_token (CI_JOB_JWT_V2) that
# Vault verifies against the OIDC provider's JWKS.
#
# Real production:  GitLab issues the id_token, Vault verifies via GitLab JWKS.
# Demo:             mock-oidc plays the role of GitLab's id_token signer.

set -euo pipefail

# Load container engine definition (Podman Desktop by default, Docker fallback).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/engine.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# What the simulated CI job claims about itself. Defaults pass the bound_claims
# in the gitlab-host-bootstrap role; override to test failure modes.
PROJECT_PATH="${PROJECT_PATH:-acme/trading-platform/agent}"
REF="${REF:-main}"
REF_TYPE="${REF_TYPE:-branch}"
REF_PROTECTED="${REF_PROTECTED:-true}"
AUDIENCE="${AUDIENCE:-vault-pki-bootstrap}"

HOST_COMMON_NAME="${HOST_COMMON_NAME:-host-01.trading.demo.internal}"
HOST_TTL="${HOST_TTL:-24h}"

# From the host (outside the container network) the mock OIDC and Vault listen on
# their published ports. Inside the network they'd be mock-oidc:8080 / vault:8200.
MOCK_OIDC_URL="${MOCK_OIDC_URL:-http://localhost:8080}"
export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"
unset VAULT_TOKEN  # the whole point: no root token in CI

CONFIG_DIR="vault-agent-config"
HOST_PEM="${CONFIG_DIR}/host.pem"
HOST_CA="${CONFIG_DIR}/pki-ca.crt"
JWT_FILE="$(mktemp)"
JWT_RESP="$(mktemp)"
LOGIN_JSON="$(mktemp)"
ISSUE_JSON="$(mktemp)"
HOST_PEM_TMP="$(mktemp "${CONFIG_DIR}/host.pem.XXXXXX")"
HOST_CA_TMP="$(mktemp "${CONFIG_DIR}/pki-ca.crt.XXXXXX")"

cleanup() {
    rm -f "$JWT_FILE" "$JWT_RESP" "$LOGIN_JSON" "$ISSUE_JSON" \
          "$HOST_PEM_TMP" "$HOST_CA_TMP"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR"

echo -e "${BLUE}=== Simulated GitLab CI host bootstrap ===${NC}"
echo "  project_path  = ${PROJECT_PATH}"
echo "  ref           = ${REF} (${REF_TYPE}, protected=${REF_PROTECTED})"
echo "  audience      = ${AUDIENCE}"
echo "  common_name   = ${HOST_COMMON_NAME}"
echo

# --- Step 1: get a signed id_token from the mock OIDC issuer ----------------
echo -e "${YELLOW}1. Asking mock OIDC for a signed id_token (simulates GitLab Runner)...${NC}"
HTTP_CODE=$(curl -s -o "$JWT_RESP" -w "%{http_code}" \
    -X POST "${MOCK_OIDC_URL}/token" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc \
        --arg p "$PROJECT_PATH" \
        --arg r "$REF" \
        --arg t "$REF_TYPE" \
        --arg pr "$REF_PROTECTED" \
        --arg a "$AUDIENCE" \
        '{project_path:$p,ref:$r,ref_type:$t,ref_protected:$pr,aud:$a}')")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}mock-oidc returned HTTP ${HTTP_CODE}:${NC}"
    cat "$JWT_RESP"
    exit 1
fi

jq -r .token "$JWT_RESP" > "$JWT_FILE"
JWT=$(cat "$JWT_FILE")
echo -e "${GREEN}   got JWT ($(wc -c < "$JWT_FILE" | tr -d ' ') bytes)${NC}"

# Decode header + payload for the audience to see what's in the token.
# JWTs use base64url (no padding, _- instead of /+). Normalise before piping.
b64url_decode() {
    local s="$1"
    local pad=$(( (4 - ${#s} % 4) % 4 ))
    local i
    for ((i=0; i<pad; i++)); do s="${s}="; done
    printf '%s' "$s" | tr '_-' '/+' | base64 -d 2>/dev/null
}
JWT_HEADER=$(b64url_decode "$(echo "$JWT" | cut -d. -f1)")
JWT_PAYLOAD=$(b64url_decode "$(echo "$JWT" | cut -d. -f2)")
JWT_SIG_LEN=$(echo "$JWT" | cut -d. -f3 | wc -c | tr -d ' ')

# Convert exp epoch -> human-readable (BSD/GNU date compatible).
JWT_EXP=$(echo "$JWT_PAYLOAD" | jq -r .exp)
if date -r 0 >/dev/null 2>&1; then
    JWT_EXP_HUMAN=$(date -r "$JWT_EXP" -u '+%Y-%m-%dT%H:%M:%SZ')   # BSD/macOS
else
    JWT_EXP_HUMAN=$(date -u -d "@$JWT_EXP" '+%Y-%m-%dT%H:%M:%SZ')  # GNU
fi

echo "   structure:  <base64url-header>.<base64url-payload>.<base64url-signature>"
echo "               signature length: ${JWT_SIG_LEN} chars (RS256, ~256-byte RSA sig)"
echo
echo "   header (alg + key id Vault uses to verify):"
echo "$JWT_HEADER" | jq . | sed 's/^/     /'
echo
echo "   payload (bound_claims will match against these):"
echo "$JWT_PAYLOAD" \
    | jq --arg exp_human "$JWT_EXP_HUMAN" \
        '{iss, aud, sub, project_path, ref, ref_type, ref_protected, exp, exp_human: $exp_human}' \
    | sed 's/^/     /'
echo

# --- Step 2: exchange the JWT for a Vault token via jwt-gitlab --------------
echo -e "${YELLOW}2. Logging into Vault at ${VAULT_ADDR} via auth/jwt-gitlab (no root token)...${NC}"
HTTP_CODE=$(curl -sk -o "$LOGIN_JSON" -w "%{http_code}" \
    -X POST "${VAULT_ADDR}/v1/auth/jwt-gitlab/login" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg jwt "$JWT" --arg role gitlab-host-bootstrap \
        '{jwt:$jwt, role:$role}')")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}Vault login rejected the JWT (HTTP ${HTTP_CODE}):${NC}"
    jq . "$LOGIN_JSON" 2>/dev/null || cat "$LOGIN_JSON"
    echo
    echo -e "${YELLOW}Tail of the Vault audit log (last 5 entries):${NC}"
    "$CONTAINER_ENGINE" exec vault sh -c 'tail -n 5 /vault/logs/audit.log' 2>/dev/null | \
        jq -c '{type, request:{path:.request.path, remote_address:.request.remote_address}, response:{mount_type:.response.mount_type}, error}' 2>/dev/null \
        || "$CONTAINER_ENGINE" exec vault sh -c 'tail -n 5 /vault/logs/audit.log' 2>/dev/null \
        || echo "  (audit log unavailable)"
    exit 1
fi

BOOTSTRAP_TOKEN=$(jq -r .auth.client_token "$LOGIN_JSON")
TOKEN_ACCESSOR=$(jq -r .auth.accessor "$LOGIN_JSON")
TOKEN_TTL=$(jq -r .auth.lease_duration "$LOGIN_JSON")
TOKEN_POLICIES=$(jq -r '.auth.token_policies | join(",")' "$LOGIN_JSON")
echo -e "${GREEN}   Vault accepted the JWT.${NC}"
echo "   token accessor:  ${TOKEN_ACCESSOR}"
echo "   policies:        ${TOKEN_POLICIES}"
echo "   ttl (seconds):   ${TOKEN_TTL}"
echo

# --- Step 3: use the scoped token to mint exactly one bootstrap cert --------
echo -e "${YELLOW}3. Using the bootstrap token to issue ${HOST_COMMON_NAME} from pki/issue/host-bootstrap-role...${NC}"
HTTP_CODE=$(curl -sk -o "$ISSUE_JSON" -w "%{http_code}" \
    -X POST "${VAULT_ADDR}/v1/pki/issue/host-bootstrap-role" \
    -H "X-Vault-Token: ${BOOTSTRAP_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg cn "$HOST_COMMON_NAME" --arg ttl "$HOST_TTL" \
        '{common_name:$cn, ttl:$ttl}')")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}pki issuance failed (HTTP ${HTTP_CODE}):${NC}"
    jq . "$ISSUE_JSON" 2>/dev/null || cat "$ISSUE_JSON"
    exit 1
fi

{
    jq -r .data.certificate "$ISSUE_JSON"
    jq -r .data.private_key "$ISSUE_JSON"
} > "$HOST_PEM_TMP"
jq -r .data.issuing_ca "$ISSUE_JSON" > "$HOST_CA_TMP"

chmod 644 "$HOST_PEM_TMP"
chmod 644 "$HOST_CA_TMP"
mv "$HOST_PEM_TMP" "$HOST_PEM"
mv "$HOST_CA_TMP" "$HOST_CA"

ISSUED_SERIAL=$(jq -r .data.serial_number "$ISSUE_JSON")
CA_CHAIN_LEN=$(jq -r '.data.ca_chain | length' "$ISSUE_JSON")
echo -e "${GREEN}   Vault returned a PKI issuance bundle:${NC}"
echo "     .data.certificate   -> leaf X.509 cert (CN=${HOST_COMMON_NAME})"
echo "     .data.private_key   -> matching key, generated server-side, sent only once"
echo "     .data.issuing_ca    -> CA cert that signed the leaf"
echo "     .data.serial_number = ${ISSUED_SERIAL}"
echo "     .data.ca_chain      = ${CA_CHAIN_LEN} intermediate(s)"
echo -e "${GREEN}   wrote ${HOST_PEM} (cert+key) and ${HOST_CA} (issuing CA)${NC}"
echo

# --- Step 4: revoke the bootstrap token now that the cert is on disk -------
echo -e "${YELLOW}4. Revoking the bootstrap Vault token (cert is the credential from here on)...${NC}"
curl -sk -X POST "${VAULT_ADDR}/v1/auth/token/revoke-self" \
    -H "X-Vault-Token: ${BOOTSTRAP_TOKEN}" >/dev/null
echo -e "${GREEN}   bootstrap token revoked${NC}"
echo

echo -e "${BLUE}Issued host certificate:${NC}"
openssl x509 -in "$HOST_PEM" -noout -subject -serial -dates
echo
echo -e "${GREEN}Bootstrap complete. Next: 'make agent-demo-cert' picks up host.pem and starts auto_auth.${NC}"
