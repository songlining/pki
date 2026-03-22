# HashiCorp Vault PKI Demo with Vault Agent

This project demonstrates a complete HashiCorp Vault PKI setup with Vault Agent for automatic certificate rotation and process supervision.

The repo now defaults to Vault Community Edition, so your audience can download it and run the demo without any commercial license.

## Features

- Vault PKI with root and intermediate certificate authorities
- Vault Agent for automatic certificate management
- 30-second certificate rotation for live demos
- Process supervision that restarts applications on certificate renewal
- Traditional interactive PKI demo with issuance, CSR signing, revocation, and CRL inspection
- Vault Agent demo showing automatic rotation and local file rendering

## Prerequisites

- Docker with Docker Compose support
- Vault CLI
- `openssl`
- `jq`

No license file is required.

## Quick Start

### Complete setup

```bash
make setup
make agent-demo
```

### Step by step

```bash
make start
make init
make setup-agent
make demo
```

### Alternative quick start

```bash
./quick-start.sh
```

## What gets started

This setup includes two main containers:

1. `vault`
   - Vault Community Edition in development mode
   - PKI root and intermediate CAs
   - AppRole authentication for Vault Agent

2. `vault-agent`
   - Certificate rendering via templates
   - Automatic renewal before expiry
   - Process restart hooks for certificate updates

## Main demos

### Traditional PKI demo

```bash
make demo
```

This walkthrough covers:

- root and intermediate CA creation
- PKI role configuration
- leaf certificate issuance with SANs and IP SANs
- CSR-based signing where the private key stays outside Vault
- certificate inspection with OpenSSL
- certificate chain verification
- revocation and CRL inspection

### Vault Agent rotation demo

```bash
make agent-demo
```

This walkthrough covers:

- AppRole-based Agent authentication
- template-driven certificate generation
- 30-second TTL demo certificates
- automatic certificate rotation
- local file rendering for cert, key, and CA chain

### Process supervisor demo

```bash
make process-demo
```

This extends the Agent demo by showing how an application can react to certificate changes.

## Common commands

```bash
make help
make start
make stop
make init
make setup-agent
make setup
make demo
make agent-demo
make process-demo
make watch-rotation
make status
make clean
```

## Repository layout

```text
.
├── docker-compose.yml
├── docker-compose-temp.yml
├── Makefile
├── README.md
├── quick-start.sh
├── vault-init.sh
├── pki-demo.sh
├── agent-pki-demo.sh
├── demo-process-supervisor.sh
├── watch-rotation.sh
├── vault-config/
├── vault-agent-config/
└── vault-agent-output/
```

## Key files

- `docker-compose.yml` - default CE demo environment
- `vault-init.sh` - PKI and AppRole initialization
- `pki-demo.sh` - interactive PKI walkthrough
- `agent-pki-demo.sh` - Vault Agent certificate rotation walkthrough
- `demo-process-supervisor.sh` - application restart demo
- `vault-agent-config/agent.hcl` - Agent config
- `vault-agent-config/*.tpl` - certificate rendering templates

## Useful checks

```bash
docker compose ps
docker compose logs vault
docker compose logs vault-agent
vault status
openssl x509 -in vault-agent-output/app.crt -noout -dates -serial
```

## Security notes

- The demo runs Vault in development mode
- The root token is hardcoded to `myroot` for convenience
- TLS is disabled on the Vault API endpoint for ease of local testing
- This setup is for demos and learning, not production use

## Legacy helper scripts

The repo still contains a few legacy helper files from an earlier version of the demo, but the supported default path is now Vault CE and does not require licensing.
