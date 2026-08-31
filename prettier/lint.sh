#!/usr/bin/env bash
set -euo pipefail

# Run prettier with optional --config and explicit paths. When CONFIG is
# empty and Prettier would find no config for the target paths (no
# .prettierrc* / prettier.config.* or package.json "prettier" key in the
# working directory or any ancestor), falls back to the canonical
# @couimet/eslint-config/prettier config.
#
# Inputs (env):
#   MODE               check (default, --check) or fix (--write)
#   WORKING_DIRECTORY  directory to run in (default: .)
#   CONFIG             path passed as --config (optional)
#   PATHS              space-separated path(s) to check (default: .)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

cd "${WORKING_DIRECTORY:-.}"

# Mirror Prettier's own discovery: a config file or a package.json "prettier"
# key found in the working directory or any ancestor counts, so the fallback
# never overrides a config Prettier would resolve for the target files.
has_prettier_config() {
  local dir="$1"
  while true; do
    if compgen -G "$dir/.prettierrc*" > /dev/null \
      || compgen -G "$dir/prettier.config.*" > /dev/null \
      || { [[ -f "$dir/package.json" ]] \
           && node -e 'process.exit(require(process.argv[1]).prettier ? 0 : 1)' "$dir/package.json" 2>/dev/null; }; then
      return 0
    fi
    if [[ "$dir" == "/" ]]; then
      return 1
    fi
    dir="$(dirname "$dir")"
  done
}

# Fall back to the canonical config from @couimet/eslint-config/prettier when
# Prettier would resolve no config of its own for the target files.
if [[ -z "${CONFIG:-}" ]] && ! has_prettier_config "$PWD"; then
  CONFIG_ARGS=(--config "$SCRIPT_DIR/node_modules/@couimet/eslint-config/prettier.js")
fi

if [[ "${MODE:-check}" != "check" && "${MODE:-check}" != "fix" ]]; then
  echo "ERROR: MODE must be 'check' or 'fix', got '${MODE}'" >&2
  exit 1
fi

if [[ "${MODE:-check}" == "fix" ]]; then
  prettier --write ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
else
  prettier --check ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
fi
