#!/bin/bash
# cert-migrate-demo.sh — two-Vault certificate migration demo.
#
# Scenario: vault-old and vault-new are two completely independent Vault
# servers. vault-old runs a PKI CA and issues a leaf client certificate.
# A client uses that certificate to authenticate into vault-old. Then we
# "migrate": vault-new is taught to trust vault-old's CA, and the SAME,
# UNCHANGED certificate authenticates into vault-new too.
#
# The point for the audience: certificate auth is anchored in the CA, not in
# the server. Move (or replicate) the trust anchor and every issued cert keeps
# working — no re-issuance, no client-side change, zero downtime.
#
# Run via: make cert-migrate

set -euo pipefail

# Load container engine definition (Podman Desktop by default, Docker fallback).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/engine.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

VAULT_OLD_ADDR="https://localhost:8210"
VAULT_NEW_ADDR="https://localhost:8220"
export VAULT_SKIP_VERIFY=true
ROOT_TOKEN="${VAULT_DEV_ROOT_TOKEN_ID:-myroot}"

WORK_DIR="migrate-work"
CLIENT_PEM="${WORK_DIR}/client.pem"
OLD_CA="${WORK_DIR}/old-ca.crt"

DOMAIN="migrate.demo.internal"
CLIENT_CN="app-01.${DOMAIN}"
CERT_ROLE="migrate-role"        # cert auth role name (identical on both Vaults)
POLICY_NAME="migrate-policy"    # token policy (identical on both Vaults)

COMPOSE_FILES="-f docker-compose.migrate.yml"
COMPOSE_CMD="${COMPOSE} ${COMPOSE_FILES}"

# Allow non-interactive runs (CI / recorded demos): CERT_MIGRATE_INTERACTIVE=false
INTERACTIVE="${CERT_MIGRATE_INTERACTIVE:-true}"

wait_for_user() {
    if [ "$INTERACTIVE" != "true" ]; then
        echo
        return 0
    fi
    echo
    echo -e "${DIM}Press ENTER to continue...${NC}"
    read -r
    echo
}

# Print `$ <command>` in green, then run it.
run_cmd() {
    echo -e "${GREEN}\$ $*${NC}"
    eval "$@"
}

# Print a command without running it (to preview what comes next).
show_cmd() {
    printf '%b    %s%b\n' "$DIM" "$*" "$NC"
}

banner() {
    echo -e "${BLUE}"
    echo "================================================================="
    echo "$1"
    echo "================================================================="
    echo -e "${NC}"
}

wait_for_vault() {
    local name="$1" addr="$2"
    for _ in $(seq 1 30); do
        if curl -sk "${addr}/v1/sys/health" >/dev/null 2>&1; then
            echo -e "${GREEN}${name} is up at ${addr}${NC}"
            return 0
        fi
        sleep 1
    done
    echo -e "${RED}${name} did not become healthy at ${addr}${NC}"
    return 1
}

# Login with the client certificate against a given Vault. Prints the token
# on stdout; assumes failure handling is done by the caller.
cert_login() {
    local addr="$1"
    curl -sk --cert "$CLIENT_PEM" --key "$CLIENT_PEM" \
        --request POST \
        --data "{\"name\":\"${CERT_ROLE}\"}" \
        "${addr}/v1/auth/cert/login"
}

mkdir -p "$WORK_DIR" vault-migrate-tls/old vault-migrate-tls/new
chmod 777 vault-migrate-tls/old vault-migrate-tls/new 2>/dev/null || true

clear
echo -e "${BLUE}"
echo "================================================================="
echo "Certificate migration demo — one cert, two Vaults"
echo "================================================================="
echo -e "${NC}"
echo -e "${YELLOW}The story:${NC}"
echo "   vault-old and vault-new are two COMPLETELY SEPARATE Vault servers."
echo "   vault-old owns a PKI CA and issues client certificates."
echo "   A client cert issued by vault-old authenticates into vault-old..."
echo "   ...and after migration, the SAME cert authenticates into vault-new."
echo
echo -e "${YELLOW}End-to-end picture:${NC}"
cat <<'DIAGRAM'

   ┌────────────────────────────┐          ┌────────────────────────────┐
   │  vault-old   :8210         │          │  vault-new   :8220         │
   │  (the "old" estate)        │          │  (the "new" estate)        │
   │                            │          │                            │
   │  pki/ (root CA)            │          │  pki/ (none — empty!)      │
   │  auth/cert trusts its      │          │  auth/cert trusts ...      │
   │  own CA                    │          │  ...nobody (yet)           │
   └─────────────┬──────────────┘          └─────────────▲──────────────┘
                 │ 1. issue leaf cert                     │
                 │    CN=app-01.migrate.demo.internal     │
                 ▼                                        │
        migrate-work/client.pem                           │
                 │                                        │
                 │ 2. cert login ── OK                    │
                 ├────────────────────────────────────────┤
                 │                                        │
                 │ 3. cert login ── REJECTED (before)     │
                 │ 4. register OLD CA in auth/cert  ──────┤  "the migration"
                 │ 5. cert login ── OK, same cert!        │
                 └────────────────────────────────────────┘

   The certificate never changes. What moves is the TRUST ANCHOR:
   vault-new learns to trust vault-old's CA, so every cert already
   issued by vault-old keeps working on vault-new.

DIAGRAM
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 1: Start two independent Vault servers"
echo "vault-old  -> ${VAULT_OLD_ADDR}"
echo "vault-new  -> ${VAULT_NEW_ADDR}"
echo "Both run in dev mode with TLS (dev-tls). They share NOTHING: no storage,"
echo "no PKI, no auth configuration. Two strangers on a network."
echo
# Fresh slate on every run: tear down any previous migrate containers first
# (only affects THIS compose project — vault-old / vault-new).
run_cmd "${COMPOSE_CMD} down --remove-orphans" >/dev/null 2>&1 || true
run_cmd "${COMPOSE_CMD} up -d"
echo
wait_for_vault "vault-old" "$VAULT_OLD_ADDR"
wait_for_vault "vault-new" "$VAULT_NEW_ADDR"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 2: vault-old — build the PKI estate"
echo "Everything happens on vault-old. vault-new stays untouched."
echo
echo -e "${YELLOW}2a. Mount PKI and generate the root CA${NC}"
show_cmd "vault secrets enable pki"
show_cmd "vault write pki/root/generate/internal common_name=\"old-vault.${DOMAIN}\" ttl=87600h"
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd "vault secrets enable pki"
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd \
    "vault write pki/root/generate/internal common_name=\"old-vault.${DOMAIN}\" ttl=87600h" >/dev/null
echo -e "${GREEN}root CA created (CN=old-vault.${DOMAIN}, 10-year TTL)${NC}"
wait_for_user

echo -e "${YELLOW}2b. Export the CA certificate — this file IS the trust anchor${NC}"
show_cmd "vault read -field=certificate pki/cert/ca > ${OLD_CA}"
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" vault read -field=certificate pki/cert/ca > "$OLD_CA"
openssl x509 -in "$OLD_CA" -noout -subject -dates | sed 's/^/    /'
wait_for_user

echo -e "${YELLOW}2c. Create the client-issuance role${NC}"
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd \
    "vault write pki/roles/migrate-client allowed_domains=\"${DOMAIN}\" allow_subdomains=true client_flag=true server_flag=false ttl=24h max_ttl=24h" >/dev/null
echo -e "${GREEN}role pki/roles/migrate-client created (client certs, 24h TTL)${NC}"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 3: vault-old — enable cert auth and seed a proof-of-access secret"
echo -e "${YELLOW}3a. Policy for certificate holders (identical name on both Vaults)${NC}"
echo "The policy grants exactly one read, so a successful login is provable."
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" vault policy write "$POLICY_NAME" - <<EOF
path "secret/data/migrate-demo" {
  capabilities = ["read"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
echo -e "${GREEN}policy ${POLICY_NAME} written${NC}"
wait_for_user

echo -e "${YELLOW}3b. Enable cert auth and register vault-old's OWN CA${NC}"
show_cmd "vault auth enable cert"
show_cmd "vault write auth/cert/certs/${CERT_ROLE} \\"
show_cmd "    certificate=@${OLD_CA} \\"
show_cmd "    allowed_common_names=\"*.${DOMAIN}\" token_policies=${POLICY_NAME}"
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd "vault auth enable cert" >/dev/null
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd \
    "vault write auth/cert/certs/${CERT_ROLE} certificate=@${OLD_CA} allowed_common_names=\"*.${DOMAIN}\" token_policies=${POLICY_NAME} token_no_default_policy=true" >/dev/null
echo -e "${GREEN}cert auth role '${CERT_ROLE}' registered with the old CA${NC}"
wait_for_user

echo -e "${YELLOW}3c. Seed a KV secret so we can prove real access after login${NC}"
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd \
    "vault kv put secret/migrate-demo message=\"hello from vault-old\"" >/dev/null
echo -e "${GREEN}secret/migrate-demo = \"hello from vault-old\"${NC}"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 4: Issue the leaf certificate from vault-old"
echo "This is the credential our client will carry through the whole demo."
echo
show_cmd "vault write -format=json pki/issue/migrate-client \\"
show_cmd "    common_name=${CLIENT_CN} ttl=24h"
ISSUE_JSON=$(mktemp)
VAULT_ADDR="$VAULT_OLD_ADDR" VAULT_TOKEN="$ROOT_TOKEN" vault write -format=json \
    pki/issue/migrate-client common_name="$CLIENT_CN" ttl=24h > "$ISSUE_JSON"
{
    jq -r .data.certificate "$ISSUE_JSON"
    jq -r .data.private_key "$ISSUE_JSON"
} > "$CLIENT_PEM"
rm -f "$ISSUE_JSON"
chmod 600 "$CLIENT_PEM"
echo
echo -e "${YELLOW}The issued certificate:${NC}"
openssl x509 -in "$CLIENT_PEM" -noout -subject -issuer -serial -dates | sed 's/^/    /'
echo
echo -e "${DIM}(saved as ${CLIENT_PEM} — cert + key together, like a real app credential)${NC}"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 5: Authenticate into vault-old with the certificate"
echo "The client presents its cert during the TLS handshake. Vault matches it"
echo "against the CA registered in auth/cert and returns a Vault token."
echo
echo -e "${GREEN}\$ curl --cert ${CLIENT_PEM} --key ${CLIENT_PEM} \\${NC}"
echo -e "${GREEN}       -d '{\"name\":\"${CERT_ROLE}\"}' ${VAULT_OLD_ADDR}/v1/auth/cert/login${NC}"
LOGIN_JSON=$(cert_login "$VAULT_OLD_ADDR")
OLD_TOKEN=$(echo "$LOGIN_JSON" | jq -r '.auth.client_token // empty')
if [ -z "$OLD_TOKEN" ]; then
    echo -e "${RED}login to vault-old failed:${NC}"
    echo "$LOGIN_JSON" | jq . || echo "$LOGIN_JSON"
    exit 1
fi
echo "$LOGIN_JSON" | jq '{policies: .auth.policies, ttl: .auth.lease_duration, renewable: .auth.renewable}' | sed 's/^/    /'
echo -e "${GREEN}vault-old accepted the certificate.${NC}"
echo
echo -e "${YELLOW}Prove real access — read the secret with the token we just got:${NC}"
curl -sk -H "X-Vault-Token: ${OLD_TOKEN}" \
    "${VAULT_OLD_ADDR}/v1/secret/data/migrate-demo" \
    | jq -r '.data.data.message' | sed 's/^/    message: /'
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 6: NEGATIVE CONTROL — try the same cert against vault-new"
echo "Before migration, vault-new has never heard of vault-old's CA."
echo "The exact same TLS handshake, the exact same certificate..."
echo
echo -e "${GREEN}\$ curl --cert ${CLIENT_PEM} --key ${CLIENT_PEM} ${VAULT_NEW_ADDR}/v1/auth/cert/login${NC}"
NEW_LOGIN_JSON=$(cert_login "$VAULT_NEW_ADDR" || true)
if echo "$NEW_LOGIN_JSON" | jq -e '.auth.client_token' >/dev/null 2>&1; then
    echo -e "${RED}Unexpected success — vault-new should not trust this cert yet!${NC}"
    exit 1
fi
echo -e "${RED}    REJECTED by vault-new:${NC}"
echo "$NEW_LOGIN_JSON" | jq -r '.errors // ["(no body)"] | join("; ")' | sed 's/^/    /'
echo
echo "Right now the cert is worthless on vault-new. Watch what one command changes."
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 7: THE MIGRATION — teach vault-new to trust vault-old's CA"
echo "One registration. No re-issuance, no client change, no downtime."
echo
show_cmd "vault auth enable cert"
show_cmd "vault write auth/cert/certs/${CERT_ROLE} \\"
show_cmd "    certificate=@${OLD_CA}            # <-- the SAME trust anchor \\"
show_cmd "    allowed_common_names=\"*.${DOMAIN}\" token_policies=${POLICY_NAME}"
VAULT_ADDR="$VAULT_NEW_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd "vault auth enable cert" >/dev/null
VAULT_ADDR="$VAULT_NEW_ADDR" VAULT_TOKEN="$ROOT_TOKEN" run_cmd \
    "vault write auth/cert/certs/${CERT_ROLE} certificate=@${OLD_CA} allowed_common_names=\"*.${DOMAIN}\" token_policies=${POLICY_NAME} token_no_default_policy=true" >/dev/null
echo -e "${GREEN}vault-new now trusts the SAME CA as vault-old.${NC}"
echo
echo -e "${YELLOW}Same policy + proof secret on vault-new, so the demo is symmetric:${NC}"
VAULT_ADDR="$VAULT_NEW_ADDR" VAULT_TOKEN="$ROOT_TOKEN" vault policy write "$POLICY_NAME" - <<EOF
path "secret/data/migrate-demo" {
  capabilities = ["read"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
VAULT_ADDR="$VAULT_NEW_ADDR" VAULT_TOKEN="$ROOT_TOKEN" vault kv put \
    secret/migrate-demo message="hello from vault-new" >/dev/null
echo -e "${GREEN}secret/migrate-demo = \"hello from vault-new\"${NC}"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 8: THE PAYOFF — same cert, unchanged, logs into vault-new"
echo "Same file. Same private key. Same TLS handshake. Different server."
echo
echo -e "${GREEN}\$ curl --cert ${CLIENT_PEM} --key ${CLIENT_PEM} \\${NC}"
echo -e "${GREEN}       -d '{\"name\":\"${CERT_ROLE}\"}' ${VAULT_NEW_ADDR}/v1/auth/cert/login${NC}"
NEW_LOGIN_JSON=$(cert_login "$VAULT_NEW_ADDR")
NEW_TOKEN=$(echo "$NEW_LOGIN_JSON" | jq -r '.auth.client_token // empty')
if [ -z "$NEW_TOKEN" ]; then
    echo -e "${RED}login to vault-new failed:${NC}"
    echo "$NEW_LOGIN_JSON" | jq . || echo "$NEW_LOGIN_JSON"
    exit 1
fi
echo "$NEW_LOGIN_JSON" | jq '{policies: .auth.policies, ttl: .auth.lease_duration, renewable: .auth.renewable}' | sed 's/^/    /'
echo -e "${GREEN}vault-new accepted the SAME certificate issued by vault-old.${NC}"
echo
echo -e "${YELLOW}Prove real access on vault-new:${NC}"
curl -sk -H "X-Vault-Token: ${NEW_TOKEN}" \
    "${VAULT_NEW_ADDR}/v1/secret/data/migrate-demo" \
    | jq -r '.data.data.message' | sed 's/^/    message: /'
echo
echo -e "${DIM}Certificate fingerprint (identical in Step 5 and Step 8 — it never changed):${NC}"
openssl x509 -in "$CLIENT_PEM" -noout -fingerprint -sha256 | sed 's/^/    /'
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Takeaways"
echo -e "${GREEN}1.${NC} Certificate auth is anchored in the CA, not the server."
echo -e "${GREEN}2.${NC} Registering the issuing CA in another Vault makes every"
echo "   certificate it signed valid there instantly."
echo -e "${GREEN}3.${NC} Migration = moving/replicating the trust anchor. Clients"
echo "   keep their certs; nothing needs to be re-issued."
echo -e "${GREEN}4.${NC} This is exactly how Vault migrations, DR failovers, and"
echo "   multi-cluster estates keep X.509 workloads online with zero downtime."
echo
echo "Cleanup:"
echo -e "   ${YELLOW}make stop-migrate${NC}   # stop and remove vault-old + vault-new"
echo
