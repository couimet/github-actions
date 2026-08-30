#!/usr/bin/env bash
set -euo pipefail

# Run prettier with optional --config and explicit paths. When CONFIG is
# empty and the working directory has no .prettierrc* / prettier.config.*,
# falls back to the canonical @couimet/eslint-config/prettier config.
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

# Fall back to the canonical config from @couimet/eslint-config/prettier when
# the working directory has no file-based prettier config of its own.
if [[ -z "${CONFIG:-}" ]] \
  && ! compgen -G ".prettierrc*" > /dev/null \
  && ! compgen -G "prettier.config.*" > /dev/null; then
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
