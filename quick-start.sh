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
echo "This path leaves the repo ready for a live demo, workshop, or operator walkthrough."
echo ""

# Stop any running containers without deleting local volumes
echo -e "${YELLOW}Stopping existing containers...${NC}"
docker compose down >/dev/null 2>&1 || true

echo -e "${YELLOW}Starting Vault and Vault Agent containers...${NC}"
docker compose up -d

echo -e "${YELLOW}Initializing PKI and AppRole...${NC}"
./vault-init.sh

echo -e "${YELLOW}Refreshing Vault Agent bootstrap credentials...${NC}"
./setup-agent-credentials.sh
docker restart vault-agent >/dev/null

echo -e "${YELLOW}Running demo preflight...${NC}"
./demo-preflight.sh

echo -e "${GREEN}Quick start complete!${NC}"
echo ""
echo "Choose your path:"
echo -e "   ${GREEN}make live-demo${NC}      # Short live story: operator first, then automation"
echo -e "   ${GREEN}make workshop-demo${NC}  # Hands-on sequence for self-serve learners"
echo -e "   ${GREEN}make operator-demo${NC}  # Focus on AppRole, templates, and rotation"
echo -e "   ${GREEN}make reset-demo${NC}    # Safe cleanup of known generated demo state"
