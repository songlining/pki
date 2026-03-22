.PHONY: help start stop init demo clean setup status agent-demo setup-agent watch-rotation process-demo preflight live-demo workshop-demo operator-demo reset-demo

help: ## Show this help message
	@echo "HashiCorp Vault CE PKI Demo"
	@echo "==========================="
	@echo ""
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

start: ## Start Vault CE demo containers
	@echo "Starting Vault CE demo containers..."
	docker compose up -d
	@echo "Container started!"

stop: ## Stop Vault CE demo containers
	@echo "Stopping Vault CE demo containers..."
	docker compose down
	@echo "Container stopped!"

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

live-demo: preflight ## Guided entrypoint for a short live presentation
	./demo-paths.sh live --launch

workshop-demo: preflight ## Guided entrypoint for a hands-on workshop path
	./demo-paths.sh workshop

operator-demo: preflight ## Guided entrypoint for the operator and automation path
	./demo-paths.sh operator --launch

watch-rotation: ## Watch certificate rotation in real-time
	@echo "Starting certificate rotation monitor..."
	./watch-rotation.sh

reset-demo: ## Safely reset known generated demo state
	@echo "Resetting known demo state..."
	./reset-demo-state.sh

clean: reset-demo ## Alias for safe demo reset

setup: start init setup-agent ## Complete setup (start + init + agent)
	@echo "Setup complete!"
	@echo "Choose your path:"
	@echo "  make live-demo"
	@echo "  make workshop-demo"
	@echo "  make operator-demo"

status: ## Show status of Vault service
	@echo "Service Status:"
	@echo ""
	@echo "Docker Container:"
	docker compose ps
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
