---
options:
  implicit_slide_ends: false
---

<!-- jump_to_middle -->
<!-- alignment: center -->
<!-- no_footer -->
<!-- font_size: 2 -->

Vault PKI

<!-- new_lines: 2 -->
<!-- font_size: 1 -->

Certificates by API — create, then delete

<!-- new_lines: 4 -->

*Larry Song — HashiCorp Solutions Engineering*

<!-- end_slide -->

The use case
============

<!-- list_item_newlines: 2 -->

- Service accounts live in an identity system — creation, validation, deletion
- The application's **only** Vault interaction is **certificate generation and deletion**
- Lifecycle is bound to the service account:

  *create → issue a certificate · delete → revoke the certificate*

**Two API calls. No UI. No humans in the loop.**

<!-- speaker_note: Mirrors how the ASX identity team's application integrates — the identity provider (ForgeRock) owns the service-account lifecycle, and custom code calls Vault only when a certificate must be issued or revoked. -->

<!-- end_slide -->

What we will show
=================

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->

**Once — operator prepares**

- PKI engine, root CA
- Issuance role `web-server`
- AppRole credentials
- Least-privilege policy

<!-- column: 1 -->

**Every call — application**

1. Log in via AppRole (API)
2. POST `pki/issue/web-server` → certificate
3. POST `pki/revoke` → certificate dies

<!-- reset_layout -->

<!-- jump_to_middle -->

Create and delete are just API calls

<!-- end_slide -->

The environment is running
==========================

Vault is up, PKI is mounted, AppRole is configured.

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

One-time setup — engine, role, policy, AppRole. **AppRole** is *how the app proves who it is* · `web-server` is *which certificate profile it gets*.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
echo "== secrets engines =="
vault secrets list | grep -E "^Path|pki"
echo "== issuance role web-server =="
vault read pki/roles/web-server | grep -E "allowed_domains|max_ttl"
echo "== the application's policy — issue AND revoke =="
vault policy read pki-policy
echo "== approle vault-agent-role =="
vault read auth/approle/role/vault-agent-role | \
  grep -E "token_policies|token_ttl|token_max_ttl|token_no_default_policy"
```

<!-- end_slide -->

The application authenticates
=============================

AppRole login — the exact call the app makes before any certificate work.

If a demo reset cleared the credentials, this re-creates them first (the operator's one-time step).

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
# One-time operator step — re-create AppRole credentials if a reset cleared them
if [ ! -s vault-agent-config/secret-id ]; then
  vault write auth/approle/role/vault-agent-role \
    token_policies=pki-policy token_no_default_policy=true \
    token_ttl=1h token_max_ttl=4h >/dev/null
  # Retry: Podman virtiofs can intermittently drop a freshly written file from the host view.
  for _ in 1 2 3; do
    vault read -field=role_id auth/approle/role/vault-agent-role/role-id \
      > vault-agent-config/role-id
    vault write -field=secret_id -f auth/approle/role/vault-agent-role/secret-id \
      > vault-agent-config/secret-id
    chmod 644 vault-agent-config/role-id vault-agent-config/secret-id
    [ -s vault-agent-config/secret-id ] && break
    sleep 1
  done
fi
ROLE_ID=$(cat vault-agent-config/role-id)
SECRET_ID=$(cat vault-agent-config/secret-id)
curl -s "$VAULT_ADDR/v1/auth/approle/login" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
  | jq -r '.auth.client_token' > /tmp/asx-token
TOKEN=$(cat /tmp/asx-token)
echo "client token: ${TOKEN:0:24}..."
curl -s -H "X-Vault-Token: $TOKEN" "$VAULT_ADDR/v1/auth/token/lookup-self" \
  | jq -r '.data | "policies: \(.policies | join(", "))\nttl:       \(.ttl)s"'
```

<!-- speaker_note: This is what the custom Java library does — POST role_id + secret_id to /v1/auth/approle/login, then use the returned client token. The token is saved to /tmp/asx-token for the following slides. -->

<!-- end_slide -->

Create — issue a certificate
============================

One API call, one certificate — the app gets cert, key, and CA chain.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
TOKEN=$(cat /tmp/asx-token)
curl -s -X POST -H "X-Vault-Token: $TOKEN" \
  "$VAULT_ADDR/v1/pki/issue/web-server" \
  -d '{"common_name":"api-demo.example.com","ttl":"2m"}' \
  | tee /tmp/asx-cert.json | jq -r '
    "serial_number: \(.data.serial_number)",
    "expiry:        \(.data.expiration | todateiso8601)"'
echo "== who issued it =="
jq -r '.data.certificate' /tmp/asx-cert.json \
  | openssl x509 -noout -subject -issuer -dates
```

<!-- speaker_note: Short TTL on purpose — certificates are short-lived by design, and a 2-minute TTL makes the lifecycle visible. -->

<!-- end_slide -->

The app writes the files it needs
=================================

```bash +exec
[ -f .env ] || cd ..
jq -r '.data.certificate' /tmp/asx-cert.json > /tmp/api-demo.crt
jq -r '.data.private_key' /tmp/asx-cert.json > /tmp/api-demo.key
jq -r '.data.issuing_ca'  /tmp/asx-cert.json > /tmp/api-demo.ca
chmod 600 /tmp/api-demo.key
openssl x509 -in /tmp/api-demo.crt -noout -subject -dates -serial
echo "== the public key lives inside the certificate =="
openssl x509 -in /tmp/api-demo.crt -noout -pubkey
echo "== and it matches the private key =="
CERT_PUB=$(openssl x509 -in /tmp/api-demo.crt -noout -pubkey \
  | openssl pkey -pubin -outform der | openssl sha256)
KEY_PUB=$(openssl pkey -in /tmp/api-demo.key -pubout -outform der \
  | openssl sha256)
[ "$CERT_PUB" = "$KEY_PUB" ] && echo "MATCH — one key pair" || echo "MISMATCH"
echo "== trusted by the CA =="
openssl verify -CAfile /tmp/api-demo.ca /tmp/api-demo.crt
```

<!-- speaker_note: In the ASX integration the Java app receives certificate, private_key, and issuing_ca, and writes them where the workload expects them. -->

<!-- end_slide -->

Delete — revoke
===============

The service account is deleted, so the certificate must die too.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
TOKEN=$(cat /tmp/asx-token)
SERIAL=$(jq -r '.data.serial_number' /tmp/asx-cert.json)
echo "revoking serial $SERIAL"
curl -s -X POST -H "X-Vault-Token: $TOKEN" \
  "$VAULT_ADDR/v1/pki/revoke" \
  -d "{\"serial_number\":\"$SERIAL\"}" \
  | jq -r '.data | "revoked at \(.revocation_time)  (\(.state))"'
echo "$SERIAL" > /tmp/asx-revoked-serial
```

<!-- end_slide -->

Proof — the certificate is dead
===============================

Revocation is immediate and observable: the serial lands in the CRL.

```bash +exec
[ -f .env ] || cd ..
set -a; . ./.env; set +a
TOKEN=$(cat /tmp/asx-token)
# Read the serial the Delete slide actually revoked (Create re-runs overwrite /tmp/asx-cert.json)
if [ ! -s /tmp/asx-revoked-serial ]; then
  echo "Nothing revoked yet — run the 'Delete — revoke' slide first."
  exit 0
fi
SERIAL=$(cat /tmp/asx-revoked-serial)
echo "== certificate status =="
curl -s -H "X-Vault-Token: $TOKEN" "$VAULT_ADDR/v1/pki/cert/$SERIAL" \
  | jq -r '.data | "revoked:         \(.revocation_time != 0)\nrevocation_time:  \(.revocation_time)"'
echo "== is $SERIAL in the CRL? =="
CRL_HEX=$(curl -s -H "X-Vault-Token: $TOKEN" "$VAULT_ADDR/v1/pki/crl/pem" \
  | openssl crl -noout -text | grep -i "serial number" \
  | sed -E 's/.*Serial Number:[[:space:]]*//; s/://g; s/[^0-9A-Fa-f]//g' | tr 'a-f' 'A-F')
SERIAL_HEX=$(echo "$SERIAL" | tr -d ':' | tr 'a-f' 'A-F')
case "$CRL_HEX" in
  *"$SERIAL_HEX"*) echo "yes — the revoked serial is listed in the CRL" ;;
  *) echo "not found in the CRL (yet)" ;;
esac
```

<!-- end_slide -->

<!-- jump_to_middle -->
<!-- alignment: center -->

**What we proved**

1. The application's PKI interaction is two API calls — issue and revoke
2. AppRole authenticates the application — no humans, no UI
3. Create and delete are bound to the service-account lifecycle
4. Revocation is immediate and observable — the serial lands in the CRL

<!-- end_slide -->

Cleanup / reset
===============

Tear down the demo environment and restore a clean state for the next run.

```bash +exec
# stops containers and clears generated demo artifacts
[ -f Makefile ] || cd ..
make reset-demo
```

<!-- speaker_note: Reset stops the containers and clears generated files. PKI data is also lost (dev server is in-memory). The next make deck-api run self-heals on its first slide, so no manual setup is needed. -->
