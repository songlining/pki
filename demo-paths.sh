#!/bin/bash

set -euo pipefail

MODE=""
LAUNCH=false

for arg in "$@"; do
    case "$arg" in
        live|workshop|operator)
            MODE="$arg"
            ;;
        --launch)
            LAUNCH=true
            ;;
        *)
            echo "Usage: $0 {live|workshop|operator} [--launch]"
            exit 1
            ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "Usage: $0 {live|workshop|operator} [--launch]"
    exit 1
fi

./demo-preflight.sh
echo

case "$MODE" in
    live)
        echo "=== Live Demo Track ==="
        echo "Story: operator establishes trust manually, then the machine takes over."
        echo
        echo "Act 1: Operator trust path"
        echo "  - Run: make demo"
        echo "  - Covers root/intermediate CA setup, issuance, CSR signing, and revocation"
        echo
        echo "Act 2: Machine automation path"
        echo "  - Run next: make agent-demo"
        echo "  - Shows Vault Agent rendering and rotating short-lived certs"
        echo
        echo "Optional Act 3: Application behavior"
        echo "  - Run next: make process-demo or make watch-rotation"
        if [ "$LAUNCH" = true ]; then
            echo
            echo "Launching Act 1 now..."
            exec ./pki-demo.sh
        fi
        ;;
    workshop)
        echo "=== Workshop Track ==="
        echo "Goal: let a self-serve learner touch each concept in order."
        echo
        echo "Recommended sequence:"
        echo "  1. make demo"
        echo "  2. make agent-demo"
        echo "  3. make watch-rotation"
        echo "  4. make process-demo"
        echo
        echo "Teaching frame:"
        echo "  - Operator provisions trust and issuance policy"
        echo "  - Application teams can keep private keys outside Vault via CSR signing"
        echo "  - Vault Agent handles machine authentication and certificate rotation"
        ;;
    operator)
        echo "=== Operator Track ==="
        echo "Goal: focus on AppRole, least-privilege policy, templates, and runtime rotation."
        echo
        echo "Start here:"
        echo "  - make agent-demo"
        echo
        echo "Then deepen the story with:"
        echo "  - make watch-rotation"
        echo "  - make process-demo"
        echo
        echo "Operating model:"
        echo "  - Operator owns PKI, policy, bootstrap, and guardrails"
        echo "  - Vault Agent is the machine actor that authenticates, renders, and rotates"
        if [ "$LAUNCH" = true ]; then
            echo
            echo "Launching the operator path now..."
            exec ./agent-pki-demo.sh
        fi
        ;;
esac
