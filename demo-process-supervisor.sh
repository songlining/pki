#!/bin/bash

# Vault Agent Process Supervisor Demo Script
# Demonstrates automatic certificate rotation with application restart

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================${NC}\n"
}

print_step() {
    echo -e "${GREEN}STEP: $1${NC}"
}

print_important() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}OK: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_info() {
    echo -e "${CYAN}INFO: $1${NC}"
}

# Function to wait for user input
wait_for_user() {
    echo -e "${PURPLE}Press Enter to continue...${NC}"
    read -r
}

# Function to check if services are running
check_services() {
    print_step "Checking Vault and Vault Agent status..."
    
    if ! docker ps | grep -q vault-enterprise; then
        print_error "Vault Enterprise is not running!"
        exit 1
    fi
    
    if ! docker ps | grep -q vault-agent; then
        print_error "Vault Agent is not running!"
        exit 1
    fi
    
    print_success "Both services are running"
}

# Function to setup PKI role if needed
setup_pki_role() {
    print_step "Ensuring PKI role exists..."
    
    # Set environment variables for Vault access
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=myroot
    
    # Check if example-role exists
    if ! vault read pki/roles/example-role >/dev/null 2>&1; then
        print_important "Creating example-role for certificate generation..."
        vault write pki/roles/example-role \
            allowed_domains="example.com,localhost" \
            allow_subdomains=true \
            allow_localhost=true \
            allow_ip_sans=true \
            max_ttl="72h" \
            ttl="30s" >/dev/null
        print_success "PKI role created successfully"
    else
        print_success "PKI role already exists"
    fi
}

# Function to ensure Vault Agent credentials are valid
setup_agent_credentials() {
    print_step "Checking Vault Agent credentials..."
    
    # Set environment variables for Vault access
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=myroot
    
    # Check if secret-id file exists and has content
    if [ ! -f "vault-agent-config/secret-id" ] || [ ! -s "vault-agent-config/secret-id" ]; then
        print_important "Secret-id missing or empty, regenerating..."
        vault write -force -field=secret_id auth/approle/role/vault-agent-role/secret-id > vault-agent-config/secret-id
        chmod 600 vault-agent-config/secret-id
        print_success "New secret-id generated"
        
        # Restart Vault Agent to pick up new credentials
        print_step "Restarting Vault Agent with new credentials..."
        docker restart vault-agent >/dev/null
        sleep 3
    else
        print_success "Agent credentials exist"
    fi
}

# Function to show current certificate
show_current_cert() {
    if [ -f "./vault-agent-output/app.crt" ]; then
        SERIAL=$(openssl x509 -in "./vault-agent-output/app.crt" -noout -serial 2>/dev/null | cut -d= -f2)
        DATES=$(openssl x509 -in "./vault-agent-output/app.crt" -noout -dates 2>/dev/null)
        print_info "Current certificate serial: $SERIAL"
        echo -e "${CYAN}   $(echo "$DATES" | grep notBefore | cut -d= -f2-)${NC}"
        echo -e "${CYAN}   $(echo "$DATES" | grep notAfter | cut -d= -f2-)${NC}"
    else
        print_error "No certificate file found"
    fi
}

# Function to show vault agent logs
show_agent_logs() {
    print_step "Recent Vault Agent activity:"
    docker logs vault-agent --tail 10 | grep -E "(rendered|executing|spawning|starting|Application running)" | tail -5
}

filter_live_monitor_output() {
    perl -ne '
        BEGIN { $| = 1 }
        $visible = $_;
        $visible =~ s/\0//g;
        $visible =~ s/[^\x09\x0A\x0D\x1B\x20-\x7E]//g;

        $match = $visible;
        $match =~ s/\e\[[0-9;?]*[ -\/]*[@-~]//g;

        print $visible if $match =~ /MyApp starting up \(PID:/ ||
                           $match =~ /Environment CERT_SERIAL:/ ||
                           $match =~ /Current certificate serial:/ ||
                           $match =~ /Application running\.\.\. \(iteration / ||
                           $match =~ /Checking certificate status/ ||
                           $match =~ /Received SIGTERM - initiating graceful shutdown/ ||
                           $match =~ /Received SIGHUP - reloading configuration/ ||
                           $match =~ /Loaded environment from \/vault\/agent\/app\.env/ ||
                           $match =~ /Reloaded environment from \/vault\/agent\/app\.env/ ||
                           $match =~ /MyApp shutting down gracefully/ ||
                           $match =~ /MyApp stopped cleanly/ ||
                           $match =~ /automatically restarted every ~30s when certificates rotate/;
    '
}

show_current_startup_context() {
    print_step "Current startup context:"
    docker exec vault-agent sh -c 'if [ -f /tmp/myapp.log ]; then tail -n 200 /tmp/myapp.log; fi' | \
        perl -ne '
            BEGIN { $| = 1 }
            $visible = $_;
            $visible =~ s/\0//g;
            $visible =~ s/[^\x09\x0A\x0D\x1B\x20-\x7E]//g;

            $match = $visible;
            $match =~ s/\e\[[0-9;?]*[ -\/]*[@-~]//g;

            $startup = $visible if $match =~ /MyApp starting up \(PID:/;
            $env = $visible if $match =~ /Loaded environment from \/vault\/agent\/app\.env/ ||
                                     $match =~ /Reloaded environment from \/vault\/agent\/app\.env/;
            $serial = $visible if $match =~ /Environment CERT_SERIAL:/;

            END {
                print $startup if defined $startup;
                print $env if defined $env;
                print $serial if defined $serial;
            }
        '
}

# Main demo function
main() {
    clear
    print_header "VAULT AGENT PROCESS SUPERVISOR DEMO"
    
    echo -e "${CYAN}This demo showcases HashiCorp Vault Agent's process supervisor functionality"
    echo -e "with automatic certificate rotation and application restart.${NC}\n"
    
    echo -e "${YELLOW}Key Features:${NC}"
    echo -e "- Automatic certificate rotation (30-second TTL)"
    echo -e "- Process supervisor restarts application on certificate changes"
    echo -e "- Environment template generation"
    echo -e "- Zero-downtime certificate rotation"
    echo -e "- Signal handling (SIGTERM, SIGHUP)"
    
    wait_for_user
    
    # Step 1: Check services
    print_header "Step 1: Service Status Check"
    check_services
    
    wait_for_user
    
    # Step 1.5: Setup PKI role and credentials
    print_header "Step 1.5: PKI Configuration & Credentials"
    setup_pki_role
    setup_agent_credentials
    
    wait_for_user
    
    # Step 2: Show current setup
    print_header "Step 2: Current Configuration"
    print_step "Vault Agent configuration highlights:"
    echo -e "${CYAN}   - Template with command execution: /bin/sh /vault/config/myapp.sh${NC}"
    echo -e "${CYAN}   - Environment template: vault-agent-config/env.tpl${NC}"
    echo -e "${CYAN}   - Certificate TTL: 30 seconds${NC}"
    echo -e "${CYAN}   - Auto-restart on certificate rotation${NC}"
    
    wait_for_user
    
    # Step 3: Show current certificate
    print_header "Step 3: Current Certificate Status"
    show_current_cert
    
    wait_for_user
    
    # Step 4: Show live application logs
    print_header "Step 4: Live Application Monitoring"
    print_step "Monitoring application logs in real-time..."
    print_important "Watch for:"
    echo -e "${YELLOW}   - Certificate serial number changes${NC}"
    echo -e "${YELLOW}   - Process restarts (PID changes)${NC}"
    echo -e "${YELLOW}   - Iteration counter resets / heartbeat lines${NC}"
    echo -e "${YELLOW}   - Reload and shutdown events during rotation${NC}"
    
    show_current_startup_context
    
    echo -e "\n${PURPLE}Starting live log monitoring... (Press Ctrl+C to stop)${NC}\n"
    
    # Follow the app log written by restart-app.sh inside the container.
    docker exec vault-agent sh -c 'touch /tmp/myapp.log && exec tail -n 0 -f /tmp/myapp.log' | \
        filter_live_monitor_output &
    LOG_PID=$!
    
    # Wait for user to stop
    trap "kill $LOG_PID 2>/dev/null || true" EXIT
    
    echo -e "\n${GREEN}Demo completed! You should have observed:${NC}"
    echo -e "${GREEN}OK: Automatic application restarts every ~30 seconds${NC}"
    echo -e "${GREEN}OK: Certificate serial number changes${NC}"
    echo -e "${GREEN}OK: Process ID changes indicating real restarts${NC}"
    echo -e "${GREEN}OK: Environment variable reloading${NC}"
    
    wait
}

# Cleanup function
cleanup() {
    print_info "Cleaning up..."
    kill $LOG_PID 2>/dev/null || true
}

trap cleanup EXIT

# Run the demo
main "$@"
