#!/bin/bash

set -euo pipefail

# Load container engine definition (Podman Desktop by default, Docker fallback).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/engine.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOST_CERT="vault-agent-config/host.pem"
APP_CERT="vault-agent-output-cert/app.crt"
AGENT_HCL="vault-agent-config/agent-cert.hcl"
HOST_TPL="vault-agent-config/host-bundle.tpl"

export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

wait_for_user() {
    echo
    echo "Press ENTER to continue..."
    read -r
    echo
}

show_file() {
    local file="$1"
    echo "   ------------------------------------------------------------------------"
    sed 's/^/   /' "$file"
    echo "   ------------------------------------------------------------------------"
}

token_accessor() {
    local token accessor
    token="$("$CONTAINER_ENGINE" exec vault-agent-cert cat /tmp/vault-token-cert 2>/dev/null || true)"
    if [ -z "$token" ]; then
        echo ""
        return 0
    fi
    accessor="$(VAULT_TOKEN=myroot vault token lookup -format=json "$token" 2>/dev/null | jq -r '.data.accessor // empty' 2>/dev/null || true)"
    echo "$accessor"
    return 0
}

cert_serial() {
    openssl x509 -in "$1" -noout -serial 2>/dev/null | cut -d= -f2 || true
}

show_host_cert() {
    openssl x509 -in "$HOST_CERT" -noout -subject -serial -dates | sed 's/^/      /'
}

wait_for_file() {
    local path="$1"
    local label="$2"
    for _ in {1..30}; do
        if [ -s "$path" ]; then
            return 0
        fi
        sleep 1
    done
    echo "Timed out waiting for ${label}."
    return 1
}

wait_for_agent_token() {
    for _ in {1..30}; do
        if "$CONTAINER_ENGINE" exec vault-agent-cert test -s /tmp/vault-token-cert >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "Timed out waiting for Vault Agent cert-auth token."
    return 1
}

clear
echo -e "${BLUE}"
echo "================================================================="
echo "Vault Agent - Cert-auth End-to-End Demo"
echo "================================================================="
echo -e "${NC}"
echo -e "${YELLOW}This walkthrough covers the full cert-auth story:${NC}"
echo "   1. TLS client-cert auto-auth (auto_auth { method \"cert\" })"
echo "   2. One-time host-cert provisioning (simulating CI enrolment)"
echo "   3. Agent-driven re-issuance of its own host credential via template"
echo "   4. Immediate re-authentication when the credential changes"
echo "   5. Restart survivability - re-auth from the cert bundle on disk"
echo
cat <<'DIAGRAM'
   Big picture (steady state, after the one-time bootstrap):

       ┌──────────────────────────────────────┐
       │  Vault Agent   (cert-auth mode)      │
       │                                      │
       │   host.pem  (cert + key on disk)     │  ◄── Agent rotates this itself
       │      │                               │        every ~25s via template
       │      ▼                               │
       │   auto_auth { method "cert" }        │
       └─────────────┬────────────────────────┘
                     │ 1 → mTLS handshake (presents client cert)
                     │ 2 ← new client_token
                     ▼
       ┌──────────────────────────────────────┐
       │  Vault   https://localhost:8200      │
       │    auth/cert/certs/host-role         │  ← trust anchor (pki-ca.crt)
       │    pki/issue/host-role               │  ← signs the next host.pem
       └──────────────────────────────────────┘

   Loop:  issue new host.pem  →  reload  →  re-auth  →  new token
   No human, no CI, no secret-id after the initial bootstrap.
DIAGRAM
echo

wait_for_file "$HOST_CERT" "initial host certificate"
wait_for_agent_token

# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}"
echo "================================================================="
echo "Step 1: TLS client-certificate auto-auth"
echo "================================================================="
echo -e "${NC}"
cat <<'DIAGRAM'
   host.pem                                  Vault
   ┌──────────────┐                          ┌─────────────────────────┐
   │ cert + key   │── 1 → mTLS, client cert ►│ auth/cert/login         │
   └──────────────┘                          │   verify chain          │
         ▲                                   │   match allowed_CN      │
         │ reload=true on file change        │                         │
         │                                   │ 2 ← issue token         │
   ┌──────────────┐◄─────── client_token ────┤   policies=pki-host     │
   │ Vault Agent  │                          │   period (renewable)    │
   └──────────────┘                          └─────────────────────────┘
DIAGRAM
echo
echo "This Agent presents an X.509 client certificate to"
echo "Vault's auth/cert method. The relevant block in ${AGENT_HCL}:"
echo
echo "   ------------------------------------------------------------------------"
awk '/^auto_auth \{/{flag=1} flag{print} flag && /^\}/{exit}' "$AGENT_HCL" | sed 's/^/   /'
echo "   ------------------------------------------------------------------------"
echo
echo "Key details:"
echo "   - method \"cert\" -> Agent calls auth/cert/login with a client cert"
echo "   - client_cert / client_key both point at host.pem (cert + key bundled)"
echo "   - reload = true   -> Agent re-reads host.pem when it changes on disk"
echo "   - enable_reauth_on_new_credentials = true -> re-auth as soon as the cert rotates"
echo
echo "On the Vault side, auth/cert/certs/host-role pins the trust anchor:"
echo
vault read auth/cert/certs/host-role 2>/dev/null \
    | grep -E "allowed_common_names|token_policies|token_period|display_name" \
    | sed 's/^/      /'
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}"
echo "================================================================="
echo "Step 2: One-time host-cert provisioning (simulating CI enrolment)"
echo "================================================================="
echo -e "${NC}"
cat <<'DIAGRAM'
   provision-host-cert.sh   (one-off, stands in for GitLab CI / Packer)
        │
        │ vault write pki/issue/host-role \
        │   common_name=host-01.trading.demo.internal ttl=60s
        ▼
   ┌─────────────────────────┐
   │ Vault  pki/issue/...    │── cert + key + issuing_ca ──┐
   └─────────────────────────┘                             │
                                                           ▼
                                       ┌──────────────────────────────┐
                                       │ host.pem (cert+key bundle on │
                                       │          shared volume)      │
                                       └──────────────┬───────────────┘
                                                      │ Agent restarts,
                                                      │ reads bundle,
                                                      ▼ does auth/cert/login
                                                Vault Agent operational
DIAGRAM
echo
echo "Before the Agent can authenticate, the host needs an initial certificate."
echo "In production this would come from your CI/enrolment system (GitLab,"
echo "Packer, cloud-init...). Here, ./provision-host-cert.sh does the equivalent:"
echo
echo "   vault write -format=json pki/issue/host-role \\"
echo "       common_name=host-01.trading.demo.internal ttl=60s"
echo
echo "The PKI role that constrains what hosts can be issued (host-role):"
echo
vault read pki/roles/host-role 2>/dev/null \
    | grep -E "allowed_domains|client_flag|server_flag|max_ttl|^ttl" \
    | sed 's/^/      /'
echo
echo "Running provisioning now (so the demo starts from a fresh, short-lived bundle)..."
INITIAL_HOST_CERT_TTL=60s ./provision-host-cert.sh >/dev/null
echo "Restarting the Agent so it adopts the freshly provisioned credential..."
"$CONTAINER_ENGINE" restart vault-agent-cert >/dev/null
wait_for_agent_token
echo
echo "The resulting bundle on disk (${HOST_CERT}):"
show_host_cert
echo
echo "This is the credential the Agent will use to bootstrap auto-auth."
echo "From here onwards, no human or CI is in the loop - the Agent takes over."

INITIAL_SERIAL="$(cert_serial "$HOST_CERT")"
INITIAL_ACCESSOR="$(token_accessor)"
echo
echo "   Initial host cert serial:     ${INITIAL_SERIAL}"
echo "   Current Agent token accessor: ${INITIAL_ACCESSOR}"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}"
echo "================================================================="
echo "Step 3: Agent-driven re-issuance via template"
echo "================================================================="
echo -e "${NC}"
cat <<'DIAGRAM'
   Vault Agent   (every ~25s, using its CURRENT token)
        │
        │ 1 → pki/issue/host-role   (ttl=30s)
        ▼
   ┌─────────────────────────┐
   │ Vault PKI  signs leaf   │
   └────────────┬────────────┘
                │ 2 ← rendered cert + key
                ▼
       host-bundle.tpl  →  host.pem   (atomic replace)
                                │
                                │ reload=true detects the file change
                                ▼
                       (Step 4 picks up here)

   In parallel, separate templates render app.crt / app.key / ca.crt
   for the workload — same Agent, same token, different roles.
DIAGRAM
echo
echo "The Agent rotates its OWN client credential by rendering host.pem from a"
echo "template. The template (${HOST_TPL}):"
echo
show_file "$HOST_TPL"
echo
echo "And the matching template stanza in ${AGENT_HCL}:"
echo
echo "   ------------------------------------------------------------------------"
awk '/^template \{/{flag=1; block=""} flag{block = block $0 ORS} flag && /^\}/{
        if (block ~ /host-bundle\.tpl/) { printf "%s", block; exit }
        flag=0
    }' "$AGENT_HCL" | sed 's/^/   /'
echo "   ------------------------------------------------------------------------"
echo
echo "What happens every ~25s:"
echo "   1. Agent uses its current token to call pki/issue/host-role (ttl=30s)"
echo "   2. The rendered cert + key replace host.pem atomically"
echo "   3. Because reload=true, the Agent re-reads host.pem"
echo "   4. enable_reauth_on_new_credentials triggers a fresh auth/cert login"
echo
wait_for_file "$APP_CERT" "application certificate"
echo -e "${GREEN}OK: Agent is also rendering app.crt / app.key / ca.crt for the workload"
echo -e "       (same Agent, separate templates, same auto-auth token).${NC}"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}"
echo "================================================================="
echo "Step 4: Immediate re-authentication on credential change"
echo "================================================================="
echo -e "${NC}"
cat <<'DIAGRAM'
       host.pem changed on disk
              │
              │ Agent file-watcher fires (reload=true)
              ▼
   ┌──────────────────────────────────────┐
   │ Vault Agent                          │
   │   enable_reauth_on_new_credentials   │
   │     = true                           │
   └────────────────┬─────────────────────┘
                    │ auth/cert/login (using the NEW cert)
                    ▼
   ┌──────────────────────────────────────┐
   │ Vault  auth/cert                     │
   │   verify chain, issue new token      │
   └────────────────┬─────────────────────┘
                    │ new client_token
                    ▼
              new accessor
   (A new accessor proves it's a fresh login, not a token renewal.)
DIAGRAM
echo
echo "Waiting up to 75s for the Agent to rotate its own host certificate..."
echo "(host.pem ttl=30s; Vault Agent renews around the 80% mark, but render"
echo " timing can slip by a cycle, so we allow up to two TTLs.)"
echo "(Watch host.pem serial AND token accessor - both must change.)"
echo
echo "   Before rotation:"
echo "      host.pem serial:  ${INITIAL_SERIAL}"
echo "      token accessor:   ${INITIAL_ACCESSOR}"
echo

ROTATED=false
for _ in {1..25}; do
    sleep 3
    CURRENT_SERIAL="$(cert_serial "$HOST_CERT")"
    CURRENT_ACCESSOR="$(token_accessor)"
    if [ -n "$CURRENT_SERIAL" ] && [ "$CURRENT_SERIAL" != "$INITIAL_SERIAL" ]; then
        ROTATED=true
        echo
        echo -e "${GREEN}   ROTATED: host.pem serial changed.${NC}"
        echo "      New host cert:"
        show_host_cert
        if [ -n "$CURRENT_ACCESSOR" ] && [ "$CURRENT_ACCESSOR" != "$INITIAL_ACCESSOR" ]; then
            echo -e "${GREEN}   RE-AUTHENTICATED: token accessor changed to ${CURRENT_ACCESSOR}.${NC}"
            echo "   (A new accessor proves a fresh auth/cert login, not a token renewal.)"
        else
            echo -e "${YELLOW}   WARNING: cert rotated, but token accessor change not observed yet.${NC}"
        fi
        break
    fi
    echo -n "."
done
echo

if [ "$ROTATED" != true ]; then
    echo "No host certificate rotation detected within the expected window."
    "$CONTAINER_ENGINE" logs vault-agent-cert --tail 80
    exit 1
fi
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}"
echo "================================================================="
echo "Step 5: Restart survivability"
echo "================================================================="
echo -e "${NC}"
cat <<'DIAGRAM'
   Agent container restarts
          │
          │ no in-memory token after restart
          ▼
   reads host.pem from mounted volume
          │
          │ auto_auth { method "cert" }  →  auth/cert/login
          ▼
   ┌──────────────────────────────┐
   │ Vault  auth/cert/login       │
   └──────────────┬───────────────┘
                  │ new token
                  ▼
          Agent operational again
   No operator, no CI, no secret-id involved.
DIAGRAM
echo
echo "If the host reboots, the Agent must be able to re-authenticate purely"
echo "from the cert bundle on disk - no operator, no CI, no secret-id."
echo
echo "Restarting the cert-auth Agent container..."
"$CONTAINER_ENGINE" restart vault-agent-cert >/dev/null
wait_for_agent_token
POST_RESTART_ACCESSOR="$(token_accessor)"

if [ -z "$POST_RESTART_ACCESSOR" ]; then
    echo "Agent did not re-authenticate after restart."
    "$CONTAINER_ENGINE" logs vault-agent-cert --tail 80
    exit 1
fi

echo -e "${GREEN}OK: Agent re-authenticated from host.pem on disk after restart.${NC}"
echo "   Post-restart token accessor: ${POST_RESTART_ACCESSOR}"
echo
echo "Why this works:"
echo "   - host.pem (cert + key) lives on a mounted volume"
echo "   - On startup, auto_auth { method \"cert\" } reads it and calls auth/cert/login"
echo "   - As long as host.pem is still valid (ttl=30s, rotated every ~25s),"
echo "     the Agent recovers without any external bootstrap"
echo
echo -e "${BLUE}"
echo "================================================================="
echo "Demo complete"
echo "================================================================="
echo -e "${NC}"
echo -e "${GREEN}Recap:${NC}"
echo "   OK: auto_auth method \"cert\" bootstrapped from the initial host.pem"
echo "   OK: Agent rotated its own host credential via host-bundle.tpl"
echo "   OK: enable_reauth_on_new_credentials triggered a fresh auth/cert login"
echo "   OK: Agent survived a container restart using only the on-disk bundle"
echo
echo -e "${YELLOW}For a continuous view: make watch-cert-rotation${NC}"
