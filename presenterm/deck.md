---
options:
  implicit_slide_ends: false
---

<!-- jump_to_middle -->
<!-- alignment: center -->
<!-- no_footer -->
<!-- font_size: 2 -->

Vault Agent

<!-- new_lines: 2 -->
<!-- font_size: 1 -->

Automated PKI certificate rotation

<!-- new_lines: 4 -->

*Larry Song — HashiCorp Solutions Engineering*

<!-- end_slide -->

Certificates expire
===================

<!-- jump_to_middle -->
<!-- list_item_newlines: 2 -->

- **Every certificate has a lifetime** — a short TTL keeps the blast radius small
- **Expiry is a hard stop** — an expired certificate is an outage, not a warning
- **Manual rotation does not scale** — each certificate is a chore, and humans make errors

**Who rotates certificates at machine pace — without a human in the loop?**

<!-- speaker_note: The deck is about the pattern, not the number — the 30 second TTL is deliberately extreme so rotation is visible in a demo. -->

<!-- end_slide -->

Operator prepares, machine runs
===============================

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->

**Operator — once**

- PKI engine, root CA
- Issuance role `web-server`
- Least-privilege policy
- AppRole credentials

<!-- column: 1 -->

**Machine — always**

- Vault Agent
- AppRole auto-auth
- Template rendering
- Rotation before expiry

<!-- reset_layout -->

<!-- jump_to_middle -->

Vault issues → Agent renders → certificates rotate every 30 seconds

<!-- end_slide -->

The environment is running
==========================

Two containers, one job each — Vault issues, the Agent renders.

Self-healing: if the last run's reset stopped the containers (or a dev restart wiped PKI), this slide brings the environment back.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
# The previous run's "Cleanup / reset" slide stopped the containers — bring them back.
if ! curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
  echo "Vault not running — starting the demo environment (make start)..."
  make start >/dev/null
  for _ in $(seq 1 30); do
    curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1 && break
    sleep 1
  done
fi
# Dev-server storage is in-memory: a container restart wipes PKI, so re-apply the one-time setup if missing.
if ! vault secrets list 2>/dev/null | grep -q "^pki/"; then
  echo "PKI engine missing — applying one-time setup (make init + make setup-agent)..."
  make init >/dev/null 2>&1
  make setup-agent >/dev/null 2>&1
fi
echo "== containers =="
podman ps --format "table {{.Names}}\t{{.Status}}"
echo "== vault =="
vault status | grep -E "Sealed|Version"
```

<!-- speaker_note: Normally this slide just shows the running state. If the previous run ended on Cleanup / reset, the containers are stopped and PKI is wiped (dev server is in-memory) — the slide recovers automatically. -->

<!-- end_slide -->

PKI is prepared
===============

The operator did this once — engine, role, policy, AppRole. **AppRole** is *how the app proves who it is* · `web-server` is *which certificate profile it gets*.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
echo "== secrets engines =="
vault secrets list | grep -E "^Path|pki"
echo "== issuance role web-server =="
vault read pki/roles/web-server | grep -E "allowed_domains|max_ttl"
echo "== least-privilege policy =="
vault policy read pki-policy
echo "== approle vault-agent-role =="
vault read auth/approle/role/vault-agent-role | \
  grep -E "token_policies|token_ttl|token_max_ttl|token_no_default_policy"
```

<!-- end_slide -->

The Agent authenticates
=======================

AppRole login, automatic — the token carries only what rendering needs.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
T=$(podman exec vault-agent cat /tmp/vault-token)
echo "agent token is ${T:0:24}..."
vault token lookup -format=json "$T" \
  | jq -r '.data | "policies: \(.policies | join(", "))\nrenewable: \(.renewable)\nttl: \(.ttl)s"'
```

<!-- end_slide -->

Templates render
================

cert, key, and CA land on disk — with a 30-second TTL.

```bash +exec
[ -f .env ] || cd ..
podman exec vault-agent ls -la /vault/agent/
echo "== rendered certificate =="
openssl x509 -in vault-agent-output/app.crt -noout -subject -dates -serial
```

<!-- end_slide -->

Watch it rotate
===============

One 40-second window. The serial must change.

```bash +exec
[ -f .env ] || cd ..
S1=$(openssl x509 -in vault-agent-output/app.crt -noout -serial | cut -d= -f2)
echo "serial now:   $S1   ($(date +%H:%M:%S))"
echo "waiting 40s for a rotation cycle..."
sleep 40
S2=$(openssl x509 -in vault-agent-output/app.crt -noout -serial | cut -d= -f2)
echo "serial later: $S2   ($(date +%H:%M:%S))"
if [ "$S1" != "$S2" ]; then
  echo "ROTATED - the Agent re-issued automatically"
else
  echo "no change yet"
fi
```

<!-- speaker_note: The wait is intentional — one full rotation cycle. The Agent re-renders near the end of the 30 second TTL. -->

<!-- end_slide -->

<!-- jump_to_middle -->
<!-- alignment: center -->

**What we proved**

1. Certificates are short-lived by design — a 30-second TTL
2. The Agent authenticates via AppRole with a least-privilege policy
3. Templates render cert, key, and CA — no application changes
4. Rotation is automatic and observable — the serial changes every cycle

<!-- end_slide -->

Cleanup / reset
===============

Tear down the demo environment and restore a clean state for the next run.

```bash +exec
# stops containers and clears generated demo artifacts
[ -f Makefile ] || cd ..
make reset-demo
```

<!-- speaker_note: Reset stops the containers and clears generated files. PKI data is also lost (dev server is in-memory). The next make deck-agent run self-heals on its first slide, so no manual setup is needed. -->

<!-- end_slide -->

Shutdown — stop the whole demo system
=====================================

End of the session: stop every container this repo started — the migrate pair plus the default Vault stack.

```bash +exec
[ -f Makefile ] || cd ..
make stop-migrate || true
make stop || true
echo "== remaining demo containers =="
podman ps --format "{{.Names}}" | grep -E "vault" || echo "none — everything is stopped"
```

<!-- speaker_note: make stop covers the default stack and the cert-auth variant. Run this only when the demo session is fully over — the first slide of the next run rebuilds the environment from scratch. -->
