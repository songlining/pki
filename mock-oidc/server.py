"""Mock OIDC provider — simulates GitLab CI's CI_JOB_JWT_V2 signer.

NOT FOR PRODUCTION USE. Purpose:
- Sign RS256 JWTs with claims that mimic GitLab's id_tokens, so Vault's JWT
  auth method can verify them against the JWKS we publish.
- Used only by the cert-auth bootstrap demo to show "no static credential in CI".
"""

import json
import os
import time
import uuid
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from flask import Flask, jsonify, request
from jose import jwk, jwt

ISSUER_URL = os.environ.get("ISSUER_URL", "http://mock-oidc:8080")
KEYS_DIR = Path(os.environ.get("KEYS_DIR", "/app/keys"))
SIGNING_KEY_PATH = KEYS_DIR / "signing-key.pem"
KEY_ID = "mock-oidc-key-1"

app = Flask(__name__)


def _ensure_signing_key() -> bytes:
    """Generate the RSA signing key on first start, persist to volume."""
    KEYS_DIR.mkdir(parents=True, exist_ok=True)
    if not SIGNING_KEY_PATH.exists():
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        SIGNING_KEY_PATH.write_bytes(pem)
        print(f"[mock-oidc] generated new signing key at {SIGNING_KEY_PATH}")
    return SIGNING_KEY_PATH.read_bytes()


SIGNING_KEY_PEM = _ensure_signing_key()


def _public_jwks() -> dict:
    """Return the public half of the signing key as a JWKS document."""
    key = serialization.load_pem_private_key(SIGNING_KEY_PEM, password=None)
    public_pem = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    jwk_dict = jwk.construct(public_pem, algorithm="RS256").to_dict()
    jwk_dict["kid"] = KEY_ID
    jwk_dict["use"] = "sig"
    jwk_dict["alg"] = "RS256"
    return {"keys": [jwk_dict]}


@app.get("/.well-known/openid-configuration")
def discovery():
    return jsonify(
        {
            "issuer": ISSUER_URL,
            "jwks_uri": f"{ISSUER_URL}/.well-known/jwks.json",
            "id_token_signing_alg_values_supported": ["RS256"],
            "response_types_supported": ["id_token"],
            "subject_types_supported": ["public"],
        }
    )


@app.get("/.well-known/jwks.json")
def jwks():
    return jsonify(_public_jwks())


@app.post("/token")
def mint_token():
    """Sign a JWT shaped like a GitLab CI_JOB_JWT_V2.

    Required body fields: project_path, ref.
    Optional: aud (default vault-pki-bootstrap), ref_type, ref_protected,
              ttl_seconds (default 300).
    """
    body = request.get_json(force=True, silent=True) or {}
    if "project_path" not in body or "ref" not in body:
        return jsonify({"error": "project_path and ref are required"}), 400

    now = int(time.time())
    ttl = int(body.get("ttl_seconds", 300))
    claims = {
        "iss": ISSUER_URL,
        "aud": body.get("aud", "vault-pki-bootstrap"),
        "sub": f"project_path:{body['project_path']}:ref_type:"
        f"{body.get('ref_type', 'branch')}:ref:{body['ref']}",
        "jti": str(uuid.uuid4()),
        "iat": now,
        "nbf": now,
        "exp": now + ttl,
        "project_path": body["project_path"],
        "ref": body["ref"],
        "ref_type": body.get("ref_type", "branch"),
        "ref_protected": str(body.get("ref_protected", "true")).lower(),
        "namespace_path": body["project_path"].split("/", 1)[0],
    }

    token = jwt.encode(
        claims,
        SIGNING_KEY_PEM,
        algorithm="RS256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )
    return jsonify({"token": token, "claims": claims})


@app.get("/healthz")
def healthz():
    return jsonify({"ok": True})


if __name__ == "__main__":
    print(f"[mock-oidc] issuer = {ISSUER_URL}")
    print(f"[mock-oidc] keys dir = {KEYS_DIR}")
    app.run(host="0.0.0.0", port=8080)
