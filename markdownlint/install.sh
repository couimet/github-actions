#!/usr/bin/env bash
set -euo pipefail

# Install markdownlint-cli2 using the version from the local package.json
# (default) or an explicit version override supplied by the caller.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${MARKDOWNLINT_VERSION:-}" ]]; then
  cd "$SCRIPT_DIR"
  npm ci
  echo "$PWD/node_modules/.bin" >> "$GITHUB_PATH"
else
  # The version override installs the requested cli2 globally, but the action's
  # local node_modules must still be provisioned: the zero-config fallback
  # (@couimet/markdownlint-config) and the MD060A rule ship from there. npm ci
  # installs them without rewriting package-lock.json. node_modules/.bin is not
  # appended to GITHUB_PATH, so the globally installed cli2 stays the one used.
  cd "$SCRIPT_DIR"
  npm ci
  npm install -g "markdownlint-cli2@${MARKDOWNLINT_VERSION}"
fi
