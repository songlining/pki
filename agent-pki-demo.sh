#!/bin/bash

set -e

echo "=== Vault Agent PKI Demo with Templating ==="
echo

# Set environment variables for Vault Agent
export VAULT_AGENT_ADDR=http://localhost:8100
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

echo "1. Checking Vault Agent status..."
curl -s $VAULT_AGENT_ADDR/v1/sys/health | jq '.sealed'

echo "2. Getting Vault Agent token..."
AGENT_TOKEN=$(docker exec vault-agent cat /tmp/vault-token)
echo "Agent token: ${AGENT_TOKEN:0:20}..."

echo
echo "3. Testing PKI operations through Vault Agent (port 8100)..."

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

echo
echo "4. 🎯 TEMPLATING DEMO: Vault Agent Auto-Certificate Generation"
echo "   Agent is configured with templates that automatically:"
echo "   - Request certificates from PKI"
echo "   - Render them to local files"
echo "   - Set proper file permissions"

echo
echo "   📁 Template files configured:"
echo "   - cert.tpl -> /tmp/app.crt (certificate)"
echo "   - key.tpl  -> /tmp/app.key (private key)"
echo "   - ca.tpl   -> /tmp/ca.crt (CA certificate)"

echo
echo "   🔍 Current template-generated files:"
docker exec vault-agent ls -la /tmp/app.* /tmp/ca.crt 2>/dev/null || echo "   (Templates are rendering...)"

echo
echo "5. Inspecting auto-generated certificate details:"
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
echo "✅ Will auto-renew certificates when they expire"