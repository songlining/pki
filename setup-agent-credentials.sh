#!/bin/bash

set -e

echo "=== Setting up Vault Agent Credentials ==="

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

echo "1. Enabling AppRole auth method..."
vault auth enable approle 2>/dev/null || echo "AppRole already enabled"

echo "2. Creating PKI policy..."
vault policy write pki-policy - << EOF
path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "sys/mounts/pki" {
  capabilities = ["create", "update"]
}
path "sys/mounts/pki/*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOF

echo "3. Creating/updating AppRole..."
vault write auth/approle/role/vault-agent-role \
    token_policies=default,pki-policy \
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
chmod 600 vault-agent-config/role-id vault-agent-config/secret-id

echo "✅ Vault Agent credentials configured successfully!"
echo "Files created:"
ls -la vault-agent-config/role-id vault-agent-config/secret-id

echo
echo "Note: These credentials will persist across container restarts."