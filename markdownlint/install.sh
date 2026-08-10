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
  npm install -g "markdownlint-cli2@${MARKDOWNLINT_VERSION}"
fi
