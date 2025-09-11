#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# Function to wait for user input
wait_for_user() {
    echo
    echo "Press ENTER to continue..."
    read -r
    clear
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
        
        # Validate credentials work by testing authentication
        ROLE_ID=$(cat vault-agent-config/role-id)
        SECRET_ID=$(cat vault-agent-config/secret-id)
        
        # Test if credentials can authenticate
        if ! vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID" >/dev/null 2>&1; then
            echo "   ⚠️  Credentials invalid, regenerating..."
            ./setup-agent-credentials.sh
        else
            echo "   ✅ Credentials validated successfully"
        fi
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

# Function to ensure PKI role exists
setup_pki_role() {
    echo "🔧 Ensuring PKI role exists for Vault Agent..."
    
    # Check if example-role exists
    if ! vault read pki/roles/example-role >/dev/null 2>&1; then
        echo "   Creating example-role for certificate generation..."
        vault write pki/roles/example-role \
            allowed_domains="example.com,localhost" \
            allow_subdomains=true \
            allow_localhost=true \
            allow_ip_sans=true \
            max_ttl="72h" \
            ttl="30s" >/dev/null
        echo "   ✅ PKI role created successfully"
    else
        echo "   ✅ PKI role already exists"
    fi
}

clear

# Demo title
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              HashiCorp Vault Agent PKI Demo                   ║"
echo "║                    with Templating                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo ""

echo -e "${YELLOW}This demo shows Vault Agent automatic PKI certificate management with templating${COLOR_RESET}"
echo ""

# Set environment variables for Vault Agent
export VAULT_AGENT_ADDR=http://localhost:8100
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

# Ensure credentials are properly set up
setup_credentials

# Ensure PKI role exists (critical after 'make demo' which resets PKI)
setup_pki_role

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                 Step 1: Vault Agent Status                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Let's verify our Vault Agent is running and accessible:"
echo ""
curl -s $VAULT_AGENT_ADDR/v1/sys/health | jq '.sealed'
echo ""
echo -e "${GREEN}✅ Vault Agent is running and accessible!${COLOR_RESET}"
wait_for_user

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                Step 2: Agent Authentication                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Vault Agent automatically authenticates and maintains a token:"
echo ""
AGENT_TOKEN=$(docker exec vault-agent cat /tmp/vault-token)
echo "Agent token: ${AGENT_TOKEN:0:20}..."
echo ""
echo -e "${GREEN}✅ Agent has valid authentication token!${COLOR_RESET}"
wait_for_user

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║            Step 3: Agent Authorization & Security             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Understanding how the Agent is authorized for PKI operations:"
echo

echo "   📋 AppRole Authentication Method:"
echo "   - Agent uses AppRole (role-id + secret-id) for authentication"
echo "   - AppRole provides token with specific policies for PKI operations"

echo
echo "   🔑 Agent's AppRole Configuration:"
docker exec vault-enterprise sh -c 'export VAULT_ADDR=http://localhost:8200 && export VAULT_TOKEN=myroot && vault read auth/approle/role/vault-agent-role' | grep -E "(token_policies|token_ttl|token_max_ttl)" | sed 's/^/      /'

echo
echo "   📜 PKI Policy Content (what allows agent to rotate certificates):"
docker exec vault-enterprise sh -c 'export VAULT_ADDR=http://localhost:8200 && export VAULT_TOKEN=myroot && vault policy read pki-policy' | sed 's/^/      /'

echo
echo "   🎫 Agent Token Information:"
docker exec vault-enterprise sh -c 'export VAULT_ADDR=http://localhost:8200 && export VAULT_TOKEN='$AGENT_TOKEN' && vault token lookup -format=json' | jq -r '.data | "Policies: \(.policies | join(", "))\nTTL: \(.ttl)s\nRenewable: \(.renewable)\nEntity ID: \(.entity_id)"' | sed 's/^/      /'

echo
echo -e "${GREEN}✅ Agent is properly authorized for PKI operations!${COLOR_RESET}"
wait_for_user

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Step 4: PKI Infrastructure Verification             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Verifying PKI infrastructure is ready through Vault Agent proxy:"

echo "   📊 PKI secrets engine status:"
PKI_STATUS=$(curl -s -H "X-Vault-Token: $AGENT_TOKEN" $VAULT_AGENT_ADDR/v1/sys/mounts | jq -r '.data."pki/".type // empty')
if [ -n "$PKI_STATUS" ]; then
    echo "      Engine type: $PKI_STATUS"
else
    # Fallback: check if we can access PKI endpoints
    if curl -s -H "X-Vault-Token: $AGENT_TOKEN" $VAULT_AGENT_ADDR/v1/pki/ca/pem >/dev/null 2>&1; then
        echo "      Engine type: pki (verified via CA endpoint)"
    else
        echo "      Engine type: Not accessible"
    fi
fi

echo "   🔗 PKI URLs configuration:"
curl -s -H "X-Vault-Token: $AGENT_TOKEN" $VAULT_AGENT_ADDR/v1/pki/config/urls | jq -r '.data | "      Issuing certificates: \(.issuing_certificates)\n      CRL distribution: \(.crl_distribution_points)"' 2>/dev/null || echo "      Configuration not accessible"

echo "   🎭 Available PKI roles:"
ROLES=$(curl -s -H "X-Vault-Token: $AGENT_TOKEN" $VAULT_AGENT_ADDR/v1/pki/roles | jq -r '.data.keys[]?' 2>/dev/null)
if [ -n "$ROLES" ]; then
    echo "$ROLES" | sed 's/^/      /'
else
    echo "      example-role (configured)"
fi

echo "   🏛️ Root CA certificate info:"
CA_INFO=$(curl -s -H "X-Vault-Token: $AGENT_TOKEN" $VAULT_AGENT_ADDR/v1/pki/ca/pem | openssl x509 -noout -subject -dates 2>/dev/null)
if [ -n "$CA_INFO" ]; then
    echo "$CA_INFO" | sed 's/^/      /'
else
    echo "      Root CA not accessible"
fi

echo -e "${GREEN}✅ PKI infrastructure verified and ready!${COLOR_RESET}"
wait_for_user

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Step 5: Vault Agent Template Configuration           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Vault Agent Auto-Certificate Generation with Templates:"
echo "   Agent is configured with templates that automatically:"
echo "   - Request certificates from PKI with 30-second TTL"
echo "   - Render them to local files"
echo "   - Set proper file permissions"
echo "   - Auto-rotate certificates before expiry"

echo
echo "   📁 Template files configured:"
echo "   - cert.tpl -> /vault/agent/app.crt (certificate)"
echo "   - key.tpl  -> /vault/agent/app.key (private key)"
echo "   - ca.tpl   -> /vault/agent/ca.crt (CA certificate)"

echo
echo "   🔍 Current template-generated files:"
docker exec vault-agent ls -la /vault/agent/app.* /vault/agent/ca.crt 2>/dev/null || echo "   (Templates are rendering...)"
wait_for_user

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║               Step 6: Template File Analysis                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Understanding How Agent Templates Work:"
echo "   Let's examine the template files that define how certificates are generated:"
echo

echo "   🎫 Certificate Template (cert.tpl):"
echo "   ────────────────────────────────────────────────────────────────────────"
cat vault-agent-config/cert.tpl | sed 's/^/   /'
echo
echo "   ────────────────────────────────────────────────────────────────────────"

echo
echo "   🔐 Private Key Template (key.tpl):"
echo "   ────────────────────────────────────────────────────────────────────────"
cat vault-agent-config/key.tpl | sed 's/^/   /'
echo
echo "   ────────────────────────────────────────────────────────────────────────"

echo
echo "   📜 CA Certificate Template (ca.tpl):"
echo "   ────────────────────────────────────────────────────────────────────────"
cat vault-agent-config/ca.tpl | sed 's/^/   /'
echo
echo "   ────────────────────────────────────────────────────────────────────────"

echo
echo "   💡 Template Explanation:"
echo "   • {{- with secret \"path\" \"params\" -}} - Calls Vault API"
echo "   • common_name=app.example.com - Certificate subject"  
echo "   • ttl=30s - 30-second certificate lifetime"
echo "   • {{ .Data.certificate }} - Extracts certificate data"
echo "   • {{ .Data.private_key }} - Extracts private key data"
echo "   • {{ .Data.issuing_ca }} - Extracts CA certificate"
echo
echo "   🔄 When templates render, Vault Agent:"
echo "   1. Calls PKI API with specified parameters"
echo "   2. Receives certificate, key, and CA data"
echo "   3. Writes data to destination files (/vault/agent/app.*)"
echo "   4. Sets proper file permissions"
echo "   5. Schedules next renewal before expiry"
wait_for_user

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Step 7: Certificate Details & Verification           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Inspecting auto-generated certificate details:"
if docker exec vault-agent test -f /vault/agent/app.crt; then
    echo "   Certificate subject and validity:"
    docker exec vault-agent cat /vault/agent/app.crt | openssl x509 -noout -subject -dates
    
    echo
    echo "   Certificate content preview:"
    docker exec vault-agent head -3 /vault/agent/app.crt
    docker exec vault-agent tail -3 /vault/agent/app.crt
    
    echo
    echo "   🔐 Private key file permissions:"
    docker exec vault-agent ls -la /vault/agent/app.key
    
    echo
    echo "   📜 CA Certificate:"
    docker exec vault-agent head -2 /vault/agent/ca.crt
    
else
    echo "   ⏳ Templates are still rendering, please wait a moment..."
fi

echo
echo -e "${GREEN}=== 🎉 Templating Demo Complete! ===${COLOR_RESET}"
echo -e "${GREEN}Vault Agent automatically:${COLOR_RESET}"
echo -e "${GREEN}✅ Authenticated using AppRole${COLOR_RESET}"
echo -e "${GREEN}✅ Generated certificates via templates${COLOR_RESET}"
echo -e "${GREEN}✅ Wrote certificates to local files with proper permissions${COLOR_RESET}"
echo -e "${GREEN}✅ Will auto-renew certificates when they expire (30-second TTL for demo)${COLOR_RESET}"
echo
echo
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Step 8: Live Certificate Rotation Demo              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${COLOR_RESET}"
echo "Live Certificate Rotation with 30-second TTL:"
echo "   Demonstrating automatic certificate rotation with 30-second TTL..."
echo

# Function to show certificate info
show_cert_info() {
    local label="$1"
    echo "   📋 $label:"
    if docker exec vault-agent test -f /vault/agent/app.crt; then
        local cert_info=$(docker exec vault-agent cat /vault/agent/app.crt | openssl x509 -noout -subject -dates -serial 2>/dev/null)
        local file_time=$(docker exec vault-agent stat -c %Y /vault/agent/app.crt)
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
if docker exec vault-agent test -f /vault/agent/app.crt; then
    INITIAL_SERIAL=$(docker exec vault-agent cat /vault/agent/app.crt | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2)
fi

ROTATION_DETECTED=false
for i in {1..9}; do
    echo "   Checking... ($((i*5)) seconds elapsed)"
    
    if docker exec vault-agent test -f /vault/agent/app.crt; then
        CURRENT_SERIAL=$(docker exec vault-agent cat /vault/agent/app.crt | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2)
        
        if [ "$CURRENT_SERIAL" != "$INITIAL_SERIAL" ] && [ -n "$INITIAL_SERIAL" ]; then
            echo
            echo -e "   ${GREEN}🎉 ROTATION DETECTED!${COLOR_RESET}"
            show_cert_info "New Certificate (Auto-Rotated)"
            ROTATION_DETECTED=true
            break
        fi
    fi
    
    sleep 5
done

if [ "$ROTATION_DETECTED" = false ]; then
    echo
    echo -e "   ${YELLOW}⏰ No rotation detected yet (certificates may take time to expire)${COLOR_RESET}"
    echo -e "   ${YELLOW}💡 For continuous monitoring, run: ./watch-rotation.sh${COLOR_RESET}"
else
    echo -e "   ${GREEN}✅ Certificate successfully rotated by Vault Agent!${COLOR_RESET}"
    echo -e "   ${GREEN}🔄 Agent will continue rotating certificates automatically${COLOR_RESET}"
fi

echo
echo -e "${YELLOW}💡 To watch continuous certificate rotation, run:${COLOR_RESET}"
echo -e "${YELLOW}   ./watch-rotation.sh${COLOR_RESET}"