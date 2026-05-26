#!/bin/bash
# simulate-ci-bootstrap-bad.sh — same flow as simulate-ci-bootstrap.sh but with
# a project_path that violates the gitlab-host-bootstrap role's bound_claims.
# Expected outcome: Vault rejects the JWT, the audit log shows the rejection,
# and NO certificate is written to disk.

set -euo pipefail

export PROJECT_PATH="${PROJECT_PATH:-evil-corp/totally-legit/runner}"
export REF="${REF:-main}"

# Re-use the happy-path script; it will exit non-zero on rejection. We want
# the rejection to be visible to the audience, so flip the trap.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Negative test: a JWT from an unauthorized project should be rejected ==="
echo "  project_path = ${PROJECT_PATH}  (does NOT match acme/trading-platform/*)"
echo

set +e
"${SCRIPT_DIR}/simulate-ci-bootstrap.sh"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
    echo
    echo "FAIL: bootstrap should have been rejected but succeeded."
    exit 1
fi

echo
echo "SUCCESS: Vault denied the JWT (exit ${rc}). The audit log above shows the rejected /v1/auth/jwt-gitlab/login call."
echo "No host.pem was written — the bootstrap could not produce a credential."
exit 0
