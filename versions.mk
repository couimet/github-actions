# Single source of truth for the versions this repo's shared actions bake as
# defaults for consumers. scripts/verify-version-pins.sh enforces that each
# variable matches the corresponding action.yml input default (or package.json
# devDependency), so a consumer-facing pin never drifts.
#
# This file is not a registry for every tool this repo uses. A tool that no
# shared action pins lives elsewhere: node is declared in .nvmrc, and the
# dev-only tools ShellCheck, uv, and jq are declared as constants in
# scripts/generate-mise-toml.sh, the script that generates mise.toml. Add a
# variable here only when a shared action bakes that version for consumers.

BATS_VERSION := 1.14.0
LYCHEE_VERSION := 0.24.2
MARKDOWNLINT_VERSION := 0.23.2
PRETTIER_VERSION := 3.9.6
