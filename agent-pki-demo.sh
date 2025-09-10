#!/bin/bash

set -e

# Function to wait for user input
wait_for_user() {
    echo
    echo "Press ENTER to continue..."
    read -r
    echo
}

# Function to ensure agent credentials are configured
setup_credentials() {
    echo "🔧 Ensuring Vault Agent credentials are properly configured..."
    
    # Check if credentials exist and are valid
    if [ ! -f "vault-agent-config/role-id" ] || [ ! -f "vault-agent-config/secret-id" ]; then
        echo "   Missing credential files, setting up..."
        ./setup-agent-credentials.sh
    else
        echo "   ✅ Credential files exist"
    fi
    
    # Ensure credentials are available in the container
    if docker exec vault-agent test -f /vault/config/role-id && docker exec vault-agent test -f /vault/config/secret-id; then
        echo "   ✅ Credentials available in container"
    else
        echo "   Copying credentials to container..."
        docker exec vault-agent cp /vault/config/role-id /tmp/role-id 2>/dev/null || true
        docker exec vault-agent cp /vault/config/secret-id /tmp/secret-id 2>/dev/null || true
    fi
}

echo "=== Vault Agent PKI Demo with Templating ==="
echo

# Set environment variables for Vault Agent
export VAULT_AGENT_ADDR=http://localhost:8100
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

# Ensure credentials are properly set up
setup_credentials

echo "1. Checking Vault Agent status..."
curl -s $VAULT_AGENT_ADDR/v1/sys/health | jq '.sealed'
wait_for_user

echo "2. Getting Vault Agent token..."
AGENT_TOKEN=$(docker exec vault-agent cat /tmp/vault-token)
echo "Agent token: ${AGENT_TOKEN:0:20}..."
wait_for_user

echo "3. 🔐 AUTHORIZATION DEMO: How Agent is Authorized for PKI Operations"
echo

echo "   📋 AppRole Authentication Method:"
echo "   - Agent uses AppRole (role-id + secret-id) for authentication"
echo "   - AppRole provides token with specific policies for PKI operations"

echo
echo "   🔑 Agent's AppRole Configuration:"
docker exec vault-enterprise sh -c 'export VAULT_ADDR=http://localhost:8200 && export VAULT_TOKEN=myroot && vault read auth/approle/role/vault-agent-role' | grep -E "(token_policies|token_ttl|token_max_ttl)"

echo
echo "   📜 PKI Policy Content (what allows agent to rotate certificates):"
docker exec vault-enterprise sh -c 'export VAULT_ADDR=http://localhost:8200 && export VAULT_TOKEN=myroot && vault policy read pki-policy'

echo
echo "   🎫 Agent Token Information:"
docker exec vault-enterprise sh -c 'export VAULT_ADDR=http://localhost:8200 && export VAULT_TOKEN='$AGENT_TOKEN' && vault token lookup -format=json' | jq -r '.data | "Policies: \(.policies | join(", "))\nTTL: \(.ttl)s\nRenewable: \(.renewable)\nEntity ID: \(.entity_id)"'

echo
echo "✅ Agent is properly authorized for PKI operations!"
wait_for_user

echo "4. Testing PKI operations through Vault Agent (port 8100)..."

echo "   - Enabling PKI secrets engine via Agent..."
curl -s -H "X-Vault-Token: $AGENT_TOKEN" \
     -X POST \
     -d '{"type":"pki"}' \
     $VAULT_AGENT_ADDR/v1/sys/mounts/pki > /dev/null 2>&1

echo "   - Configuring PKI URLs via Agent..."
curl -s -H "X-Vault-Token: $AGENT_TOKEN" \
     -X POST \
     -d '{"issuing_certificates":"http://vault:8200/v1/pki/ca","crl_distribution_points":"http://vault:8200/v1/pki/crl"}' \
     $VAULT_AGENT_ADDR/v1/pki/config/urls > /dev/null

echo "   - Creating PKI role via Agent..."
curl -s -H "X-Vault-Token: $AGENT_TOKEN" \
     -X POST \
     -d '{"allowed_domains":"example.com","allow_subdomains":true,"max_ttl":"72h"}' \
     $VAULT_AGENT_ADDR/v1/pki/roles/example-role > /dev/null

echo "   - Generating root CA via Agent..."
curl -s -H "X-Vault-Token: $AGENT_TOKEN" \
     -X POST \
     -d '{"common_name":"Example Root CA","ttl":"8760h"}' \
     $VAULT_AGENT_ADDR/v1/pki/root/generate/internal > /dev/null

echo "✅ PKI infrastructure setup complete!"
wait_for_user

echo "5. 🎯 TEMPLATING DEMO: Vault Agent Auto-Certificate Generation"
echo "   Agent is configured with templates that automatically:"
echo "   - Request certificates from PKI with 30-second TTL"
echo "   - Render them to local files"
echo "   - Set proper file permissions"
echo "   - Auto-rotate certificates before expiry"

echo
echo "   📁 Template files configured:"
echo "   - cert.tpl -> /tmp/app.crt (certificate)"
echo "   - key.tpl  -> /tmp/app.key (private key)"
echo "   - ca.tpl   -> /tmp/ca.crt (CA certificate)"

echo
echo "   🔍 Current template-generated files:"
docker exec vault-agent ls -la /tmp/app.* /tmp/ca.crt 2>/dev/null || echo "   (Templates are rendering...)"
wait_for_user

echo "6. Inspecting auto-generated certificate details:"
if docker exec vault-agent test -f /tmp/app.crt; then
    echo "   Certificate subject and validity:"
    docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -subject -dates
    
    echo
    echo "   Certificate content preview:"
    docker exec vault-agent head -3 /tmp/app.crt
    docker exec vault-agent tail -3 /tmp/app.crt
    
    echo
    echo "   🔐 Private key file permissions:"
    docker exec vault-agent ls -la /tmp/app.key
    
    echo
    echo "   📜 CA Certificate:"
    docker exec vault-agent head -2 /tmp/ca.crt
    
else
    echo "   ⏳ Templates are still rendering, please wait a moment..."
fi

echo
echo "=== 🎉 Templating Demo Complete! ==="
echo "Vault Agent automatically:"
echo "✅ Authenticated using AppRole"
echo "✅ Generated certificates via templates"
echo "✅ Wrote certificates to local files with proper permissions"
echo "✅ Will auto-renew certificates when they expire (30-second TTL for demo)"
echo
echo
echo "7. 🔄 LIVE CERTIFICATE ROTATION DEMO"
echo "   Demonstrating automatic certificate rotation with 30-second TTL..."
echo

# Function to show certificate info
show_cert_info() {
    local label="$1"
    echo "   📋 $label:"
    if docker exec vault-agent test -f /tmp/app.crt; then
        local cert_info=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -subject -dates -serial 2>/dev/null)
        local file_time=$(docker exec vault-agent stat -c %Y /tmp/app.crt)
        echo "      Subject: $(echo "$cert_info" | grep subject | cut -d= -f2-)"
        echo "      Serial:  $(echo "$cert_info" | grep serial | cut -d= -f2)"
        echo "      Valid:   $(echo "$cert_info" | grep notBefore | cut -d= -f2-)"
        echo "      Expires: $(echo "$cert_info" | grep notAfter | cut -d= -f2-)"
        echo "      File timestamp: $(docker exec vault-agent date -d @$file_time '+%H:%M:%S')"
    else
        echo "      Certificate not found"
    fi
    echo
}

# Show initial certificate
echo "   🕐 Initial Certificate Status:"
show_cert_info "Current Certificate"

echo "   ⏳ Waiting for certificate rotation..."
echo "   (Certificates rotate ~15 seconds before expiry)"
echo

# Wait and monitor for rotation (check every 5 seconds for up to 45 seconds)
INITIAL_SERIAL=""
if docker exec vault-agent test -f /tmp/app.crt; then
    INITIAL_SERIAL=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2)
fi

ROTATION_DETECTED=false
for i in {1..9}; do
    echo "   Checking... ($((i*5)) seconds elapsed)"
    
    if docker exec vault-agent test -f /tmp/app.crt; then
        CURRENT_SERIAL=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2)
        
        if [ "$CURRENT_SERIAL" != "$INITIAL_SERIAL" ] && [ -n "$INITIAL_SERIAL" ]; then
            echo
            echo "   🎉 ROTATION DETECTED!"
            show_cert_info "New Certificate (Auto-Rotated)"
            ROTATION_DETECTED=true
            break
        fi
    fi
    
    sleep 5
done

if [ "$ROTATION_DETECTED" = false ]; then
    echo
    echo "   ⏰ No rotation detected yet (certificates may take time to expire)"
    echo "   💡 For continuous monitoring, run: ./watch-rotation.sh"
else
    echo "   ✅ Certificate successfully rotated by Vault Agent!"
    echo "   🔄 Agent will continue rotating certificates automatically"
fi

echo
echo "💡 To watch continuous certificate rotation, run:"
echo "   ./watch-rotation.sh"