#!/bin/bash

# Quick Start for Vault Enterprise with proper initialization

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Vault Enterprise Quick Start${NC}"
echo "================================="

# Stop any running containers
echo -e "${YELLOW}🛑 Stopping existing containers...${NC}"
docker-compose down -v >/dev/null 2>&1 || true

# Remove the license file temporarily to start without it
rm -f vault.hclic

# Update docker-compose to remove license dependencies for initial start
echo -e "${YELLOW}🔧 Preparing configuration...${NC}"

# Create a temporary docker-compose without license requirements
cat > docker-compose-temp.yml << 'EOF'
version: '3.8'

services:
  vault:
    image: hashicorp/vault-enterprise
    container_name: vault-enterprise
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: "myroot"
      VAULT_DEV_LISTEN_ADDRESS: "0.0.0.0:8200"
      VAULT_ADDR: "http://localhost:8200"
      VAULT_API_ADDR: "http://localhost:8200"
      VAULT_DISABLE_MLOCK: "true"
    cap_add:
      - IPC_LOCK
    volumes:
      - vault_data:/vault/data
      - vault_logs:/vault/logs
      - ./vault-config:/vault/config
    ports:
      - "8200:8200"
    networks:
      - vault-network
    hostname: vault.local
    command: vault server -dev -dev-root-token-id="myroot" -dev-listen-address="0.0.0.0:8200"

volumes:
  vault_data:
  vault_logs:

networks:
  vault-network:
    driver: bridge
EOF

# Start with dev mode first
echo -e "${YELLOW}🐳 Starting Vault in dev mode...${NC}"
docker-compose -f docker-compose-temp.yml up -d

# Wait for Vault to be ready
echo -e "${YELLOW}⏳ Waiting for Vault...${NC}"
timeout=30
counter=0
while ! curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1; do
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}❌ Timeout${NC}"
        exit 1
    fi
    echo "Waiting... ($((counter + 1))/$timeout)"
    sleep 1
    counter=$((counter + 1))
done

echo -e "${GREEN}✅ Vault is running!${NC}"

# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

# Check if it's Enterprise and provide license instructions
echo -e "${YELLOW}🏢 Checking Vault version...${NC}"
VAULT_VERSION=$(vault version | head -1)
echo -e "${BLUE}${VAULT_VERSION}${NC}"

if echo "$VAULT_VERSION" | grep -q "enterprise"; then
    echo -e "${YELLOW}🎉 Vault Enterprise is running in dev mode!${NC}"
    echo -e "${BLUE}💡 For full Enterprise features, you can:${NC}"
    echo -e "   1. Get a free trial license: ${GREEN}https://www.hashicorp.com/products/vault/trial${NC}"
    echo -e "   2. Save it as 'vault.hclic'"
    echo -e "   3. Apply it with: ${GREEN}vault write sys/license text=@vault.hclic${NC}"
    
    # Run basic initialization
    echo -e "${YELLOW}🔧 Setting up PKI...${NC}"
    vault secrets enable pki || echo "PKI already enabled"
    vault secrets tune -max-lease-ttl=8760h pki || true
    
    echo -e "${GREEN}🎉 Quick start complete!${NC}"
    echo -e "${BLUE}Vault URL: ${GREEN}http://localhost:8200${NC}"
    echo -e "${BLUE}Root Token: ${GREEN}myroot${NC}"
    echo ""
    echo -e "${YELLOW}💡 Vault Enterprise is running in development mode${NC}"
    echo -e "${YELLOW}   Some Enterprise features may require a license${NC}"
else
    echo -e "${YELLOW}⚠️  This appears to be Vault OSS${NC}"
fi

# Clean up temp file
rm -f docker-compose-temp.yml

echo -e "${GREEN}✅ Setup complete!${NC}"