# Vault Enterprise PKI Setup

This project demonstrates how to set up HashiCorp Vault Enterprise in Docker Compose with licensing and PKI capabilities.

## Prerequisites

- Docker and Docker Compose installed
- A valid Vault Enterprise license file (`vault.hclic`)
- Vault CLI installed (for initialization and management)

## Quick Start

1. **Complete setup (start + initialize)**:
   ```bash
   make setup
   ```

2. **Run the interactive demo**:
   ```bash
   make demo
   ```

3. **Or do it manually**:
   ```bash
   # Start Vault Enterprise
   make start

   # Initialize Vault
   make init

   # Run the PKI certificate demo
   make demo
   ```

## Configuration Files

### `docker-compose.yml`
- Uses `hashicorp/vault-enterprise` image
- Runs in development mode with auto-unsealing
- Mounts license file and configuration directory
- Exposes Vault on port 8200

### `.env`
Contains environment variables:
- `VAULT_ADDR`: Vault server address
- `VAULT_TOKEN`: Root token for authentication
- `VAULT_DEV_ROOT_TOKEN_ID`: Development mode root token

### `vault.hclic`
Your Vault Enterprise license file. This file must contain a valid license key.

### `vault-init.sh`
Initialization script that:
- Waits for Vault to be ready
- Verifies license status
- Enables PKI secrets engines
- Configures appropriate lease TTLs

## Usage

### Starting the Environment
```bash
# Start containers
docker-compose up -d

# Initialize Vault (first time only)
./vault-init.sh

# Check status
docker-compose ps
```

### Stopping the Environment
```bash
# Stop containers
docker-compose down

# Remove volumes (optional - will delete all data)
docker-compose down -v
```

### Working with PKI

After initialization, you'll have two PKI engines enabled:

- `pki/` - Root CA (max lease: 10 years)  
- `pki_int/` - Intermediate CA (max lease: 5 years)

Example PKI operations:
```bash
# Generate root CA
vault write -field=certificate pki/root/generate/internal \
    common_name="My Root CA" \
    ttl=87600h > root_ca.crt

# Configure PKI URLs
vault write pki/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
```

## Development Mode Notes

This setup uses Vault in development mode, which means:
- ✅ **Auto-unsealing**: No manual unseal process required
- ✅ **In-memory storage**: No persistent storage (data lost on restart)
- ✅ **Pre-configured root token**: Uses `myroot` as the root token
- ✅ **TLS disabled**: HTTP-only for easier development
- ⚠️  **Not for production**: Development mode is not secure for production use

## Troubleshooting

### License Issues
```bash
# Check license status
vault read sys/license

# Verify license file exists and is readable
ls -la vault.hclic
```

### Connection Issues
```bash
# Check if Vault is running
docker-compose ps

# Check Vault logs
docker-compose logs vault

# Verify environment variables
echo $VAULT_ADDR
echo $VAULT_TOKEN
```

### Container Issues
```bash
# Restart containers
docker-compose restart

# Clean restart (removes volumes)
docker-compose down -v && docker-compose up -d
```

## PKI Certificate Demo

The included `pki-demo.sh` script provides an interactive demonstration of:

- ✅ Root and Intermediate CA creation
- ✅ Certificate role configuration  
- ✅ Certificate issuance with SANs and IP SANs
- ✅ Certificate metadata storage and retrieval
- ✅ Certificate chain verification
- ✅ Certificate revocation and CRL management
- ✅ File-based certificate management

### Running the Demo

```bash
# Complete setup and run demo
make setup && make demo

# Or step by step
make start    # Start containers
make init     # Initialize Vault
make demo     # Run interactive demo
```

The demo uses `demo-magic.sh` for paced presentation - press ENTER to advance through each step.

## Available Commands

```bash
make help     # Show available commands
make start    # Start Vault Enterprise
make init     # Initialize and configure Vault
make demo     # Run PKI certificate demo  
make status   # Show service status
make clean    # Clean up everything
```

## File Structure

```
.
├── docker-compose.yml    # Docker Compose configuration
├── .env                 # Environment variables
├── vault.hclic          # Vault Enterprise license
├── vault-init.sh        # Initialization script
├── pki-demo.sh          # Interactive PKI demo
├── demo-magic.sh        # Demo presentation framework
├── vault-config/        # Additional Vault configuration
├── Makefile            # Build automation
└── README.md           # This file
```

## Security Notes

- The setup uses a hardcoded root token (`myroot`) for development
- TLS is disabled for easier development
- All data is stored in memory and will be lost when containers restart
- **Never use this configuration in production**