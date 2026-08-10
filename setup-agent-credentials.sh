#!/bin/bash

set -e

echo "=== Setting up Vault Agent Credentials ==="

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

echo "1. Enabling AppRole auth method..."
vault auth enable approle 2>/dev/null || echo "AppRole already enabled"

echo "2. Creating PKI policy..."
vault policy write pki-policy - << EOF
path "pki/issue/web-server" {
  capabilities = ["create", "update"]
}
path "pki/revoke" {
  capabilities = ["create", "update"]
}
path "pki/cert/+" {
  capabilities = ["read"]
}
path "pki/crl/+" {
  capabilities = ["read"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

echo "3. Creating/updating AppRole..."
vault write auth/approle/role/vault-agent-role \
    token_policies=pki-policy \
    token_no_default_policy=true \
    token_ttl=1h \
    token_max_ttl=4h

echo "4. Getting role ID..."
ROLE_ID=$(vault read -field=role_id auth/approle/role/vault-agent-role/role-id)
echo "Role ID: $ROLE_ID"

echo "5. Generating secret ID..."
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/vault-agent-role/secret-id)
echo "Secret ID: $SECRET_ID"

echo "6. Saving credentials to files..."
echo -n "$ROLE_ID" > vault-agent-config/role-id
echo -n "$SECRET_ID" > vault-agent-config/secret-id

echo "7. Setting proper permissions..."
# 0644 (not 0600): under Podman Desktop's macOS VM (libkrun virtiofs), bind-mounted
# files keep the host uid and the container may not bypass DAC for them; the Vault
# Agent container must be able to read these at boot. Demo credentials only.
chmod 644 vault-agent-config/role-id vault-agent-config/secret-id

# Podman Desktop's virtiofs sync can intermittently drop a freshly written file
# from the host view. Verify and retry so the credentials reliably persist.
attempt=1
while [ "$attempt" -le 3 ]; do
  if [ -s vault-agent-config/role-id ] && [ -s vault-agent-config/secret-id ]; then
    break
  fi
  echo "   WARNING: credential file vanished (virtiofs sync) — rewriting (attempt $attempt)..."
  printf '%s' "$ROLE_ID" > vault-agent-config/role-id
  printf '%s' "$SECRET_ID" > vault-agent-config/secret-id
  chmod 644 vault-agent-config/role-id vault-agent-config/secret-id
  sleep 1
  attempt=$((attempt + 1))
done
[ -s vault-agent-config/role-id ] && [ -s vault-agent-config/secret-id ] || {
  echo "ERROR: could not persist credential files" >&2
  exit 1
}

echo "Vault Agent credentials configured successfully!"
echo "Files created:"
ls -la vault-agent-config/role-id vault-agent-config/secret-id

echo
echo "Note: These credentials will persist across container restarts."
