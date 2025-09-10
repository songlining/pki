#!/bin/bash

echo "=== Vault Agent Certificate Rotation Demo ==="
echo "Watching certificate rotation with 30-second TTL..."
echo

# Function to show certificate and key details
show_cert_info() {
    echo "🕐 $(date '+%H:%M:%S') - Certificate & Key Status:"
    if docker exec vault-agent test -f /tmp/app.crt; then
        CERT_INFO=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -subject -dates 2>/dev/null)
        CERT_SERIAL=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -serial 2>/dev/null)
        CERT_TIME=$(docker exec vault-agent stat -c %Y /tmp/app.crt)
        KEY_TIME=$(docker exec vault-agent stat -c %Y /tmp/app.key)
        
        echo "   📜 Certificate:"
        echo "      $CERT_INFO"
        echo "      $CERT_SERIAL"
        echo "      Modified: $(docker exec vault-agent date -d @$CERT_TIME '+%H:%M:%S')"
        
        echo "   🔐 Private Key:"
        echo "      Modified: $(docker exec vault-agent date -d @$KEY_TIME '+%H:%M:%S')"
        echo "      Size: $(docker exec vault-agent stat -c %s /tmp/app.key) bytes"
        
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
    if docker exec vault-agent test -f /tmp/app.crt; then
        CURRENT_SERIAL=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2)
        
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