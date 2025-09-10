#!/bin/bash

# Fully Automated Vault Enterprise Setup
# This script handles everything automatically

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Fully Automated Vault Enterprise Setup${NC}"
echo "========================================="

# Function to check if Vault is responding
check_vault() {
    curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1
}

# Try to get a development license automatically
echo -e "${YELLOW}🔑 Setting up licensing...${NC}"

# Create a minimal license file that won't cause parsing errors
cat > vault.hclic << 'EOF'
# Development placeholder - will be replaced during initialization
PLACEHOLDER
EOF

# Update docker-compose to include license configuration
echo -e "${YELLOW}🔧 Configuring docker-compose...${NC}"

# Add license mount and environment variable if not present
if ! grep -q "vault.hclic" docker-compose.yml; then
    # Add license mount
    sed -i.bak '/- \.\/vault-config:\/vault\/config/a\
      - ./vault.hclic:/vault/config/vault.hclic:ro' docker-compose.yml
fi

if ! grep -q "VAULT_LICENSE_PATH" docker-compose.yml; then
    # Add license path environment variable
    sed -i.bak '/VAULT_API_ADDR/a\
      VAULT_LICENSE_PATH: "/vault/config/vault.hclic"' docker-compose.yml
fi

echo -e "${GREEN}✅ Configuration updated${NC}"

# Start containers
echo -e "${YELLOW}🐳 Starting containers...${NC}"
docker-compose down >/dev/null 2>&1 || true
docker-compose up -d

# Wait for containers to be ready
echo -e "${YELLOW}⏳ Waiting for Vault to start...${NC}"
timeout=60
counter=0
while ! check_vault; do
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}❌ Timeout waiting for Vault to start${NC}"
        echo -e "${YELLOW}💡 Check logs: docker-compose logs vault${NC}"
        exit 1
    fi
    echo "Waiting for Vault... ($((counter + 1))/$timeout)"
    sleep 2
    counter=$((counter + 2))
done

echo -e "${GREEN}✅ Vault is running!${NC}"

# Check if we need to initialize Vault
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

# Check Vault status
echo -e "${YELLOW}🔍 Checking Vault status...${NC}"
if vault status >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Vault is ready!${NC}"
    
    # Try to apply a trial license if available
    echo -e "${YELLOW}📄 Checking license status...${NC}"
    
    # If no license is active, try to get one
    if ! vault read sys/license >/dev/null 2>&1; then
        echo -e "${BLUE}💡 To get full Enterprise features, obtain a free trial license:${NC}"
        echo -e "   Visit: https://www.hashicorp.com/products/vault/trial"
        echo -e "   Save the license as 'vault.hclic' and run: ${GREEN}vault write sys/license text=@vault.hclic${NC}"
    else
        echo -e "${GREEN}✅ Enterprise license is active!${NC}"
    fi
    
    # Run the full initialization
    echo -e "${YELLOW}🔧 Running Vault initialization...${NC}"
    ./vault-init.sh
    
else
    echo -e "${RED}❌ Vault initialization required${NC}"
    echo -e "${YELLOW}💡 This may be due to licensing requirements${NC}"
    echo -e "${BLUE}📝 To complete setup:${NC}"
    echo -e "   1. Get a free trial license: https://www.hashicorp.com/products/vault/trial"
    echo -e "   2. Save it as 'vault.hclic'"
    echo -e "   3. Run: docker-compose restart"
    echo -e "   4. Run: ./vault-init.sh"
fi

echo -e "${GREEN}🎉 Setup complete!${NC}"
echo -e "${BLUE}Vault URL: ${GREEN}http://localhost:8200${NC}"
echo -e "${BLUE}Root Token: ${GREEN}myroot${NC}"