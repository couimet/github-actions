.PHONY: check check-actions fmt-check format install-prereqs lint lint-fix lint-md lint-md-fix lint-sh test

include versions.mk

check: lint test check-actions

check-actions:
	bash scripts/verify-action-coverage.sh
	bash scripts/verify-version-pins.sh
	bash scripts/generate-mise-toml.sh --check
	bash scripts/verify-action-shas.sh
	bash scripts/verify-no-relative-uses.sh
	bash scripts/verify-ci-checks-secrets.sh
	bash scripts/verify-required-check-docs.sh
	bash scripts/verify-dependabot-npm-coverage.sh

fmt-check:
	npx --yes prettier@$(PRETTIER_VERSION) --check .

format:
	npx --yes prettier@$(PRETTIER_VERSION) --write .

install-prereqs:
	@command -v mise >/dev/null 2>&1 || { \
		echo "Missing: mise — install it: https://mise.jdx.dev/getting-started.html"; \
		echo; \
		echo "Then re-run make install-prereqs."; \
		exit 1; \
	}
	@mise install
	@missing=""; \
	for tool in node bats shellcheck uv jq; do \
		command -v $$tool >/dev/null 2>&1 || missing="$$missing $$tool"; \
	done; \
	[ -z "$$missing" ] || { \
		echo "mise is installed, but these tools do not resolve on PATH:$$missing"; \
		echo; \
		echo "Activate mise in your shell so its shims win, then re-run make install-prereqs."; \
		echo "See https://mise.jdx.dev/getting-started.html"; \
		exit 1; \
	}

lint: install-prereqs lint-md fmt-check lint-sh

lint-fix: install-prereqs lint-md-fix format

markdownlint/node_modules: markdownlint/package.json
	cd markdownlint && npm install --no-audit --no-fund
	@touch markdownlint/node_modules

lint-md: markdownlint/node_modules
	markdownlint/node_modules/.bin/markdownlint-cli2 "**/*.md"

lint-md-fix: markdownlint/node_modules
	markdownlint/node_modules/.bin/markdownlint-cli2 --fix "**/*.md"

lint-sh:
	find . -type f \( -name '*.sh' -o -name '*.bash' \) -not -path '*/.claude-work/*' -not -path '*/.history/*' -not -path '*/node_modules/*' -exec shellcheck {} +

test: install-prereqs markdownlint/node_modules
	bats bats-tests/shell/
