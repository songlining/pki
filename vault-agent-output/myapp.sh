#!/bin/bash

# MyApp - Demo application with signal handling
# Handles SIGTERM for graceful shutdown and SIGHUP for configuration reload

# Global flag for graceful shutdown
RUNNING=true

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to display environment variables and certificate details
show_config() {
    log "=== Configuration ==="
    if [ -n "$CERT_FILE" ]; then
        log "CERT_FILE: $CERT_FILE"
        if [ -f "$CERT_FILE" ]; then
            CERT_SIZE=$(stat -f %z "$CERT_FILE" 2>/dev/null || stat -c %s "$CERT_FILE" 2>/dev/null)
            log "  Certificate file exists ($CERT_SIZE bytes)"
            
            # Extract certificate details
            CERT_SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial 2>/dev/null | cut -d= -f2)
            CERT_DATES=$(openssl x509 -in "$CERT_FILE" -noout -dates 2>/dev/null)
            CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null | cut -d= -f2-)
            
            if [ -n "$CERT_SERIAL" ]; then
                log "  Serial Number: $CERT_SERIAL"
                log "  Subject: $CERT_SUBJECT"
                log "  $(echo "$CERT_DATES" | grep notBefore | cut -d= -f2-)"
                log "  $(echo "$CERT_DATES" | grep notAfter | cut -d= -f2-)"
            else
                log "  Unable to parse certificate details"
            fi
        else
            log "  Certificate file not found!"
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
            log "  Private key file not found!"
        fi
    else
        log "PRIVATE_KEY_FILE: (not set)"
    fi
    log "===================="
}

# Signal handler for SIGTERM (graceful shutdown)
handle_sigterm() {
    log "Received SIGTERM - initiating graceful shutdown..."
    RUNNING=false
}

# Signal handler for SIGHUP (configuration reload)
handle_sighup() {
    log "Received SIGHUP - reloading configuration..."
    
    # Reload environment variables if available
    if [ -f "/vault/agent/app.env" ]; then
        source /vault/agent/app.env
        log "Reloaded environment from /vault/agent/app.env"
    fi
    
    show_config
}

# Set up signal traps
trap handle_sigterm SIGTERM SIGINT
trap handle_sighup SIGHUP

# Load environment variables if available
if [ -f "/vault/agent/app.env" ]; then
    source /vault/agent/app.env
    log "Loaded environment from /vault/agent/app.env"
fi

# Application startup
log "MyApp starting up (PID: $$)"
log "Send SIGTERM to shutdown gracefully: kill -TERM $$"
log "Send SIGHUP to reload configuration: kill -HUP $$"

# Show initial configuration
show_config

# Main application loop
COUNTER=0
while [ "$RUNNING" = true ]; do
    COUNTER=$((COUNTER + 1))
    
    # Simulate application work
    log "Application running... (iteration $COUNTER)"
    
    # Sleep for a short time but allow signal interruption
    sleep 5 || break
done

# Cleanup and shutdown
log "MyApp shutting down gracefully..."
log "Final iteration count: $COUNTER"
log "MyApp stopped"

exit 0