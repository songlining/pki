#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

echo -e "${BLUE}Vault cert-auth demo setup${NC}"
echo "===================================="

echo -e "${YELLOW}Configuring PKI URLs for the TLS demo listener...${NC}"
vault write pki/config/urls \
    issuing_certificates="https://vault.local:8200/v1/pki/ca" \
    crl_distribution_points="https://vault.local:8200/v1/pki/crl"

echo -e "${YELLOW}Creating host certificate issuance role...${NC}"
vault write pki/roles/host-role \
    allowed_domains="trading.demo.internal" \
    allow_subdomains=true \
    client_flag=true \
    server_flag=false \
    generate_lease=false \
    not_before_duration="0s" \
    max_ttl="5m" \
    ttl="30s"

echo -e "${YELLOW}Making the application certificate role lease-backed for predictable demo rotation...${NC}"
vault write pki/roles/app-role \
    allowed_domains="example.com" \
    allow_subdomains=true \
    allow_localhost=true \
    allow_ip_sans=true \
    client_flag=true \
    server_flag=true \
    generate_lease=true \
    max_ttl="72h" \
    ttl="30s"

echo -e "${YELLOW}Writing host policy for cert-auth Vault Agent...${NC}"
vault policy write pki-policy-host - <<EOF
path "pki/issue/host-role" {
  capabilities = ["create", "update"]
}

path "pki/issue/app-role" {
  capabilities = ["create", "update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

echo -e "${YELLOW}Exporting the PKI CA used to trust host certificates...${NC}"
mkdir -p vault-agent-config
vault read -field=certificate pki/cert/ca > vault-agent-config/pki-ca.crt
chmod 644 vault-agent-config/pki-ca.crt

echo -e "${YELLOW}Enabling TLS certificate auth method...${NC}"
if vault auth list | grep -q "cert/"; then
    echo -e "${YELLOW}cert auth method already enabled${NC}"
else
    vault auth enable cert
    echo -e "${GREEN}cert auth method enabled${NC}"
fi

echo -e "${YELLOW}Configuring cert-auth role for host certificates...${NC}"
vault write auth/cert/certs/host-role \
    display_name=host-role \
    token_policies=pki-policy-host \
    token_no_default_policy=true \
    token_period=24h \
    certificate=@vault-agent-config/pki-ca.crt \
    allowed_common_names="*.trading.demo.internal"

echo -e "${YELLOW}Enabling file audit device for the bad-claim teaching moment...${NC}"
if vault audit list 2>/dev/null | grep -q "^file/"; then
    echo -e "${YELLOW}file audit device already enabled${NC}"
else
    vault audit enable file file_path=/vault/logs/audit.log log_raw=true
    echo -e "${GREEN}file audit device enabled at /vault/logs/audit.log${NC}"
fi

echo -e "${YELLOW}Creating long-TTL bootstrap PKI role for the CI step...${NC}"
vault write pki/roles/host-bootstrap-role \
    allowed_domains="trading.demo.internal" \
    allow_subdomains=true \
    client_flag=true \
    server_flag=false \
    generate_lease=false \
    not_before_duration="0s" \
    max_ttl="24h" \
    ttl="24h"

echo -e "${YELLOW}Writing pki-bootstrap-policy (CI can only mint bootstrap certs)...${NC}"
vault policy write pki-bootstrap-policy - <<'EOF'
# Scoped to the simulated GitLab CI job. It can mint ONE thing — a long-TTL
# bootstrap cert via host-bootstrap-role — and nothing else. No renewal, no
# app certs, no reads, no token self-management. Once the cert is on disk,
# the Vault Agent (with its own cert auth) takes over.
path "pki/issue/host-bootstrap-role" {
  capabilities = ["create", "update"]
}

# Let the CI job revoke its own token after writing the cert — a credential
# you no longer need shouldn't keep living. Without this, the audit log shows
# a permission-denied revoke-self that would distract the audience.
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
EOF

echo -e "${YELLOW}Enabling JWT auth method for the simulated GitLab CI...${NC}"
if vault auth list 2>/dev/null | grep -q "^jwt-gitlab/"; then
    echo -e "${YELLOW}jwt-gitlab auth method already enabled${NC}"
else
    vault auth enable -path=jwt-gitlab jwt
    echo -e "${GREEN}jwt-gitlab auth method enabled${NC}"
fi

echo -e "${YELLOW}Waiting for mock-oidc to publish JWKS...${NC}"
OIDC_READY=false
for _ in $(seq 1 30); do
    if docker exec vault wget -qO- http://mock-oidc:8080/.well-known/jwks.json 2>/dev/null \
        | grep -q '"keys"'; then
        OIDC_READY=true
        break
    fi
    sleep 1
done
if [ "$OIDC_READY" != true ]; then
    echo -e "${RED}mock-oidc did not respond on http://mock-oidc:8080. Is the container up?${NC}"
    exit 1
fi
echo -e "${GREEN}mock-oidc JWKS is reachable from Vault${NC}"

echo -e "${YELLOW}Configuring jwt-gitlab to trust the mock OIDC issuer...${NC}"
vault write auth/jwt-gitlab/config \
    oidc_discovery_url="http://mock-oidc:8080" \
    bound_issuer="http://mock-oidc:8080" \
    default_role="gitlab-host-bootstrap"

echo -e "${YELLOW}Creating jwt-gitlab role 'gitlab-host-bootstrap' with bound_claims...${NC}"
ROLE_PAYLOAD=$(cat <<'JSON'
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
  "token_no_default_policy": true,
  "token_ttl": "5m",
  "token_max_ttl": "10m",
  "clock_skew_leeway": "60s"
}
JSON
)
curl -sSk -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$ROLE_PAYLOAD" \
    "${VAULT_ADDR}/v1/auth/jwt-gitlab/role/gitlab-host-bootstrap" \
    | (grep -q . && echo "(API returned a body — see above)") || true
vault read auth/jwt-gitlab/role/gitlab-host-bootstrap >/dev/null \
    && echo -e "${GREEN}role gitlab-host-bootstrap created${NC}" \
    || { echo -e "${RED}failed to create jwt role${NC}"; exit 1; }

echo -e "${GREEN}cert-auth setup complete${NC}"
