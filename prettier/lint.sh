#!/usr/bin/env bash
set -euo pipefail

# Run prettier --check with optional --config and explicit paths.
#
# Inputs (env):
#   WORKING_DIRECTORY  directory to run in (default: .)
#   CONFIG             path passed as --config (optional)
#   PATHS              space-separated path(s) to check (default: .)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

cd "${WORKING_DIRECTORY:-.}"
prettier --check ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
