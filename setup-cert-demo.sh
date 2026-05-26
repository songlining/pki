#!/bin/bash
# setup-cert-demo.sh — stepped, narrated version of the cert-auth setup flow.
# Same effect as the old `make setup-cert` recipe (containers + PKI init +
# cert/JWT auth init + simulated CI bootstrap) but presented as a demo with
# Step banners, audience-visible commands, and pauses between phases.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

COMPOSE_FILES="${COMPOSE_FILES:--f docker-compose.yml -f docker-compose.cert.yml}"
COMPOSE="docker compose ${COMPOSE_FILES}"

# Allow non-interactive runs (CI / automated rebuilds): SETUP_CERT_INTERACTIVE=false
INTERACTIVE="${SETUP_CERT_INTERACTIVE:-true}"

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

# Print `$ <command>` in green, then run it. Audience sees exactly what's
# being executed at each step.
run_cmd() {
    echo -e "${GREEN}\$ $*${NC}"
    eval "$@"
}

# Print a command without running (for showing what's INSIDE a script the
# next run_cmd will invoke). Uses printf %s so trailing backslashes in the
# argument don't collide with the \033 in ${NC} (which echo -e would mangle).
show_cmd() {
    printf '%b    %s%b\n' "$DIM" "$*" "$NC"
}

# Display a multi-line block (HCL policy, JSON payload, etc.) so the audience
# can read the actual content Vault will receive. Pipe the block on stdin.
show_block() {
    local title="$1"
    echo -e "${YELLOW}${title}${NC}"
    sed 's/^/    /'
}

# Run a noisy command but hide its output unless it fails. Audience sees a
# single status line instead of pages of yellow narration from helper scripts.
run_quietly() {
    local log
    log=$(mktemp)
    echo -e "${GREEN}\$ $*${NC}"
    if eval "$@" >"$log" 2>&1; then
        echo -e "${DIM}    (output suppressed — $(wc -l <"$log" | tr -d ' ') lines)${NC}"
        rm -f "$log"
    else
        echo -e "${RED}command failed — full output below:${NC}"
        cat "$log"
        rm -f "$log"
        exit 1
    fi
}

banner() {
    echo -e "${BLUE}"
    echo "================================================================="
    echo "$1"
    echo "================================================================="
    echo -e "${NC}"
}

clear
echo -e "${BLUE}"
echo "================================================================="
echo "Vault Agent cert-auth — one-time setup walkthrough"
echo "================================================================="
echo -e "${NC}"
echo -e "${YELLOW}This is the provisioning side of the demo. Four phases:${NC}"
echo "   1. Start the Vault TLS listener + mock OIDC issuer (no GitLab CE)"
echo "   2. Initialize Vault's PKI engine (root + intermediate)"
echo "   3. Configure cert-auth and jwt-gitlab auth (no static credentials)"
echo "   4. Run the simulated GitLab CI job to mint the first host.pem"
echo
echo -e "${YELLOW}End-to-end picture:${NC}"
cat <<'DIAGRAM'

   ┌───────────────────────────────────────────────────────────────────────┐
   │ Simulated GitLab CI job   (drives every step from OUTSIDE Vault)      │
   │   has no Vault token to start with — only what GitLab CI would have   │
   └───┬──────────────────────┬─────────────────────────────────────┬──────┘
       │ 1 → GET /token       │ 3 → POST /v1/auth/jwt-gitlab/login  │ 5 → POST /v1/pki/issue/host-bootstrap-role
       │                      │       { role, jwt }                 │       X-Vault-Token: <bootstrap>
       │ 2 ← signed JWT       │ 4 ← .auth.client_token (5-min)      │       common_name=host-01.trading.demo.internal
       ▼                      ▼                                     │ 6 ← JSON: .data.certificate / .private_key
                                                                    ▼              / .issuing_ca / .serial_number
   ┌──────────────┐        ┌──────────────────────────────────────────────┐
   │  mock-oidc   │        │ Vault   https://localhost:8200               │
   │  :8080       │        │                                              │
   │  signs JWT   │◄───────│  auth/jwt-gitlab                             │
   │              │ 3a JWKS│    fetches JWKS to verify the JWT signature  │
   │  serves      │   GET  │    enforces bound_audiences + bound_claims   │
   │  /jwks.json  │        │                                              │
   │              │        │  pki/issue/host-bootstrap-role               │
   │              │        │    signs leaf with pki/ root CA              │
   │              │        │    returns .data.certificate / .private_key  │
   │              │        │            / .issuing_ca / .serial_number    │
   └──────────────┘        └──────────────────────────────────────────────┘

   CI then writes the response to disk:
       vault-agent-config/
           host.pem    = .data.certificate + .data.private_key
           pki-ca.crt  = .data.issuing_ca   (trust anchor)

   Finally CI calls auth/token/revoke-self. The bootstrap token is gone;
   from here on the cert is the credential — agent uses it for cert-auth
   login on every renewal.

DIAGRAM
echo "After this completes, 'make live-demo-cert' shows the agent runtime."
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 1: Bring up Vault + mock OIDC issuer"
echo "Vault listens on https://localhost:8200 with a self-signed TLS cert."
echo "mock-oidc plays the role of GitLab's OIDC issuer. It signs the JWT that"
echo "the simulated CI job will hand to Vault in Step 4."
echo
echo -e "${YELLOW}What runs:${NC}"
show_cmd "${COMPOSE} up -d --build vault mock-oidc"
echo
run_cmd "${COMPOSE} up -d --build vault mock-oidc"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 2: Initialize Vault PKI engine (root + intermediate)"
echo "vault-init.sh mounts the pki backend, generates a root CA, then an"
echo "intermediate signed by it. The intermediate is what mints host and"
echo "application certs later."
echo
echo -e "${YELLOW}Key commands it will run (excerpt):${NC}"
show_cmd "vault secrets enable pki"
show_cmd "vault write pki/root/generate/internal common_name=\"trading.demo.internal\" ttl=87600h"
show_cmd "vault secrets enable -path=pki_int pki   # (intermediate mount, signed by root)"
show_cmd "vault write pki/roles/app-role allowed_domains=\"example.com\" ..."
echo
echo -e "${DIM}    (SKIP_APPROLE=true \u2014 cert-auth variant does not enable AppRole)${NC}"
echo
run_quietly "SKIP_APPROLE=true ./vault-init.sh"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 3: Configure cert-auth + jwt-gitlab auth"
echo "This is where the trust boundaries get set:"
echo "   - auth/cert/certs/host-role  -> Vault Agent logs in with a host cert"
echo "   - auth/jwt-gitlab            -> simulated CI logs in with an OIDC JWT"
echo "   - pki/roles/host-bootstrap-role  (long-TTL, CI mints once)"
echo "   - pki/roles/host-role            (short-TTL, agent self-rotates)"
echo "   - pki-bootstrap-policy           (CI can ONLY issue bootstrap certs)"
wait_for_user

echo -e "${YELLOW}3a. Policy for the Vault Agent (cert-auth login)${NC}"
echo "The agent's token can issue host + app certs and manage its own token. Nothing else."
echo
show_block "vault policy write pki-policy-host - <<EOF" <<'EOF'
path "pki/issue/host-role"    { capabilities = ["create", "update"] }
path "pki/issue/app-role" { capabilities = ["create", "update"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/renew-self"  { capabilities = ["update"] }
EOF
echo -e "${YELLOW}EOF${NC}"
wait_for_user

echo -e "${YELLOW}3b. Policy for the simulated GitLab CI job${NC}"
echo "Scoped to ONE capability: mint a long-TTL bootstrap cert. No renewal,"
echo "no app certs, no reads. Once the cert lands on disk, the agent takes over."
echo
show_block "vault policy write pki-bootstrap-policy - <<EOF" <<'EOF'
path "pki/issue/host-bootstrap-role" { capabilities = ["create", "update"] }
path "auth/token/revoke-self"        { capabilities = ["update"] }
EOF
echo -e "${YELLOW}EOF${NC}"
wait_for_user

echo -e "${YELLOW}3c. Auth methods + roles${NC}"
echo
show_cmd "vault auth enable cert"
show_cmd "vault write auth/cert/certs/host-role \\"
show_cmd "    display_name=host-role token_policies=pki-policy-host \\"
show_cmd "    certificate=@vault-agent-config/pki-ca.crt \\"
show_cmd "    allowed_common_names=\"*.trading.demo.internal\""
echo
show_cmd "vault auth enable -path=jwt-gitlab jwt"
show_cmd "vault write auth/jwt-gitlab/config \\"
show_cmd "    oidc_discovery_url=\"http://mock-oidc:8080\" \\"
show_cmd "    bound_issuer=\"http://mock-oidc:8080\""
wait_for_user

echo -e "${YELLOW}3d. JWT role with bound_claims — the contract that fails 'bad' jobs${NC}"
echo
show_block "vault write auth/jwt-gitlab/role/gitlab-host-bootstrap @- <<JSON" <<'EOF'
{
  "role_type": "jwt",
  "user_claim": "sub",
  "bound_audiences": ["vault-pki-bootstrap"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "project_path": "acme/trading-platform/*",
    "ref_type": "branch",
    "ref_protected": "true"
  },
  "token_policies": ["pki-bootstrap-policy"],
  "token_ttl": "5m",
  "token_max_ttl": "10m"
}
EOF
echo -e "${YELLOW}JSON${NC}"
echo
show_cmd "vault audit enable file file_path=/vault/logs/audit.log   # for the bad-claim demo"
wait_for_user

echo -e "${YELLOW}Applying all of the above via vault-init-cert.sh:${NC}"
run_quietly "./vault-init-cert.sh"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Step 4: Simulated GitLab CI job mints the first host.pem"
echo "Now we run the script that pretends to be a GitLab Runner. It has NO"
echo "Vault root token. Its only credential is the JWT it fetches from"
echo "mock-oidc — Vault verifies that JWT against the JWKS and checks"
echo "bound_claims before handing back a 5-minute scoped token."
echo
echo -e "${YELLOW}What the simulated CI does:${NC}"
show_cmd "curl -X POST http://localhost:8080/token   ->  signed JWT (audience=vault-pki-bootstrap)"
show_cmd "vault write auth/jwt-gitlab/login role=gitlab-host-bootstrap jwt=\$JWT"
show_cmd "  # Vault returns: .auth.client_token  (5-min bootstrap Vault token, pki-bootstrap-policy)"
show_cmd "vault write pki/issue/host-bootstrap-role common_name=host-01.trading.demo.internal"
show_cmd "  # Vault returns JSON with:"
show_cmd "  #   .data.certificate  -> the leaf X.509 cert (CN=host-01.trading.demo.internal)"
show_cmd "  #   .data.private_key  -> matching private key (generated server-side, sent once)"
show_cmd "  #   .data.issuing_ca   -> the PKI CA cert that signed the leaf"
show_cmd "  #   .data.serial_number, .data.ca_chain"
show_cmd "# concat cert+key -> vault-agent-config/host.pem ; issuing_ca -> vault-agent-config/pki-ca.crt"
show_cmd "vault write auth/token/revoke-self  # bootstrap token discarded; cert is the credential now"
echo
run_cmd "./simulate-ci-bootstrap.sh"
wait_for_user

# ─────────────────────────────────────────────────────────────────────────────
banner "Setup complete"
echo -e "${GREEN}Provisioning side is done.${NC}"
echo
echo "  vault-agent-config/host.pem   <- bootstrap cert + key (24h TTL)"
echo "  vault-agent-config/pki-ca.crt <- PKI CA that signed it"
echo
echo "Next:"
echo -e "   ${YELLOW}make live-demo-cert${NC}            # agent runtime + self-rotation"
echo -e "   ${YELLOW}make provision-host-bad-claim${NC}  # negative test (wrong project_path)"
echo
