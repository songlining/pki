# HashiCorp Vault PKI Demo with Vault Agent

This project demonstrates a complete HashiCorp Vault PKI setup with Vault Agent for automatic certificate rotation and process supervision.

The repo now defaults to Vault Community Edition, so your audience can download it and run the demo without any commercial license.

## Features

- Vault PKI with root and intermediate certificate authorities
- Vault Agent for automatic certificate management
- Guided audience tracks for live demo, workshop, and operator-focused walkthroughs
- Demo preflight and safer reset workflow for presenters
- Least-privilege AppRole policy for Vault Agent
- 30-second certificate rotation for live demos
- Process supervision that restarts applications on certificate renewal
- Traditional interactive PKI demo with issuance, CSR signing, revocation, and CRL inspection
- Vault Agent demo showing automatic rotation, local file rendering, and full config/template walkthroughs

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
make preflight
make live-demo
```

### Step by step

```bash
make start
make init
make setup-agent
make preflight
make workshop-demo
```

### Alternative quick start

```bash
./quick-start.sh
```

After setup, choose the path that matches your audience:

- `make live-demo` - short narrative flow for a live presentation
- `make workshop-demo` - self-serve sequence for hands-on learners
- `make operator-demo` - AppRole, templates, and rotation-focused walkthrough

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

### Guided entrypoints

```bash
make live-demo
make workshop-demo
make operator-demo
```

These guided entrypoints frame the repo as one story with three audience-specific paths:

- operator establishes trust and policy
- machine consumes short-lived certificates through Vault Agent
- optional application/process demos show what rotation looks like in practice

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
- least-privilege Agent policy scoped to certificate issuance plus token self-management
- template-driven certificate generation
- 30-second TTL demo certificates
- automatic certificate rotation
- local file rendering for cert, key, and CA chain
- full-file walkthrough of `vault-agent-config/agent.hcl` and `vault-agent-config/cert.tpl`

### Process supervisor demo

```bash
make process-demo
```

This extends the Agent demo by showing how an application can react to certificate changes.

The rotation watcher output now highlights the most useful fields for a live audience:

- certificate subject
- `Valid from` and `Expires` timestamps
- certificate serial number
- matching certificate/key file modification times

## Common commands

```bash
make help
make start
make stop
make init
make setup-agent
make setup
make preflight
make live-demo
make workshop-demo
make operator-demo
make demo
make agent-demo
make process-demo
make watch-rotation
make reset-demo
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
- `demo-preflight.sh` - read-only demo readiness check
- `demo-paths.sh` - guided audience-track entrypoints
- `pki-demo.sh` - interactive PKI walkthrough
- `agent-pki-demo.sh` - Vault Agent certificate rotation walkthrough
- `demo-process-supervisor.sh` - application restart demo
- `reset-demo-state.sh` - safer cleanup of known generated demo files
- `setup-agent-credentials.sh` - writes the AppRole policy and Agent credentials
- `watch-rotation.sh` - shows certificate rotations with validity and serial details
- `vault-agent-config/agent.hcl` - Agent config
- `vault-agent-config/*.tpl` - certificate rendering templates

## Additional references

- `agent-demo-diagrams.md` - Mermaid diagrams for the Vault Agent flow and operator/machine split
- `tls-cert-gen-manual-vs-vault.md` - side-by-side explanation of manual certificate handling versus Vault-based issuance
- `manual-pki-tls-cert-gen.md` - detailed Mermaid sequence for the traditional CSR-and-ticket flow
- `GET_TRIAL_LICENSE.md` - legacy note explaining that the repo now runs on Vault CE without a license

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
- Demo cleanup defaults now target known generated files rather than broad wildcard deletion
- The Vault Agent AppRole is scoped to `pki/issue/example-role` plus token `lookup-self` and `renew-self`
- The AppRole is configured without the default policy
- This setup is for demos and learning, not production use

## Legacy helper scripts

The repo still contains a few legacy helper files from an earlier version of the demo, but the supported default path is now Vault CE and does not require licensing.
