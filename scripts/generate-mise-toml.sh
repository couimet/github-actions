#!/usr/bin/env bash
set -euo pipefail

# Generate mise.toml from the repo's declared version sources.
#
# Node comes from .nvmrc. Bats comes from versions.mk (BATS_VERSION), the
# contract shared actions bake for consumers. ShellCheck, uv, and jq are not
# part of any shared action, so they have no other declared home and are pinned
# here as constants; see the comment at the top of versions.mk.
#
# Usage:
#   generate-mise-toml.sh           write mise.toml
#   generate-mise-toml.sh --check   fail if mise.toml is out of sync
#
# Inputs (env):
#   NVMRC_PATH        path to .nvmrc (default: <repo_root>/.nvmrc)
#   VERSIONS_MK_PATH  path to versions.mk (default: <repo_root>/versions.mk)
#   MISE_TOML_PATH    path to mise.toml (default: <repo_root>/mise.toml)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

NVMRC="${NVMRC_PATH:-$REPO_ROOT/.nvmrc}"
VERSIONS_MK="${VERSIONS_MK_PATH:-$REPO_ROOT/versions.mk}"
MISE_TOML="${MISE_TOML_PATH:-$REPO_ROOT/mise.toml}"

# Dev-only tools that no shared action pins. Bump them here; the generated
# mise.toml and the drift check follow.
SHELLCHECK_VERSION="0.11.0"
UV_VERSION="0.11.21"
JQ_VERSION="1.7.1"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
elif [[ -n "${1:-}" ]]; then
  echo "error: unknown argument '${1}' (expected no argument or --check)" >&2
  exit 1
fi

read_node() {
  if [[ ! -f "$NVMRC" ]]; then
    echo "::error::.nvmrc not found at ${NVMRC}" >&2
    exit 1
  fi

  local raw
  raw="$(tr -d '[:space:]' < "$NVMRC")"
  if [[ -z "$raw" ]]; then
    echo "::error::.nvmrc at ${NVMRC} is empty" >&2
    exit 1
  fi

  # .nvmrc may carry a leading v (e.g. v24); mise.toml wants the bare version.
  echo "${raw#v}"
}

read_versions_mk() {
  local var="$1"

  if [[ ! -f "$VERSIONS_MK" ]]; then
    echo "::error::versions.mk not found at ${VERSIONS_MK}" >&2
    exit 1
  fi

  local val
  val="$(awk -F':=' -v var="$var" '
    $1 ~ "^[[:space:]]*" var "[[:space:]]*$" {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "$VERSIONS_MK")"

  if [[ -z "$val" ]]; then
    echo "::error::Variable ${var} not found in ${VERSIONS_MK}" >&2
    exit 1
  fi

  echo "$val"
}

render() {
  # Read into variables rather than expanding inside the heredoc: a failure
  # inside a heredoc command substitution only exits that subshell, which would
  # let a broken value reach the output.
  local node bats
  node="$(read_node)" || return 1
  bats="$(read_versions_mk BATS_VERSION)" || return 1

  cat <<EOF
[tools]
node = "${node}"
bats = "${bats}"
shellcheck = "${SHELLCHECK_VERSION}"
uv = "${UV_VERSION}"
jq = "${JQ_VERSION}"
EOF
}

main() {
  local generated
  generated="$(render)" || exit 1

  if [[ "$CHECK_ONLY" == true ]]; then
    if [[ ! -f "$MISE_TOML" ]]; then
      echo "::error::mise.toml not found at ${MISE_TOML}. Run scripts/generate-mise-toml.sh and commit the result." >&2
      exit 1
    fi

    if ! diff -u "$MISE_TOML" <(printf '%s\n' "$generated") >&2; then
      echo "::error::mise.toml is out of sync with .nvmrc and versions.mk. Run scripts/generate-mise-toml.sh and commit the result." >&2
      exit 1
    fi

    echo "mise.toml is in sync with .nvmrc and versions.mk."
    return 0
  fi

  printf '%s\n' "$generated" > "$MISE_TOML"
  echo "Wrote ${MISE_TOML}"
}

main
