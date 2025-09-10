# Vault Enterprise PKI Setup

This project demonstrates how to set up HashiCorp Vault Enterprise in Docker Compose development mode with full PKI capabilities.

## Prerequisites

- Docker and Docker Compose installed
- Vault CLI installed (for initialization and management)
- **HashiCorp Vault Enterprise license file** (see setup instructions below)

## License Setup (Required)

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

⚠️  **Without a valid license file, Vault Enterprise will start but fail when accessing Enterprise features or certain storage backends.**

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
- Mounts license file from `./vault.hclic` to `/vault/config/vault.hclic`
- Exposes Vault on port 8200

### `vault.hclic` (Required)
- HashiCorp Vault Enterprise license file
- Must be placed in the project root directory
- Automatically mounted into the container
- **Added to `.gitignore` to prevent accidental commits**

### `.env`
Contains environment variables:
- `VAULT_ADDR`: Vault server address
- `VAULT_TOKEN`: Root token for authentication
- `VAULT_DEV_ROOT_TOKEN_ID`: Development mode root token

### `vault-init.sh`
Initialization script that:
- Waits for Vault to be ready
- Verifies Enterprise features are available
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

This setup uses Vault Enterprise in development mode, which means:
- ✅ **All Enterprise features**: Full access to Enterprise capabilities with valid license
- ✅ **Auto-unsealing**: No manual unseal process required
- ✅ **Raft storage**: Persistent storage for Enterprise compliance (data survives restarts)
- ✅ **Pre-configured root token**: Uses `myroot` as the root token
- ✅ **TLS disabled**: HTTP-only for easier development
- ✅ **Certificate metadata**: Enterprise PKI features like certificate metadata work out of the box
- ⚠️  **License required**: Valid Enterprise license file must be provided
- ⚠️  **Not for production**: Development mode is not secure for production use

## Troubleshooting

### License Issues
```bash
# Check if license file exists
ls -la vault.hclic

# Check license loading in container logs
docker-compose logs vault | grep -i license

# Common license errors:
# "license check failed: no autoloaded license provided" = Missing license file
# "permission denied" = License file permissions issue
```

### Enterprise Features
```bash
# Verify Enterprise features are available
vault read sys/health | grep enterprise

# Check Vault Enterprise version
vault version

# Check license status (after Vault is running)
vault read sys/license/status
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