.PHONY: check lint lint-fix test

MARKDOWNLINT_VERSION := 0.22.1

check: lint test

lint:
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION)

lint-fix:
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) --fix

test:
	bats tests/shell/
