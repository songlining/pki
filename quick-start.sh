#!/bin/bash

# Quick Start for Vault Community Edition with proper initialization

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Vault Community Edition Quick Start${NC}"
echo "=========================================="

# Stop any running containers
echo -e "${YELLOW}Stopping existing containers...${NC}"
docker-compose down -v >/dev/null 2>&1 || true

# Start Vault CE in dev mode
echo -e "${YELLOW}Starting Vault in dev mode...${NC}"
docker compose up -d vault

# Wait for Vault to be ready
echo -e "${YELLOW}Waiting for Vault...${NC}"
timeout=30
counter=0
while ! curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1; do
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}Timeout${NC}"
        exit 1
    fi
    echo "Waiting... ($((counter + 1))/$timeout)"
    sleep 1
    counter=$((counter + 1))
done

echo -e "${GREEN}Vault is running!${NC}"

# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

echo -e "${YELLOW}Checking Vault version...${NC}"
VAULT_VERSION=$(vault version | head -1)
echo -e "${BLUE}${VAULT_VERSION}${NC}"

echo -e "${YELLOW}Setting up PKI...${NC}"
vault secrets enable pki || echo "PKI already enabled"
vault secrets tune -max-lease-ttl=8760h pki || true

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${BLUE}Vault URL: ${GREEN}http://localhost:8200${NC}"
echo -e "${BLUE}Root Token: ${GREEN}myroot${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "   ${GREEN}./vault-init.sh${NC}       # Configure root/intermediate PKI and AppRole"
echo -e "   ${GREEN}make setup-agent${NC}     # Prepare Vault Agent credentials"
echo -e "   ${GREEN}make demo${NC}            # Run the interactive PKI demo"
