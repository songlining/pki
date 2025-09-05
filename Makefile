.PHONY: help start stop init demo clean

help: ## Show this help message
	@echo "HashiCorp Vault Enterprise PKI Demo"
	@echo "===================================="
	@echo ""
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

start: ## Start Vault Enterprise container
	@echo "🚀 Starting Vault Enterprise container..."
	docker-compose up -d
	@echo "✅ Container started!"

stop: ## Stop Vault Enterprise container
	@echo "🛑 Stopping Vault Enterprise container..."
	docker-compose down
	@echo "✅ Container stopped!"

init: ## Initialize Vault and PKI (run after start)
	@echo "🔧 Initializing Vault and PKI..."
	./vault-init.sh

demo: ## Run the interactive PKI certificate demo
	@echo "🎭 Starting PKI certificate demo..."
	./pki-demo.sh

clean: ## Clean up demo artifacts and containers
	@echo "🧹 Cleaning up demo artifacts..."
	rm -f *.crt *.csr *.key *.pem *.txt
	docker-compose down -v
	@echo "✅ Cleanup complete!"

setup: start init ## Complete setup (start + init)
	@echo "🎉 Setup complete! Run 'make demo' to start the PKI demonstration."

status: ## Show status of Vault service
	@echo "📊 Service Status:"
	@echo ""
	@echo "Docker Container:"
	docker-compose ps
	@echo ""
	@echo "Vault Status:"
	@VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=myroot vault status 2>/dev/null || echo "Vault not accessible"