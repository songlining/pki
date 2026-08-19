.PHONY: help start stop stop-cert stop-default stop-migrate init demo clean setup status agent-demo setup-agent watch-rotation process-demo preflight live-demo workshop-demo operator-demo reset-demo setup-cert preflight-cert agent-demo-cert watch-cert-rotation live-demo-cert provision-host provision-host-bad-claim show-bootstrap-cert mock-oidc-logs cert-migrate deck-agent deck-api deck-migrate

# Container engine: Podman Desktop (podman) by default, Docker as fallback.
CONTAINER_ENGINE ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)

# podman prints an "executing external compose provider" banner on stderr;
# silence it so demo output stays clean. Empty under Docker (no-op).
COMPOSE_QUIET := $(shell [ "$(CONTAINER_ENGINE)" = podman ] && printf 'PODMAN_COMPOSE_WARNING_LOGS=false ')

COMPOSE_FILES := -f docker-compose.yml

COMPOSE := $(COMPOSE_QUIET)$(CONTAINER_ENGINE) compose $(COMPOSE_FILES)
CERT_COMPOSE := $(COMPOSE_QUIET)$(CONTAINER_ENGINE) compose $(COMPOSE_FILES) -f docker-compose.cert.yml

# Fully isolated compose project (explicit `name: vault-migrate` inside the
# file) — separate containers, network, and ports from every other scenario.
MIGRATE_COMPOSE := $(COMPOSE_QUIET)$(CONTAINER_ENGINE) compose -f docker-compose.migrate.yml

deck-agent: ## Run the presenterm slide deck focused on Vault Agent cert rotation (-x enables live code execution)
	@command -v presenterm >/dev/null 2>&1 || { echo "presenterm not installed: brew install presenterm"; exit 1; }
	@presenterm -x presenterm/deck.md

deck-api: ## Run the presenterm slide deck on API-driven cert issue/revoke (-x enables live code execution)
	@command -v presenterm >/dev/null 2>&1 || { echo "presenterm not installed: brew install presenterm"; exit 1; }
	@presenterm -x presenterm/deck-api.md

deck-migrate: ## Run the presenterm slide deck on two-Vault cert migration (-x enables live code execution)
	@command -v presenterm >/dev/null 2>&1 || { echo "presenterm not installed: brew install presenterm"; exit 1; }
	@presenterm -x presenterm/deck-migrate.md

help: ## Show this help message
	@echo "HashiCorp Vault PKI Demo"
	@echo "========================"
	@echo ""
	@echo "Edition: Vault Community Edition"
	@echo ""
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

start: ## Start demo containers
	@echo "Starting Vault demo containers..."
	@mkdir -p vault-agent-config vault-agent-output vault-agent-output-cert vault-tls && chmod 777 vault-agent-config vault-agent-output vault-agent-output-cert vault-tls
	$(COMPOSE) up -d
	@echo "Container started!"

stop: ## Stop all demo containers, including the cert-auth variant
	@echo "Stopping all Vault demo containers..."
	$(CERT_COMPOSE) down --remove-orphans
	@echo "All demo containers stopped!"

stop-cert: ## Stop only the cert-auth demo overlay containers
	@echo "Stopping cert-auth demo containers..."
	$(CERT_COMPOSE) stop vault-agent-cert
	$(CERT_COMPOSE) rm -f vault-agent-cert
	@echo "Cert-auth containers stopped!"

stop-default: ## Stop only the default demo containers
	@echo "Stopping default Vault demo containers..."
	$(COMPOSE) down
	@echo "Container stopped!"

stop-migrate: ## Stop only the cert-migrate demo containers (vault-old + vault-new)
	@echo "Stopping cert-migrate demo containers..."
	$(MIGRATE_COMPOSE) down --remove-orphans
	@echo "Cert-migrate containers stopped!"

init: ## Initialize Vault and PKI (run after start)
	@echo "Initializing Vault and PKI..."
	@sleep 3
	./vault-init.sh

demo: ## Run the interactive PKI certificate demo
	@echo "Starting PKI certificate demo..."
	./pki-demo.sh

agent-demo: ## Run Vault Agent PKI demo with 30s rotation
	@echo "Starting Vault Agent PKI demo with 30-second rotation..."
	./agent-pki-demo.sh

setup-agent: ## Setup Vault Agent credentials
	@echo "Setting up Vault Agent credentials..."
	./setup-agent-credentials.sh

preflight: ## Check whether the demo is ready to present
	./demo-preflight.sh

preflight-cert: ## Check whether the cert-auth demo variant is ready
	./demo-preflight.sh cert

live-demo: preflight ## Guided entrypoint for a short live presentation
	./demo-paths.sh live --launch

live-demo-cert: preflight-cert agent-demo-cert ## Guided entrypoint for the cert-auth presentation path

workshop-demo: preflight ## Guided entrypoint for a hands-on workshop path
	./demo-paths.sh workshop

operator-demo: preflight ## Guided entrypoint for the operator and automation path
	./demo-paths.sh operator --launch

watch-rotation: ## Watch certificate rotation in real-time
	@echo "Starting certificate rotation monitor..."
	./watch-rotation.sh

watch-cert-rotation: preflight-cert ## Watch the agent's own cert-auth credential rotate
	@echo "Starting cert-auth credential rotation monitor..."
	./watch-cert-rotation.sh

reset-demo: ## Safely reset known generated demo state
	@echo "Resetting known demo state..."
	./reset-demo-state.sh

clean: reset-demo ## Alias for safe demo reset

setup: start init setup-agent ## Complete setup (start + init + agent).
	@echo "Setup complete!"
	@echo "Choose your path:"
	@echo "  make live-demo"
	@echo "  make workshop-demo"
	@echo "  make operator-demo"
	@echo ""
	@echo "Or for the cert-auth (TLS client-cert) variant:"
	@echo "  make setup-cert       # one-time setup of the cert-auth stack"
	@echo "  make live-demo-cert   # guided cert-auth walkthrough"

setup-cert: ## Setup the TLS cert-auth Vault Agent variant (stepped, narrated)
	@COMPOSE_FILES="$(COMPOSE_FILES) -f docker-compose.cert.yml" \
		VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=myroot \
		./setup-cert-demo.sh

provision-host: ## Re-run the simulated GitLab CI bootstrap to mint a fresh host.pem
	VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true ./simulate-ci-bootstrap.sh

provision-host-bad-claim: ## Negative test: prove a wrong-project JWT gets rejected
	VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true ./simulate-ci-bootstrap-bad.sh

show-bootstrap-cert: ## Inspect the current bootstrap host certificate
	@if [ ! -s vault-agent-config/host.pem ]; then \
		echo "vault-agent-config/host.pem not found. Run 'make provision-host'."; exit 1; \
	fi
	@openssl x509 -in vault-agent-config/host.pem -noout -subject -serial -dates

mock-oidc-logs: ## Tail the mock OIDC issuer's logs
	$(CERT_COMPOSE) logs -f mock-oidc

cert-migrate: ## Two-Vault cert migration demo (same cert authenticates into both Vaults)
	@echo "Starting the two-Vault certificate migration demo..."
	./cert-migrate-demo.sh

agent-demo-cert: preflight-cert ## Run Vault Agent with TLS cert auto-auth and self-rotation
	@echo "Starting cert-auth Vault Agent..."
	@mkdir -p vault-agent-config vault-agent-output-cert && chmod 777 vault-agent-config vault-agent-output-cert
	$(CERT_COMPOSE) up -d --force-recreate vault-agent-cert
	./agent-cert-demo.sh

status: ## Show status of Vault service
	@echo "Service Status:"
	@echo ""
	@echo "$(CONTAINER_ENGINE) Container:"
	$(COMPOSE) ps
	@echo ""
	@echo "Vault Status:"
	@VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=myroot vault status 2>/dev/null || echo "Vault not accessible"

process-demo: ## Run PKI demo followed by process supervisor demo
	@echo "Running complete PKI + Process Supervisor demo..."
	@$(MAKE) demo
	@echo ""
	@echo "Now starting Process Supervisor demo..."
	@sleep 2
	./demo-process-supervisor.sh
