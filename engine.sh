#!/bin/bash
# engine.sh — container engine abstraction for the PKI demo.
#
# Sources a single definition of the container engine so every demo script,
# the Makefile, and compose invocations use Podman (Podman Desktop / podman
# machine) by default and transparently fall back to Docker Desktop when
# Podman is not installed. The demo's compose files are standard Compose
# spec, so they run unchanged under either engine.
#
# Usage:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/engine.sh"
#   "$CONTAINER_ENGINE" exec vault vault version
#   "$COMPOSE" up -d
#
# Runtime override:  CONTAINER_ENGINE=docker ./demo-preflight.sh

# Prefer Podman (Podman Desktop / podman machine); fall back to Docker.
if command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
else
    CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"
fi

# `podman compose` delegates to an external provider (podman-compose, installed
# alongside Podman Desktop). Silence its "executing external compose provider"
# banner so demo output stays clean. Harmless no-op under Docker.
if [ "$CONTAINER_ENGINE" = "podman" ]; then
    export PODMAN_COMPOSE_WARNING_LOGS=false
fi

# Compose command prefix (e.g. "podman compose" or "docker compose").
COMPOSE="${COMPOSE:-$CONTAINER_ENGINE compose}"

# Ensure demo bind-mount directories exist with permissions the containers can
# write to. Podman machine (libkrun virtiofs) enforces real host ownership, so
# the vault image's unprivileged user (uid 100, dropped by the entrypoint) needs
# world-writable dirs where Docker Desktop tolerated 755/root remapping.
demo_ensure_dirs() {
    for dir in vault-agent-config vault-agent-output vault-agent-output-cert vault-tls; do
        mkdir -p "$dir"
        chmod 777 "$dir"
    done
}

export CONTAINER_ENGINE
export COMPOSE
