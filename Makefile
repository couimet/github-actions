.PHONY: check check-actions fmt-check format install-prereqs lint lint-fix lint-md lint-md-fix lint-sh test

include versions.mk

check: lint test check-actions

check-actions:
	bash scripts/verify-action-coverage.sh
	bash scripts/verify-version-pins.sh
	bash scripts/verify-action-shas.sh
	bash scripts/verify-no-relative-uses.sh
	bash scripts/verify-ci-checks-secrets.sh
	bash scripts/verify-dependabot-npm-coverage.sh

fmt-check:
	npx --yes prettier@$(PRETTIER_VERSION) --check .

format:
	npx --yes prettier@$(PRETTIER_VERSION) --write .

install-prereqs:
	@ok=true; \
	command -v node >/dev/null 2>&1 || { echo "Missing: node — install it: brew install node@24"; ok=false; }; \
	command -v bats >/dev/null 2>&1 || { echo "Missing: bats — install it: brew install bats-core"; ok=false; }; \
	command -v shellcheck >/dev/null 2>&1 || { echo "Missing: shellcheck — install it: brew install shellcheck"; ok=false; }; \
	command -v uv >/dev/null 2>&1 || { echo "Missing: uv — install it: brew install uv"; ok=false; }; \
	$$ok || { echo; echo "Install the missing prerequisites above, then re-run make install-prereqs."; exit 1; }

lint: install-prereqs lint-md fmt-check lint-sh

lint-fix: install-prereqs lint-md-fix format

node_modules: package.json
	npm install --no-audit --no-fund
	@touch node_modules

lint-md: node_modules
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) "**/*.md"

lint-md-fix: node_modules
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) --fix "**/*.md"

lint-sh:
	find . -type f \( -name '*.sh' -o -name '*.bash' \) -not -path '*/.claude-work/*' -not -path '*/.history/*' -not -path '*/node_modules/*' -exec shellcheck {} +

test: install-prereqs
	bats bats-tests/shell/
