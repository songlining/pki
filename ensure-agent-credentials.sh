#!/bin/bash

# Helper script to ensure Vault Agent credentials are always available
# Can be sourced by other demo scripts: source ./ensure-agent-credentials.sh

# Function to ensure agent credentials are configured and valid
ensure_agent_credentials() {
    echo "🔧 Ensuring Vault Agent credentials are properly configured..."
    
    # Check if credentials exist
    if [ ! -f "vault-agent-config/role-id" ] || [ ! -f "vault-agent-config/secret-id" ]; then
        echo "   Missing credential files, setting up..."
        ./setup-agent-credentials.sh
        return
    fi
    
    # Check if files are empty
    if [ ! -s "vault-agent-config/role-id" ] || [ ! -s "vault-agent-config/secret-id" ]; then
        echo "   Empty credential files, regenerating..."
        ./setup-agent-credentials.sh
        return
    fi
    
    echo "   ✅ Credential files exist"
    
    # Validate credentials work by testing authentication
    ROLE_ID=$(cat vault-agent-config/role-id)
    SECRET_ID=$(cat vault-agent-config/secret-id)
    
    # Set Vault environment if not already set
    export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
    export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"
    
    # Test if credentials can authenticate
    if ! vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID" >/dev/null 2>&1; then
        echo "   ⚠️  Credentials invalid, regenerating..."
        ./setup-agent-credentials.sh
    else
        echo "   ✅ Credentials validated successfully"
    fi
    
    echo ""
}

# If script is executed (not sourced), run the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    ensure_agent_credentials
fi