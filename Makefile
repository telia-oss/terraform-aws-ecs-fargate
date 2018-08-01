OS=darwin
DIR=$(shell pwd)

default: test

test:
	@echo "== Test =="
	@if ! terraform fmt -write=false -check=true >> /dev/null; then \
		echo "✗ terraform fmt (Some files need to be formatted, run 'terraform fmt' to fix.)"; \
		exit 1; \
	else \
		echo "√ terraform fmt"; \
	fi

	@for d in $$(find . -type f -name '*.tf' -path "./modules/*" -not -path "**/.terraform/*" -exec dirname {} \; | sort -u); do \
		cd $$d; \
		terraform init -backend=false >> /dev/null; \
		terraform validate -check-variables=false; \
		if [ $$? -eq 1 ]; then \
			echo "✗ terraform validate failed: $$d"; \
			exit 1; \
		fi; \
		cd $(DIR); \
	done
	@echo "√ terraform validate modules (not including variables)"; \

	@for d in $$(find . -type f -name '*.tf' -path "./examples/*" -not -path "**/.terraform/*" -exec dirname {} \; | sort -u); do \
		cd $$d; \
		terraform init -backend=false >> /dev/null; \
		terraform validate -check-variables=false; \
		if [ $$? -eq 1 ]; then \
			echo "✗ terraform validate failed: $$d"; \
			exit 1; \
		fi; \
		cd $(DIR); \
	done
	@echo "√ terraform validate examples"; \

.PHONY: default test
