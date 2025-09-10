#!/bin/bash

# HashiCorp Vault Initialization Script
# This script sets up Vault with PKI capabilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Vault configuration
export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-myroot}"

echo -e "${BLUE}🚀 HashiCorp Vault PKI Setup${NC}"
echo "===================================="

# Wait for Vault to be ready
echo -e "${YELLOW}⏳ Waiting for Vault to be ready...${NC}"
timeout=30
counter=0
while ! curl -s $VAULT_ADDR/v1/sys/health >/dev/null 2>&1; do
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}❌ Timeout waiting for Vault to start${NC}"
        echo -e "${YELLOW}💡 Check container logs: docker-compose logs vault${NC}"
        exit 1
    fi
    echo "Waiting for Vault server... ($((counter + 1))/$timeout)"
    sleep 1
    counter=$((counter + 1))
done

echo -e "${GREEN}✅ Vault is ready!${NC}"
vault status

# Check Vault version for informational purposes
echo -e "${YELLOW}ℹ️  Checking Vault version...${NC}"
VAULT_VERSION=$(vault version | head -1)
echo -e "${BLUE}${VAULT_VERSION}${NC}"

# Enable PKI secrets engine if not already enabled
echo -e "${YELLOW}🔧 Enabling PKI secrets engine...${NC}"
if vault secrets list | grep -q "pki/"; then
    echo -e "${YELLOW}ℹ️  PKI secrets engine already enabled${NC}"
else
    vault secrets enable pki
    echo -e "${GREEN}✅ PKI secrets engine enabled!${NC}"
fi

# Set max lease TTL for PKI
echo -e "${YELLOW}⏰ Configuring PKI max lease TTL...${NC}"
vault secrets tune -max-lease-ttl=87600h pki

# Enable PKI intermediate engine if not already enabled
echo -e "${YELLOW}🔧 Enabling PKI intermediate secrets engine...${NC}"
if vault secrets list | grep -q "pki_int/"; then
    echo -e "${YELLOW}ℹ️  PKI intermediate secrets engine already enabled${NC}"
else
    vault secrets enable -path=pki_int pki
    echo -e "${GREEN}✅ PKI intermediate secrets engine enabled!${NC}"
fi

# Set max lease TTL for PKI intermediate
echo -e "${YELLOW}⏰ Configuring PKI intermediate max lease TTL...${NC}"
vault secrets tune -max-lease-ttl=43800h pki_int

echo -e "${GREEN}🎉 Vault PKI setup complete!${NC}"
echo ""
echo -e "${BLUE}Vault Information:${NC}"
echo "=================="
echo -e "Vault URL: ${GREEN}${VAULT_ADDR}${NC}"
echo -e "Vault Root Token: ${GREEN}${VAULT_TOKEN}${NC}"
echo -e "PKI Path: ${GREEN}pki/${NC}"
echo -e "PKI Intermediate Path: ${GREEN}pki_int/${NC}"
echo ""
echo -e "${YELLOW}💡 Your Vault instance is ready for PKI operations!${NC}"