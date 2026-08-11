#!/usr/bin/env bash
set -euo pipefail

# Run markdownlint-cli2 with optional --config and explicit paths.
#
# Inputs (env):
#   MODE               check (default, read-only) or fix (adds --fix)
#   CONFIG             path to a config file passed as --config (optional)
#   PATHS              space-separated glob(s) of Markdown files to lint
#   WORKING_DIRECTORY  directory to run in (default: .)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

cd "${WORKING_DIRECTORY:-.}"

if [[ "${MODE:-check}" != "check" && "${MODE:-check}" != "fix" ]]; then
  echo "ERROR: MODE must be 'check' or 'fix', got '${MODE}'" >&2
  exit 1
fi

FIX_ARGS=()
if [[ "${MODE:-check}" == "fix" ]]; then
  FIX_ARGS+=(--fix)
fi

markdownlint-cli2 ${FIX_ARGS[@]+"${FIX_ARGS[@]}"} ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
