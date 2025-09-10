#!/bin/bash

# Set environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

# Enable AppRole auth method
vault auth enable approle

# Create a role for vault-agent
vault write auth/approle/role/vault-agent-role \
    token_policies=default \
    token_ttl=1h \
    token_max_ttl=4h

# Get role ID
echo "Getting role ID..."
vault read auth/approle/role/vault-agent-role/role-id

# Generate secret ID
echo "Generating secret ID..."
vault write -f auth/approle/role/vault-agent-role/secret-id

echo "AppRole auth method configured successfully!"
echo "Update vault-agent-config/role-id and vault-agent-config/secret-id with the values above"