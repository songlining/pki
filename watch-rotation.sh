#!/bin/bash

echo "=== Vault Agent Certificate Rotation Demo ==="
echo "Watching certificate rotation with 30-second TTL..."
echo

# Function to show certificate details
show_cert_info() {
    echo "🕐 $(date '+%H:%M:%S') - Certificate Status:"
    if docker exec vault-agent test -f /tmp/app.crt; then
        CERT_INFO=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -subject -dates 2>/dev/null)
        CERT_SERIAL=$(docker exec vault-agent cat /tmp/app.crt | openssl x509 -noout -serial 2>/dev/null)
        FILE_TIME=$(docker exec vault-agent stat -c %Y /tmp/app.crt)
        echo "   $CERT_INFO"
        echo "   $CERT_SERIAL"
        echo "   File modified: $(docker exec vault-agent date -d @$FILE_TIME)"
        echo
    else
        echo "   Certificate file not found"
        echo
    fi
}

echo "Initial certificate:"
show_cert_info

echo "⏱️  Watching for certificate rotation (press Ctrl+C to stop)..."
echo "   Certificate should rotate when it's close to expiry (30 second TTL)"
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