#!/bin/bash

# Source credential helper
source ./ensure-agent-credentials.sh

echo "=== Vault Agent Certificate Rotation Demo ==="
echo "Watching certificate rotation with 30-second TTL..."
echo

# Ensure credentials are available
ensure_agent_credentials

# Function to show certificate and key details
show_cert_info() {
    echo "🕐 $(date '+%H:%M:%S') - Certificate & Key Status:"
    if [ -f "vault-agent-output/app.crt" ]; then
        CERT_INFO=$(openssl x509 -in vault-agent-output/app.crt -noout -subject -dates 2>/dev/null)
        CERT_SERIAL=$(openssl x509 -in vault-agent-output/app.crt -noout -serial 2>/dev/null)
        CERT_TIME=$(stat -f %m vault-agent-output/app.crt)
        KEY_TIME=$(stat -f %m vault-agent-output/app.key)
        
        echo "   📜 Certificate:"
        echo "      $CERT_INFO"
        echo "      $CERT_SERIAL"
        echo "      Modified: $(date -r $CERT_TIME '+%H:%M:%S')"
        
        echo "   🔐 Private Key:"
        echo "      Modified: $(date -r $KEY_TIME '+%H:%M:%S')"
        echo "      Size: $(stat -f %z vault-agent-output/app.key) bytes"
        
        if [ "$CERT_TIME" -eq "$KEY_TIME" ]; then
            echo "   ✅ Certificate and key rotated together"
        else
            echo "   ⚠️  Certificate and key have different timestamps"
        fi
        echo
    else
        echo "   Certificate file not found"
        echo
    fi
}

echo "Initial certificate and private key:"
show_cert_info

echo "⏱️  Watching for certificate & private key rotation (press Ctrl+C to stop)..."
echo "   Both certificate AND private key rotate together when close to expiry (30 second TTL)"
echo

# Watch for changes
LAST_SERIAL=""
COUNTER=1

while true; do
    if [ -f "vault-agent-output/app.crt" ]; then
        CURRENT_SERIAL=$(openssl x509 -in vault-agent-output/app.crt -noout -serial 2>/dev/null | cut -d= -f2)
        
        if [ "$CURRENT_SERIAL" != "$LAST_SERIAL" ]; then
            echo "🔄 ROTATION DETECTED! (Check #$COUNTER)"
            show_cert_info
            LAST_SERIAL="$CURRENT_SERIAL"
            ((COUNTER++))
        else
            echo -n "."
        fi
    else
        echo "Certificate not found, waiting..."
    fi
    
    sleep 5
done