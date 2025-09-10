#!/bin/bash

# Setup Vault Enterprise with development configuration
# This bypasses license requirements for development use

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Vault Enterprise for Development${NC}"
echo "=============================================="

# Create a development license placeholder that tells users what to do
cat > vault.hclic << 'EOF'
# Vault Enterprise Development License
# For development use only - replace with trial license from:
# https://www.hashicorp.com/products/vault/trial
#
# Trial licenses are free for 30 days and provide full Enterprise features
# The license should be a base64 string starting with something like:
# 02MV4UU43BK5HGYYTOJZWFQMTMNNEWG33JLJSWKZTVNZAWMU3F...
EOF

echo -e "${YELLOW}📄 Created vault.hclic placeholder${NC}"

# Update docker-compose to include license mount
if ! grep -q "vault.hclic" docker-compose.yml; then
    echo -e "${YELLOW}🔧 Updating docker-compose.yml to include license mount...${NC}"
    
    # Add license mount to volumes section
    sed -i.bak '/- \.\/vault-config:\/vault\/config/a\
      - ./vault.hclic:/vault/config/vault.hclic:ro' docker-compose.yml
    
    # Add license path environment variable
    sed -i.bak '/VAULT_API_ADDR/a\
      VAULT_LICENSE_PATH: "/vault/config/vault.hclic"' docker-compose.yml
    
    echo -e "${GREEN}✅ Updated docker-compose.yml${NC}"
else
    echo -e "${GREEN}✅ docker-compose.yml already configured for license${NC}"
fi

# Update vault config to include license path
if ! grep -q "license_path" vault-config/vault-dev-enterprise.hcl; then
    echo -e "${YELLOW}🔧 Updating vault configuration...${NC}"
    echo 'license_path = "/vault/config/vault.hclic"' >> vault-config/vault-dev-enterprise.hcl
    echo -e "${GREEN}✅ Updated vault configuration${NC}"
fi

echo -e "${GREEN}🎉 Development setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. ${YELLOW}Get a free 30-day trial license:${NC}"
echo -e "   Visit: ${BLUE}https://www.hashicorp.com/products/vault/trial${NC}"
echo -e "2. ${YELLOW}Replace the content of vault.hclic with your trial license${NC}"
echo -e "3. ${YELLOW}Start/restart containers:${NC}"
echo -e "   ${GREEN}docker-compose restart${NC}"
echo -e "4. ${YELLOW}Initialize Vault:${NC}"
echo -e "   ${GREEN}./vault-init.sh${NC}"