#!/usr/bin/env bash
set -euo pipefail

# Install Prettier using the version from the local package.json (default)
# or an explicit version override supplied by the caller.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${PRETTIER_VERSION:-}" ]]; then
  cd "$SCRIPT_DIR"
  npm ci
  echo "$PWD/node_modules/.bin" >> "$GITHUB_PATH"
else
  npm install -g "prettier@${PRETTIER_VERSION}"
fi
