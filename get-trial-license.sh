#!/bin/bash

# Automated Vault Enterprise Trial License Retrieval
# This script automates getting a 30-day trial license

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 HashiCorp Vault Enterprise Trial License Setup${NC}"
echo "=================================================="

# Check if license already exists
if [ -f "vault.hclic" ]; then
    echo -e "${GREEN}✅ License file already exists: vault.hclic${NC}"
    echo -e "${YELLOW}💡 If you need a fresh license, delete vault.hclic and run this script again${NC}"
    exit 0
fi

echo -e "${YELLOW}🔑 Getting Vault Enterprise trial license...${NC}"

# Get trial license using HashiCorp's trial API
echo -e "${BLUE}📡 Requesting 30-day trial license from HashiCorp...${NC}"

# Try to get trial license automatically
TRIAL_RESPONSE=$(curl -s -X POST \
  "https://api.hashicorp.com/v1/trials" \
  -H "Content-Type: application/json" \
  -d '{
    "product": "vault",
    "email": "dev@example.com",
    "company": "Development",
    "first_name": "Dev",
    "last_name": "User"
  }' 2>/dev/null || echo "")

if [ ! -z "$TRIAL_RESPONSE" ] && echo "$TRIAL_RESPONSE" | grep -q "license"; then
    echo "$TRIAL_RESPONSE" | jq -r '.license' > vault.hclic 2>/dev/null
    if [ $? -eq 0 ] && [ -s "vault.hclic" ]; then
        echo -e "${GREEN}✅ Trial license obtained and saved to vault.hclic${NC}"
    else
        echo -e "${RED}❌ Failed to parse license response${NC}"
        rm -f vault.hclic
    fi
else
    echo -e "${YELLOW}⚠️  Automatic license retrieval not available${NC}"
    echo -e "${BLUE}📝 Please get a trial license manually:${NC}"
    echo -e "${BLUE}   1. Visit: https://www.hashicorp.com/products/vault/trial${NC}"
    echo -e "${BLUE}   2. Fill out the form${NC}"
    echo -e "${BLUE}   3. Copy the license and save it as 'vault.hclic' in this directory${NC}"
    echo ""
    echo -e "${YELLOW}💡 Alternatively, create a development license placeholder:${NC}"
    read -p "Create a dev license placeholder? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat > vault.hclic << 'EOF'
# This is a development placeholder
# Replace with actual license from https://www.hashicorp.com/products/vault/trial
# The actual license will be a long base64-encoded string starting with something like:
# 02MV4UU43BK5HGYYTOJZWFQMTMNNEWG33JLJSWKZTVNZAWMU3FPBXKQZLONJXXGYLCOVRXGULTDK5WWWZTVNRJQ...
EOF
        echo -e "${GREEN}✅ Placeholder created. Replace vault.hclic with your actual trial license${NC}"
    fi
fi

if [ -f "vault.hclic" ]; then
    echo -e "${GREEN}🎉 Ready to proceed with Vault Enterprise setup!${NC}"
    echo -e "${YELLOW}💡 Next steps:${NC}"
    echo -e "   1. Run: docker-compose restart"
    echo -e "   2. Run: ./vault-init.sh"
else
    echo -e "${YELLOW}⚠️  No license file created. Please obtain a trial license manually.${NC}"
fi