#!/usr/bin/env bash
set -euo pipefail

# Run prettier with optional --config and explicit paths.
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

if [[ "${MODE:-check}" == "fix" ]]; then
  prettier --write ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
else
  prettier --check ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
fi
