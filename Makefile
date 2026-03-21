.PHONY: help start stop init demo clean

help: ## Show this help message
	@echo "HashiCorp Vault Enterprise PKI Demo"
	@echo "===================================="
	@echo ""
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

start: ## Start Vault Enterprise container
	@echo "Starting Vault Enterprise container..."
	docker-compose up -d
	@echo "Container started!"

stop: ## Stop Vault Enterprise container
	@echo "Stopping Vault Enterprise container..."
	docker-compose down
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

watch-rotation: ## Watch certificate rotation in real-time
	@echo "Starting certificate rotation monitor..."
	./watch-rotation.sh

clean: ## Clean up demo artifacts and containers
	@echo "Cleaning up demo artifacts..."
	rm -f *.crt *.csr *.key *.pem *.txt
	docker-compose down -v
	@echo "Cleanup complete!"

setup: start init setup-agent ## Complete setup (start + init + agent)
	@echo "Setup complete! Run 'make demo' or 'make agent-demo' to start demonstrations."

status: ## Show status of Vault service
	@echo "Service Status:"
	@echo ""
	@echo "Docker Container:"
	docker-compose ps
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