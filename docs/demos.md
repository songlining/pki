# Demo Sequences and Scenarios

This document collects the demo walkthroughs offered by this repo. The top-level [README](../README.md) covers setup and commands; this file is the scenario script — what each demo shows, what story to tell, and which Make targets drive it.

For the underlying GitLab CI / JWT-auth bootstrap design used by the cert-auth variant, see [gitlab-ci-provisioning-design.md](gitlab-ci-provisioning-design.md). For diagrams, see [../agent-demo-diagrams.md](../agent-demo-diagrams.md).

## Audience-track entrypoints

```bash
make live-demo        # short narrative flow for a live presentation
make workshop-demo    # self-serve sequence for hands-on learners
make operator-demo    # AppRole, templates, and rotation-focused walkthrough
make live-demo-cert   # cert-auth Agent variant (guided 5-step walkthrough)
```

These guided entrypoints frame the repo as one story with three audience-specific paths:

- the operator establishes trust and policy
- the machine consumes short-lived certificates through Vault Agent
- optional application/process demos show what rotation looks like in practice

## Traditional PKI demo

```bash
make demo
```

Covers:

- root and intermediate CA creation
- PKI role configuration
- leaf certificate issuance with SANs and IP SANs
- CSR-based signing where the private key stays outside Vault
- certificate inspection with OpenSSL
- certificate chain verification
- revocation and CRL inspection

```mermaid
flowchart LR
    Op([Operator]) --> Mount[Enable pki<br/>mount root + intermediate]
    Mount --> Role[Write web-server<br/>allowed_domains, TTLs]
    Role --> Issue[vault write pki/issue/web-server<br/>cert + key + chain]
    Role --> Sign[vault write pki/sign/web-server<br/>CSR signed, key stays out]
    Issue --> Inspect[openssl x509 -text<br/>SANs, IPs, validity]
    Sign --> Inspect
    Inspect --> Verify[openssl verify -CAfile<br/>chain to root]
    Verify --> Revoke[vault write pki/revoke<br/>+ vault read pki/crl]
    Revoke --> Done([Demo complete])

    style Op fill:#e1f5ff
    style Done fill:#d4edda
    style Sign fill:#fff3cd
```

## Vault Agent rotation demo (AppRole)

```bash
make agent-demo
```

Covers:

- AppRole-based Agent authentication
- least-privilege Agent policy scoped to certificate issuance plus token self-management
- template-driven certificate generation
- 30-second TTL demo certificates
- automatic certificate rotation
- local file rendering for cert, key, and CA chain
- full-file walkthrough of [vault-agent-config/agent.hcl](../vault-agent-config/agent.hcl) and [vault-agent-config/cert.tpl](../vault-agent-config/cert.tpl)

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator
    participant Agent as Vault Agent
    participant Vault
    participant Disk as vault-agent-output/
    participant App as Watcher / App

    Op->>Vault: enable approle + write pki-policy
    Op->>Vault: write role-id / secret-id<br/>(bootstrap files into agent container)
    Note over Agent,Vault: Auto-auth loop starts
    Agent->>Vault: auth/approle/login (role-id + secret-id)
    Vault-->>Agent: short-lived token (policy: pki-policy)
    loop every TTL (~30s)
        Agent->>Vault: pki/issue/web-server common_name=...
        Vault-->>Agent: new cert + key + chain
        Agent->>Disk: render cert.tpl -> cert.pem / key.pem / ca-chain.pem
        Disk-->>App: file change observed (mtime + new serial)
    end
    Op->>Op: watch-rotation.sh shows new serial each cycle
```

For the full step-by-step flow and container topology of this demo, see [../agent-demo-diagrams.md](../agent-demo-diagrams.md).

## Vault Agent cert-auth rotation demo

```bash
make setup-cert
make live-demo-cert
make watch-cert-rotation   # optional, in another terminal
```

`make live-demo-cert` is the audience-facing entrypoint. Under the hood it runs `preflight-cert`, then `agent-demo-cert`, then [`./agent-cert-demo.sh`](../agent-cert-demo.sh), which steps through the config snippets relevant to each phase with pauses between steps.

### Setup-cert flow (provisioning, runs once)

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator
    participant Compose as podman compose
    participant Vault
    participant OIDC as mock-oidc
    participant CI as simulate-ci-bootstrap.sh<br/>(pretends to be GitLab Runner)
    participant Disk as vault-agent-config/

    Op->>Compose: make setup-cert<br/>(setup-cert-demo.sh, stepped)
    Compose->>Vault: up -d vault (TLS listener :8200)
    Compose->>OIDC: up -d mock-oidc (:8080, RS256 signer)
    Op->>Vault: vault-init.sh<br/>pki root + intermediate + roles
    Op->>Vault: vault-init-cert.sh<br/>auth/cert + auth/jwt-gitlab + bound_claims
    Note over Vault: pki-bootstrap-policy = issue host-bootstrap-role only<br/>pki-policy-host    = issue host-role (agent rotation)

    CI->>OIDC: POST /token {project_path, ref, aud}
    OIDC-->>CI: signed JWT (5 min exp)
    CI->>Vault: auth/jwt-gitlab/login role=gitlab-host-bootstrap jwt=...
    Vault->>OIDC: GET /.well-known/jwks.json (verify signature)
    Vault-->>CI: scoped 5-min token (pki-bootstrap-policy)
    CI->>Vault: pki/issue/host-bootstrap-role<br/>common_name=host-01.trading.demo.internal
    Vault-->>CI: cert + key (24h TTL)
    CI->>Disk: write host.pem (cert+key bundle) + pki-ca.crt
    Note over Disk,CI: CI token revoked. No static credential on disk.
```

### Live-demo-cert flow (agent runtime, repeats forever)

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator
    participant Agent as vault-agent-cert<br/>(auto_auth method=cert)
    participant Vault
    participant Bundle as host.pem<br/>(cert + key)
    participant App as app.crt / app.key

    Note over Agent,Bundle: Step 1 — TLS client-cert auto-auth
    Agent->>Vault: auth/cert/login (mTLS with host.pem)
    Vault-->>Agent: token (policy: pki-policy-host, period 24h)

    Note over Agent,Vault: Step 2 — Bootstrap cert is what CI dropped

    Note over Agent,Bundle: Step 3 — Self-rotation template
    loop reload_period (every 5s)
        Agent->>Vault: pkiCert host-role ttl=30s (template)
        Vault-->>Agent: new cert + key
        Agent->>Bundle: atomic write host.pem<br/>(cert + key together)
        Agent->>Agent: reloader notices mtime change<br/>swaps in-memory cert
    end

    Note over Agent,Vault: Step 4 — enable_reauth_on_new_credentials
    Agent->>Vault: auth/cert/login again with new cert
    Vault-->>Agent: new token (new accessor = proof)

    Note over Agent,App: Step 5 — Restart survivability
    Op->>Agent: podman restart vault-agent-cert
    Agent->>Bundle: read host.pem from disk
    Agent->>Vault: auth/cert/login (no operator intervention)
    Vault-->>Agent: token
    Agent->>App: render app cert via web-server
```

### Negative path: provision-host-bad-claim

```mermaid
sequenceDiagram
    participant CI as simulate-ci-bootstrap-bad.sh
    participant OIDC as mock-oidc
    participant Vault

    CI->>OIDC: POST /token {project_path: attacker/sneaky}
    OIDC-->>CI: signed JWT (valid signature, wrong claim)
    CI->>Vault: auth/jwt-gitlab/login jwt=...
    Vault->>OIDC: GET /.well-known/jwks.json
    Vault-->>CI: 403 permission denied<br/>(bound_claims.project_path mismatch)
    Note over Vault: file audit log captures the rejection — the SIEM teaching moment
```

This path starts Vault with the development TLS listener because Vault's `auth/cert` method requires client certificates on the TLS connection. It runs alongside the other demos without changing them.

### What the 5-step walkthrough shows

1. **`auto_auth { method "cert" }`** — show the relevant block in [agent-cert.hcl](../vault-agent-config/agent-cert.hcl) and the `auth/cert/certs/host-role` trust anchor pinned to the PKI CA.
2. **Bootstrap host certificate** — show the `host-role` PKI role, re-run [`provision-host-cert.sh`](../provision-host-cert.sh) with a 60s TTL so rotation is visible within the demo window, restart `vault-agent-cert`, then inspect the issued `host.pem` (serial + token accessor captured as `INITIAL_*`).
3. **Self-rotation template** — show [host-bundle.tpl](../vault-agent-config/host-bundle.tpl) and the `template` stanza in `agent-cert.hcl`; narrate the 4-stage rotation (template renders new cert/key → Agent writes bundle → `reload_period` picks it up → Agent re-authenticates).
4. **Watch rotation** — poll for ~90s; on rotation the script prints the new serial and the new token accessor, proving the Agent re-issued its own host credential and re-authenticated.
5. **Restart survivability** — `podman restart vault-agent-cert` (or `docker` if the engine fallback is active), then verify the new accessor proves the Agent re-authenticated from the on-disk bundle without operator intervention.

### Bootstrap (CI simulation)

The initial host certificate is provisioned by [`simulate-ci-bootstrap.sh`](../simulate-ci-bootstrap.sh), which models a GitLab CI job:

1. asks the local mock OIDC issuer (`mock-oidc` container) for a signed `id_token`
2. exchanges that token at `auth/jwt-gitlab/login` for a short-lived Vault token scoped to `pki-bootstrap-policy`
3. uses that token to mint exactly one host certificate

**No Vault root token, no static client secret leaves the build pipeline.** After bootstrap, the Agent's own host cert is its only credential. Rotation is fully Agent-driven.

Useful follow-up targets:

```bash
make provision-host             # mint a fresh host.pem via the simulated CI
make provision-host-bad-claim   # negative test: a wrong-project JWT is denied
make show-bootstrap-cert        # inspect the current bootstrap cert
make mock-oidc-logs             # tail the mock OIDC issuer
```

The full bootstrap design lives in [gitlab-ci-provisioning-design.md](gitlab-ci-provisioning-design.md).

### Things this variant proves

- TLS client-certificate authentication with `auto_auth { method "cert" }`
- one-time provisioning of the initial host certificate, simulating CI enrolment
- agent-driven re-issuance of its own host credential via a template
- immediate re-authentication when the credential changes
- restart survivability: the Agent can re-authenticate from the certificate bundle on disk

## Process supervisor demo

```bash
make process-demo
```

Extends the Agent demo by showing how an application can react to certificate changes. The rotation watcher output highlights the fields most useful for a live audience:

- certificate subject
- `Valid from` and `Expires` timestamps
- certificate serial number
- matching certificate/key file modification times

```mermaid
flowchart LR
    Agent[Vault Agent<br/>auto_auth + template] -->|render| Cert[cert.pem / key.pem]
    Cert -->|exec hook| Restart[restart-app.sh<br/>or supervisor signal]
    Restart --> App[myapp.sh<br/>picks up new cert]
    Cert -->|fsnotify mtime| Watch[watch-rotation.sh]
    Watch --> Log[(stdout: subject,<br/>valid from/to,<br/>serial, mtime)]

    style Agent fill:#fff0f0
    style Cert fill:#f0fff0
    style App fill:#e1f5ff
    style Watch fill:#fff3cd
```

**Story beat:** new cert lands on disk → agent's `exec` (or external watcher) triggers the supervisor → app reloads with the new identity. The watcher panel proves the cert really changed (new serial + new mtime) instead of looking like a no-op.
