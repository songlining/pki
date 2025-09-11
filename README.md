# HashiCorp Vault Enterprise PKI Demo with Vault Agent

This project demonstrates a complete HashiCorp Vault Enterprise PKI setup with Vault Agent for automatic certificate rotation and process supervision.

## 🚀 Features

- **Vault Enterprise** with full PKI capabilities
- **Vault Agent** for automatic certificate management
- **30-second certificate rotation** for demo purposes
- **Process supervisor** that restarts applications on certificate renewal
- **Real-time monitoring** of certificate lifecycle
- **Enterprise features** including certificate metadata and audit trails

## 📋 Prerequisites

- Docker and Docker Compose installed
- Vault CLI installed (for initialization and management)
- **HashiCorp Vault Enterprise license file** (see setup instructions below)

## 📝 License Setup (Required)

**Before starting, you need a Vault Enterprise license file:**

1. **Obtain a license**:
   - Get a trial or full license from HashiCorp
   - Download the license file (`.hclic` format)

2. **Place the license file**:
   ```bash
   # Copy your license file to the project root as 'vault.hclic'
   cp /path/to/your-license.hclic ./vault.hclic
   ```

3. **Verify the license file exists**:
   ```bash
   ls -la vault.hclic
   ```

⚠️  **Without a valid license file, Vault Enterprise will start but fail when accessing Enterprise features.**

## 🎯 Quick Start

### Complete Demo Setup
```bash
# Complete setup (start + initialize + agent configuration)
make setup

# Run the Vault Agent PKI demo with 30-second rotation
make agent-demo

# Or run the traditional interactive PKI demo
make demo
```

### Step-by-Step Setup
```bash
# Start Vault Enterprise and Vault Agent
make start

# Initialize Vault and configure PKI
make init

# Setup Vault Agent credentials
make setup-agent

# Run Vault Agent PKI demo
make agent-demo

# Watch certificate rotation in real-time
make watch-rotation
```

## 🏗️ Architecture

This setup includes two main components:

1. **Vault Enterprise Server** (`vault` container)
   - PKI secrets engine with root and intermediate CAs
   - AppRole authentication for Vault Agent
   - Enterprise features enabled

2. **Vault Agent** (`vault-agent` container)
   - Automatic certificate rotation (30-second TTL for demo)
   - Template-based certificate generation
   - Process supervision with automatic restarts
   - Real-time monitoring capabilities

## 📁 Configuration Files

### Core Configuration
- `docker-compose.yml` - Multi-container setup with Vault Enterprise and Vault Agent
- `.env` - Environment variables for Vault connection
- `vault.hclic` - Vault Enterprise license file (required)
- `vault-init.sh` - Initialization script for PKI setup

### Vault Agent Configuration
- `vault-agent-config/agent.hcl` - Vault Agent main configuration
- `vault-agent-config/cert.tpl` - Certificate template
- `vault-agent-config/key.tpl` - Private key template  
- `vault-agent-config/env.tpl` - Environment variables template
- `vault-agent-config/restart-app.sh` - Application restart script

### Demo Scripts
- `agent-pki-demo.sh` - Vault Agent PKI demo with 30-second rotation
- `pki-demo.sh` - Traditional interactive PKI demo
- `demo-process-supervisor.sh` - Process supervisor demonstration
- `watch-rotation.sh` - Real-time certificate rotation monitor

## 🎭 Demo Capabilities

### Vault Agent PKI Demo (`make agent-demo`)
- ✅ **Automatic certificate rotation** every 30 seconds
- ✅ **Real-time certificate monitoring** with serial number tracking
- ✅ **Process supervision** - applications restart on certificate renewal
- ✅ **Template-based certificate generation**
- ✅ **Environment variable injection**
- ✅ **Certificate metadata integration**

### Traditional PKI Demo (`make demo`)
- ✅ Root and Intermediate CA creation
- ✅ Certificate role configuration with short TTLs
- ✅ Certificate issuance with SANs and IP SANs
- ✅ Certificate metadata storage and retrieval
- ✅ Certificate chain verification
- ✅ Certificate revocation and CRL management

## 🛠️ Usage

### Starting the Environment
```bash
# Start all containers (Vault Enterprise + Vault Agent)
make start

# Check service status
make status

# View container logs
docker-compose logs -f
```

### Vault Agent Operations
```bash
# Monitor certificate rotation in real-time
make watch-rotation

# Check Vault Agent generated files
ls -la vault-agent-output/

# View current certificate information
cat vault-agent-output/app.env
```

### PKI Operations
```bash
# Issue a certificate manually
vault write pki/issue/example-role common_name="test.example.com" ttl="1h"

# List issued certificates
vault list pki/certs

# Check certificate metadata
vault read pki/cert/<serial-number>
```

### Stopping the Environment
```bash
# Stop containers
make stop

# Clean up everything (containers + volumes)
make clean
```

## 🔧 Available Make Commands

```bash
make help           # Show all available commands
make start          # Start Vault Enterprise and Vault Agent
make stop           # Stop all containers
make init           # Initialize Vault and configure PKI
make setup-agent    # Setup Vault Agent credentials
make setup          # Complete setup (start + init + agent)
make demo           # Run traditional interactive PKI demo
make agent-demo     # Run Vault Agent PKI demo with 30s rotation
make watch-rotation # Watch certificate rotation in real-time
make process-demo   # Run complete PKI + process supervisor demo
make status         # Show service status
make clean          # Clean up everything
```

## 📊 File Structure

```
.
├── docker-compose.yml          # Multi-container setup
├── .env                       # Environment variables
├── vault.hclic               # Vault Enterprise license (required)
├── vault-init.sh             # Vault initialization script
├── Makefile                  # Build automation
├── vault-agent-config/       # Vault Agent configuration
│   ├── agent.hcl            # Main agent config
│   ├── cert.tpl             # Certificate template
│   ├── key.tpl              # Private key template
│   ├── env.tpl              # Environment template
│   ├── restart-app.sh       # Application restart script
│   ├── role-id              # AppRole role ID
│   └── secret-id            # AppRole secret ID
├── vault-agent-output/       # Agent-generated files
│   ├── app.crt              # Current certificate
│   ├── app.key              # Current private key
│   ├── ca.crt               # CA certificate
│   └── app.env              # Environment variables
├── demo-scripts/            # Demonstration scripts
│   ├── agent-pki-demo.sh    # Vault Agent demo
│   ├── pki-demo.sh          # Traditional PKI demo
│   ├── demo-process-supervisor.sh # Process supervisor
│   └── watch-rotation.sh    # Rotation monitor
├── vault-config/            # Additional Vault config
└── README.md               # This file
```

## ⚡ Vault Agent Features

### Automatic Certificate Rotation
- Certificates have 30-second TTL for demonstration
- Vault Agent automatically renews certificates before expiration
- Templates are re-rendered on each renewal

### Process Supervision
- Applications restart automatically when certificates are renewed
- Environment variables are updated with new certificate metadata
- Zero-downtime certificate rotation

### Real-time Monitoring
- Watch certificate serial numbers change in real-time
- Monitor certificate expiration and renewal cycles
- Track application restarts during rotation

## 🔒 Security Notes

- This setup uses development mode with auto-unsealing
- Hardcoded root token (`myroot`) for development purposes
- TLS is disabled for easier development and debugging
- Certificate private keys have appropriate file permissions (0600)
- **Never use this configuration in production**
- All data is stored in Docker volumes and persists across restarts

## 🐛 Troubleshooting

### License Issues
```bash
# Check license file exists and is accessible
ls -la vault.hclic

# Check license loading in container logs
docker-compose logs vault | grep -i license

# Verify Enterprise features
vault read sys/health | grep enterprise
```

### Vault Agent Issues
```bash
# Check Vault Agent logs
docker-compose logs vault-agent

# Verify Agent can connect to Vault
docker exec vault-agent vault status

# Check generated files
ls -la vault-agent-output/
```

### Certificate Rotation
```bash
# Monitor rotation in real-time
make watch-rotation

# Check certificate expiration
openssl x509 -in vault-agent-output/app.crt -noout -dates

# Verify certificate chain
openssl verify -CAfile vault-agent-output/ca.crt vault-agent-output/app.crt
```

### Connection Issues
```bash
# Check container status
docker-compose ps

# Verify environment variables
echo $VAULT_ADDR
echo $VAULT_TOKEN

# Test Vault connectivity
curl $VAULT_ADDR/v1/sys/health
```