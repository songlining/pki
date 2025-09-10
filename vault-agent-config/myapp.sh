#!/bin/bash

# MyApp - Demo application with signal handling and certificate rotation monitoring
# Demonstrates Vault Agent process supervisor with automatic certificate rotation
# Handles SIGTERM for graceful shutdown and SIGHUP for configuration reload

# Global flag for graceful shutdown
RUNNING=true

# Function to log messages with timestamp and color
log() {
    echo -e "\033[1;32m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $*"
}

# Function to log important events in cyan
log_important() {
    echo -e "\033[1;36m[$(date '+%Y-%m-%d %H:%M:%S')] 🔄 $*\033[0m"
}

# Function to log certificate details in yellow
log_cert() {
    echo -e "\033[1;33m[$(date '+%Y-%m-%d %H:%M:%S')] 📜 $*\033[0m"
}

# Function to display environment variables and certificate details
show_config() {
    log_important "=== CERTIFICATE CONFIGURATION ==="
    
    # Show environment variables for tracking
    if [ -n "$CERT_SERIAL" ]; then
        log_cert "Environment CERT_SERIAL: $CERT_SERIAL"
    fi
    
    if [ -n "$CERT_FILE" ]; then
        log "CERT_FILE: $CERT_FILE"
        if [ -f "$CERT_FILE" ]; then
            CERT_SIZE=$(stat -f %z "$CERT_FILE" 2>/dev/null || stat -c %s "$CERT_FILE" 2>/dev/null)
            log "  Certificate file exists ($CERT_SIZE bytes)"
            
            # Extract certificate details
            CERT_SERIAL_FILE=$(openssl x509 -in "$CERT_FILE" -noout -serial 2>/dev/null | cut -d= -f2)
            CERT_DATES=$(openssl x509 -in "$CERT_FILE" -noout -dates 2>/dev/null)
            CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null | cut -d= -f2-)
            
            if [ -n "$CERT_SERIAL_FILE" ]; then
                log_cert "  File Serial Number: $CERT_SERIAL_FILE"
                log "  Subject: $CERT_SUBJECT"
                
                # Parse and display dates in readable format
                NOT_BEFORE=$(echo "$CERT_DATES" | grep notBefore | cut -d= -f2-)
                NOT_AFTER=$(echo "$CERT_DATES" | grep notAfter | cut -d= -f2-)
                log "  Valid From: $NOT_BEFORE"
                log "  Valid Until: $NOT_AFTER"
                
                # Calculate TTL remaining
                if command -v date >/dev/null 2>&1; then
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        # macOS date command
                        EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$NOT_AFTER" "+%s" 2>/dev/null)
                    else
                        # Linux date command
                        EXPIRY_EPOCH=$(date -d "$NOT_AFTER" "+%s" 2>/dev/null)
                    fi
                    
                    if [ -n "$EXPIRY_EPOCH" ]; then
                        CURRENT_EPOCH=$(date "+%s")
                        TTL_REMAINING=$((EXPIRY_EPOCH - CURRENT_EPOCH))
                        if [ $TTL_REMAINING -gt 0 ]; then
                            log_cert "  TTL Remaining: ${TTL_REMAINING} seconds"
                        else
                            log_cert "  ⚠️ Certificate EXPIRED!"
                        fi
                    fi
                fi
            else
                log "  Unable to parse certificate details"
            fi
        else
            log "  ❌ Certificate file not found!"
        fi
    else
        log "CERT_FILE: (not set)"
    fi
    
    if [ -n "$PRIVATE_KEY_FILE" ]; then
        log "PRIVATE_KEY_FILE: $PRIVATE_KEY_FILE"
        if [ -f "$PRIVATE_KEY_FILE" ]; then
            KEY_SIZE=$(stat -f %z "$PRIVATE_KEY_FILE" 2>/dev/null || stat -c %s "$PRIVATE_KEY_FILE" 2>/dev/null)
            log "  Private key file exists ($KEY_SIZE bytes)"
            
            # Extract key type and size
            KEY_INFO=$(openssl pkey -in "$PRIVATE_KEY_FILE" -text -noout 2>/dev/null | head -1)
            if [ -n "$KEY_INFO" ]; then
                log "  Key Type: $KEY_INFO"
            fi
        else
            log "  ❌ Private key file not found!"
        fi
    else
        log "PRIVATE_KEY_FILE: (not set)"
    fi
    log_important "=================================="
}

# Signal handler for SIGTERM (graceful shutdown)
handle_sigterm() {
    log_important "🛑 Received SIGTERM - initiating graceful shutdown..."
    RUNNING=false
}

# Signal handler for SIGHUP (configuration reload)
handle_sighup() {
    log_important "🔄 Received SIGHUP - reloading configuration..."
    
    # Reload environment variables if available
    if [ -f "/vault/agent/app.env" ]; then
        source /vault/agent/app.env
        log_important "Reloaded environment from /vault/agent/app.env"
    fi
    
    show_config
}

# Set up signal traps
trap handle_sigterm SIGTERM SIGINT
trap handle_sighup SIGHUP

# Load environment variables if available
if [ -f "/vault/agent/app.env" ]; then
    source /vault/agent/app.env
    log_important "Loaded environment from /vault/agent/app.env"
fi

# Application startup
log_important "🚀 MyApp starting up (PID: $$)"
log_important "📧 Send SIGTERM to shutdown gracefully: kill -TERM $$"
log_important "🔄 Send SIGHUP to reload configuration: kill -HUP $$"
echo ""
log_important "🎯 VAULT AGENT PROCESS SUPERVISOR DEMO"
log_important "📋 This application will be automatically restarted every ~30s when certificates rotate"
log_important "🔑 Watch for certificate serial number changes indicating rotation!"
echo ""

# Show initial configuration
show_config

# Main application loop
COUNTER=0
while [ "$RUNNING" = true ]; do
    COUNTER=$((COUNTER + 1))
    
    # Simulate application work with certificate monitoring
    if [ $((COUNTER % 6)) -eq 1 ] && [ $COUNTER -gt 1 ]; then
        # Every 30 seconds (6 iterations * 5 seconds), show certificate status
        log_important "🔍 Checking certificate status..."
        if [ -n "$CERT_FILE" ] && [ -f "$CERT_FILE" ]; then
            CURRENT_SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial 2>/dev/null | cut -d= -f2)
            if [ -n "$CURRENT_SERIAL" ]; then
                log_cert "Current certificate serial: $CURRENT_SERIAL"
            fi
        fi
    fi
    
    # Regular application work
    log "🔧 Application running... (iteration $COUNTER)"
    
    # Sleep for a short time but allow signal interruption
    sleep 5 || break
done

# Cleanup and shutdown
log_important "🛑 MyApp shutting down gracefully..."
log_important "📊 Final iteration count: $COUNTER"
log_important "✅ MyApp stopped cleanly"

exit 0