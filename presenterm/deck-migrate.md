---
options:
  implicit_slide_ends: false
---

<!-- jump_to_middle -->
<!-- alignment: center -->
<!-- no_footer -->
<!-- font_size: 2 -->

One Certificate, Two Vaults

<!-- new_lines: 2 -->
<!-- font_size: 1 -->

Certificate migration without re-issuance

<!-- new_lines: 4 -->

*Larry Song — HashiCorp Solutions Engineering*

<!-- end_slide -->

What we will prove
==================

<!-- jump_to_middle -->
<!-- list_item_newlines: 2 -->

1. A client certificate is anchored to its **CA** — not to any one Vault server
2. The **same, unchanged certificate** authenticates into two completely independent Vaults
3. Migration is **one registration** — no re-issuance, no client change, zero downtime

<!-- speaker_note: Framing for the room. This is the mechanism behind Vault migrations, DR failover, and multi-cluster estates keeping X.509 clients online. -->

<!-- end_slide -->

Two independent Vault estates
=============================

vault-old (:8210) and vault-new (:8220) share nothing — no storage, no PKI, no auth. Two strangers on a network. This slide starts them fresh.

```bash +exec
[ -f Makefile ] || cd ..
export VAULT_SKIP_VERIFY=true
podman compose -f docker-compose.migrate.yml down --remove-orphans >/dev/null 2>&1 || true
podman compose -f docker-compose.migrate.yml up -d >/dev/null
for port in 8210 8220; do
  for _ in $(seq 1 30); do
    curl -sk https://localhost:$port/v1/sys/health >/dev/null 2>&1 && break
    sleep 1
  done
done
echo "== vault-old =="
curl -sk https://localhost:8210/v1/sys/health | jq -r '"version \(.version)  sealed \(.sealed)"'
echo "== vault-new =="
curl -sk https://localhost:8220/v1/sys/health | jq -r '"version \(.version)  sealed \(.sealed)"'
echo "== containers =="
podman ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|vault-old|vault-new"
```

<!-- end_slide -->

The trust anchor moves, not the certificate
===========================================

```text
┌────────────────────────┐        ┌────────────────────────┐
│ vault-old      :8210   │        │ vault-new      :8220   │
│                        │        │                        │
│ pki/   owns root CA    │        │ auth/cert              │
│ auth/cert              │        │ trusts nobody yet      │
│   trusts its own CA    │        │                        │
└───────────┬────────────┘        └───────────▲────────────┘
            │                                 │
            │ 4. register the CA ─────────────┘  the migration
            │
            │ 1. issue leaf cert
            ▼
        client.pem  (never changes)
            │
            │ 2. login vault-old  ── OK
            │ 3. login vault-new  ── REJECTED  before
            │ 5. login vault-new  ── OK  same cert, after
```

<!-- speaker_note: Walk the numbers in order. The only thing that ever moves is the CA registration, step 4. The certificate file is untouched for the entire demo. -->

<!-- end_slide -->

vault-old builds the PKI estate
===============================

The one-time operator setup, all on vault-old — engine, root CA, role, cert auth. vault-new is never touched.

```bash +exec
[ -f Makefile ] || cd ..
mkdir -p migrate-work; . ./.env
export VAULT_SKIP_VERIFY=true
O=https://localhost:8210
V() { VAULT_ADDR=$O VAULT_TOKEN=$VAULT_TOKEN vault "$@"; }
echo "== root CA =="
V secrets enable pki >/dev/null
V write pki/root/generate/internal \
  common_name=old-vault.migrate.demo.internal ttl=87600h >/dev/null 2>&1
V read -field=certificate pki/cert/ca > migrate-work/old-ca.crt
openssl x509 -in migrate-work/old-ca.crt -noout -subject -dates
echo "== client-issuance role =="
V write pki/roles/migrate-client allowed_domains=migrate.demo.internal \
  allow_subdomains=true client_flag=true server_flag=false ttl=24h >/dev/null
echo "== cert auth trusts its own CA =="
V auth enable cert >/dev/null
V write auth/cert/certs/migrate-role certificate=@migrate-work/old-ca.crt \
  allowed_common_names="*.migrate.demo.internal" token_policies=migrate-policy \
  token_no_default_policy=true >/dev/null
echo "== policy + proof KV entry =="
echo 'path "secret/data/migrate-demo" { capabilities = ["read"] }' \
  | V policy write migrate-policy -
V kv put secret/migrate-demo message="hello from vault-old" >/dev/null
```

<!-- end_slide -->

Issue the leaf certificate
==========================

The client's credential for the whole demo — issued once on vault-old, never re-issued.

```bash +exec
[ -f Makefile ] || cd ..
set -a; . ./.env; set +a
export VAULT_SKIP_VERIFY=true
V() { VAULT_ADDR=https://localhost:8210 VAULT_TOKEN=$VAULT_TOKEN vault "$@"; }
J=$(V write -format=json pki/issue/migrate-client \
     common_name=app-01.migrate.demo.internal ttl=24h)
jq -r .data.certificate <<<"$J" > /tmp/mc
jq -r .data.private_key  <<<"$J" > /tmp/mk
cat /tmp/mc /tmp/mk > migrate-work/client.pem && rm -f /tmp/mc /tmp/mk
chmod 600 migrate-work/client.pem
echo "== the issued certificate =="
openssl x509 -in migrate-work/client.pem -noout -subject -issuer -dates
openssl x509 -in migrate-work/client.pem -noout -fingerprint -sha256
```

<!-- speaker_note: Point at the issuer line — signed by old-vault.migrate.demo.internal. This fingerprint is the one to remember for the final slide. -->

<!-- end_slide -->

Claim — the cert authenticates into vault-old
=============================================

The client presents its certificate in the TLS handshake; Vault matches it against the registered CA and returns a token carrying only the migrate policy.

```bash +exec
[ -f Makefile ] || cd ..
export VAULT_SKIP_VERIFY=true
J=$(curl -sk --cert migrate-work/client.pem --key migrate-work/client.pem \
      -d '{"name":"migrate-role"}' https://localhost:8210/v1/auth/cert/login)
echo "$J" | jq '{policies: .auth.policies, ttl_seconds: .auth.lease_duration,
  renewable: .auth.renewable}'
T=$(jq -r .auth.client_token <<<"$J")
curl -sk -H "X-Vault-Token: $T" https://localhost:8210/v1/secret/data/migrate-demo \
  | jq -r '.data.data.message | "proof read: \(.)"'
```

<!-- speaker_note: The proof read at the end shows the client can actually use the token, not just obtain one. -->

<!-- end_slide -->

Negative control — rejected by vault-new
========================================

Same file, same private key, same handshake. vault-new has never heard of this CA — right now the certificate is worthless there.

```bash +exec
[ -f Makefile ] || cd ..
export VAULT_SKIP_VERIFY=true
R=$(curl -sk --cert migrate-work/client.pem --key migrate-work/client.pem \
      -d '{"name":"migrate-role"}' https://localhost:8220/v1/auth/cert/login || true)
jq -r '.errors // ["(empty response)"] | join("; ")' <<<"$R" | sed 's/^/    /'
```

<!-- end_slide -->

The migration — one registration
===============================

The entire migration. The same trust-anchor file exported earlier — registered in vault-new. No re-issuance, no client change, no downtime.

```bash +exec
[ -f Makefile ] || cd ..
set -a; . ./.env; set +a
export VAULT_SKIP_VERIFY=true
N=https://localhost:8220
V() { VAULT_ADDR=$N VAULT_TOKEN=$VAULT_TOKEN vault "$@"; }
V auth enable cert >/dev/null
V write auth/cert/certs/migrate-role certificate=@migrate-work/old-ca.crt \
  allowed_common_names="*.migrate.demo.internal" token_policies=migrate-policy \
  token_no_default_policy=true >/dev/null
echo "vault-new now trusts the SAME CA as vault-old"
echo 'path "secret/data/migrate-demo" { capabilities = ["read"] }' \
  | V policy write migrate-policy -
V kv put secret/migrate-demo message="hello from vault-new" >/dev/null
V read auth/cert/certs/migrate-role \
  | grep -E "allowed_common_names|token_policies|allowed_extensions"
```

<!-- end_slide -->

Claim — the same cert, unchanged, into vault-new
================================================

Same file, same key, same fingerprint — different server.

```bash +exec
[ -f Makefile ] || cd ..
export VAULT_SKIP_VERIFY=true
J=$(curl -sk --cert migrate-work/client.pem --key migrate-work/client.pem \
      -d '{"name":"migrate-role"}' https://localhost:8220/v1/auth/cert/login)
echo "$J" | jq '{policies: .auth.policies, ttl_seconds: .auth.lease_duration,
  renewable: .auth.renewable}'
T=$(jq -r .auth.client_token <<<"$J")
curl -sk -H "X-Vault-Token: $T" https://localhost:8220/v1/secret/data/migrate-demo \
  | jq -r '.data.data.message | "proof read: \(.)"'
echo "== fingerprint (unchanged since issuance) =="
openssl x509 -in migrate-work/client.pem -noout -fingerprint -sha256
```

<!-- speaker_note: Compare with the fingerprint on the issuance slide — identical. The certificate never changed; only the trust anchor moved. -->

<!-- end_slide -->

<!-- jump_to_middle -->
<!-- alignment: center -->

**What we proved**

1. Certificate auth is anchored in the **CA**, not the server
2. Registering the issuing CA made every signed certificate valid there instantly — one command
3. The certificate never changed — same fingerprint, same key, zero re-issuance

This is how Vault migrations, DR failovers, and multi-cluster
estates keep X.509 clients online.

<!-- end_slide -->

Cleanup / reset
===============

Tear down only the migrate project — the default Vault stack is untouched.

```bash +exec
[ -f Makefile ] || cd ..
podman compose -f docker-compose.migrate.yml down --remove-orphans || true
podman ps --format "table {{.Names}}\t{{.Status}}"
```

<!-- speaker_note: Skip this slide if the audience wants to poke at the two Vaults afterwards. The next run self-heals — the first slide tears down and restarts fresh. -->

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

<!-- speaker_note: make stop covers the default stack and the cert-auth variant. Run this only when the demo session is fully over — the first slide of the next run rebuilds the migrate pair from scratch. -->
