#!/usr/bin/env bash
set -euo pipefail

# Run the consumer-supplied fix command.
#
# Inputs (env):
#   FIX_COMMAND        shell command to run
#   WORKING_DIRECTORY  directory to run in (default: .)

if [[ -z "${FIX_COMMAND:-}" ]]; then
  echo "error: FIX_COMMAND is required" >&2
  exit 1
fi

cd "${WORKING_DIRECTORY:-.}"
bash -euo pipefail -c "$FIX_COMMAND"
