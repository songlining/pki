# HashiCorp Vault PKI Demo with Vault Agent

This project demonstrates a complete HashiCorp Vault PKI setup with Vault Agent for automatic certificate rotation and process supervision.

The repo defaults to Vault Community Edition, but it can also run in Vault Enterprise mode when an existing local `vault.hclic` file is present.

## Features

- Vault PKI with root and intermediate certificate authorities
- Vault Community Edition by default, with optional Vault Enterprise container selection
- Vault Agent for automatic certificate management
- Guided audience tracks for live demo, workshop, and operator-focused walkthroughs
- Demo preflight and safer reset workflow for presenters
- Least-privilege AppRole policy for Vault Agent
- 30-second certificate rotation for live demos
- Process supervision that restarts applications on certificate renewal
- Traditional interactive PKI demo with issuance, CSR signing, revocation, and CRL inspection
- Vault Agent demo showing automatic rotation, local file rendering, and full config/template walkthroughs
- Parallel cert-auth Vault Agent variant showing client-certificate auto-auth and agent-driven credential rotation

## Prerequisites

- Docker with Docker Compose support
- Vault CLI
- `openssl`
- `jq`

No license file is required.

If you want to use Vault Enterprise for the demo, place an existing license file at `./vault.hclic`.

## Quick Start

### Complete setup

```bash
make setup
make preflight
make live-demo
```

### Cert-auth variant setup

```bash
make setup-cert            # vault + mock-oidc + JWT auth + first bootstrap cert
make live-demo-cert        # guided 5-step walkthrough (auto_auth method "cert")
make watch-cert-rotation   # optional: watch the host cert + token accessor rotate
```

This path starts Vault with the development TLS listener because Vault's `auth/cert` method requires client certificates on the TLS connection. It keeps the other demos unchanged.

For the full step-by-step scenario (what each step shows, what to narrate, and the CI-simulated bootstrap), see [docs/demos.md](docs/demos.md#vault-agent-cert-auth-rotation-demo). For the bootstrap design, see [docs/gitlab-ci-provisioning-design.md](docs/gitlab-ci-provisioning-design.md).

### Enterprise edition setup

```bash
make setup VAULT_EDITION=enterprise
make preflight VAULT_EDITION=enterprise
make live-demo
```

This uses `docker-compose.enterprise.yml` on top of the default compose file and fails clearly if `./vault.hclic` is missing.

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

To use Vault Enterprise with the quick start path:

```bash
VAULT_EDITION=enterprise ./quick-start.sh
```

After setup, choose the path that matches your audience:

- `make live-demo` - short narrative flow for a live presentation
- `make workshop-demo` - self-serve sequence for hands-on learners
- `make operator-demo` - AppRole, templates, and rotation-focused walkthrough
- `make live-demo-cert` - cert-auth Agent variant with self-rotating host credential (guided 5-step walkthrough)

## What gets started

This setup includes two main containers:

1. `vault`
   - Vault Community Edition in development mode by default
   - Optional Vault Enterprise image when `VAULT_EDITION=enterprise`
   - PKI root and intermediate CAs
   - AppRole authentication for Vault Agent

2. `vault-agent`
   - Certificate rendering via templates
   - Automatic renewal before expiry
   - Process restart hooks for certificate updates

## Demos

The walkthroughs (traditional PKI, Vault Agent rotation, cert-auth rotation, process supervisor) all live in [docs/demos.md](docs/demos.md) with the scenario script for each. Quick reference:

```bash
make live-demo          # short narrative for a live presentation
make workshop-demo      # self-serve sequence
make operator-demo      # AppRole, templates, rotation walkthrough
make live-demo-cert     # cert-auth variant, 5-step guided walkthrough
make demo               # traditional interactive PKI demo
make agent-demo         # Vault Agent rotation (AppRole)
make process-demo       # process supervisor reacting to rotation
```

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
make setup-cert
make agent-demo-cert
make live-demo-cert
make watch-cert-rotation
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
├── docker-compose.cert.yml
├── docker-compose-temp.yml
├── Makefile
├── README.md
├── quick-start.sh
├── vault-init.sh
├── vault-init-cert.sh
├── provision-host-cert.sh
├── pki-demo.sh
├── agent-pki-demo.sh
├── demo-process-supervisor.sh
├── watch-rotation.sh
├── watch-cert-rotation.sh
├── vault-config/
├── vault-agent-config/
└── vault-agent-output/
```

## Key files

- `docker-compose.yml` - default CE demo environment
- `docker-compose.enterprise.yml` - Enterprise override for the Vault container and license mount
- `docker-compose.cert.yml` - TLS/cert-auth override, cert-auth Agent service, and mock OIDC issuer
- `vault-init.sh` - PKI and AppRole initialization
- `vault-init-cert.sh` - cert-auth role, host issuance role, host policy, **JWT auth method (`jwt-gitlab`), bootstrap PKI role, and `pki-bootstrap-policy`**
- `provision-host-cert.sh` - legacy root-token bootstrap kept for fallback; the demo now uses the CI simulator below
- `simulate-ci-bootstrap.sh` - simulated GitLab CI bootstrap using a mock OIDC id_token and Vault JWT auth (no root token)
- `simulate-ci-bootstrap-bad.sh` - negative test: a wrong-project JWT is rejected by `bound_claims`
- `mock-oidc/` - tiny Python/Flask OIDC issuer used by the bootstrap simulator
- `demo-preflight.sh` - read-only demo readiness check
- `demo-paths.sh` - guided audience-track entrypoints
- `pki-demo.sh` - interactive PKI walkthrough
- `agent-pki-demo.sh` - Vault Agent certificate rotation walkthrough
- `demo-process-supervisor.sh` - application restart demo
- `reset-demo-state.sh` - safer cleanup of known generated demo files
- `setup-agent-credentials.sh` - writes the AppRole policy and Agent credentials
- `watch-rotation.sh` - shows certificate rotations with validity and serial details
- `watch-cert-rotation.sh` - shows the Agent's own cert-auth credential rotation and re-authentication
- `vault-agent-config/agent.hcl` - Agent config
- `vault-agent-config/agent-cert.hcl` - cert-auth Agent config
- `vault-agent-config/*.tpl` - certificate rendering templates

## Additional references

- [docs/demos.md](docs/demos.md) - demo sequences and scenario scripts for every walkthrough
- [docs/gitlab-ci-provisioning-design.md](docs/gitlab-ci-provisioning-design.md) - JWT/OIDC bootstrap design for the cert-auth variant
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
- The Vault Agent AppRole is scoped to `pki/issue/app-role` plus token `lookup-self` and `renew-self`
- The AppRole is configured without the default policy
- This setup is for demos and learning, not production use

## Legacy helper scripts

The repo still contains a few legacy helper files from an earlier version of the demo, but the supported default path is now Vault CE and does not require licensing.
