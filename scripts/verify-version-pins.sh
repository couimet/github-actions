#!/usr/bin/env bash
set -euo pipefail

# Verify that each action's version-pin default matches versions.mk.
#
# versions.mk is the single source of truth for tool versions. Composite action
# inputs::default is static (GitHub Actions does not support dynamic defaults),
# so this check catches drift between the two.
#
# Inputs (env):
#   VERSIONS_MK_PATH  path to versions.mk (default: <repo_root>/versions.mk)
#   ACTION_ROOT       dir containing action subdirectories (default: <repo_root>)
#   CHECKS            space-or-newline-separated list of var:dir:input entries
#                     (default: hardcoded list below)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

VERSIONS_MK="${VERSIONS_MK_PATH:-$REPO_ROOT/versions.mk}"
ACTION_ROOT="${ACTION_ROOT:-$REPO_ROOT}"

if [[ ! -f "$VERSIONS_MK" ]]; then
  echo "::error::versions.mk not found at ${VERSIONS_MK}"
  exit 1
fi

# Look up a value from versions.mk by variable name.
get_version() {
  local var="$1"
  local val
  val="$(awk -F':=' -v var="$var" '
    $1 ~ "^[[:space:]]*" var "[[:space:]]*$" {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "$VERSIONS_MK")"
  [[ -n "$val" ]] || return 1
  echo "$val"
}

# Default checks: var_name action_dir input_name
DEFAULT_CHECKS="
PRETTIER_VERSION prettier prettier-version
MARKDOWNLINT_VERSION markdownlint markdownlint-version
"
CHECKS="${CHECKS:-$DEFAULT_CHECKS}"

missing=0
while read -r var action_dir input_name; do
  [[ -z "$var" ]] && continue

  if ! expected="$(get_version "$var")"; then
    echo "::error::Variable ${var} not found in ${VERSIONS_MK}"
    missing=1
    continue
  fi

  action_yml="$ACTION_ROOT/$action_dir/action.yml"
  if [[ ! -f "$action_yml" ]]; then
    echo "::error::Action file not found: ${action_yml}"
    missing=1
    continue
  fi

  # Extract the default value for the input. The YAML structure is:
  #   <input-name>:
  #     ...
  #     default: '<value>'
  actual="$(awk -v input="$input_name" '
    $0 ~ "^[[:space:]]*" input ":" { found=1; next }
    found && /default:/ {
      gsub(/.*default:[[:space:]]*/, "")
      gsub(/^'\''|'\''$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$action_yml")"

  if [[ -z "$actual" ]]; then
    echo "::error::Could not extract default for input '${input_name}' from ${action_yml}"
    missing=1
    continue
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "::error::Version drift: ${action_dir}/${input_name} default is '${actual}' but ${var} in versions.mk is '${expected}'"
    missing=1
  else
    echo "${action_dir}/${input_name} default '${actual}' matches versions.mk ${var}"
  fi
done <<< "$CHECKS"

if (( missing )); then
  echo "::error::One or more version pins have drifted from versions.mk. Update versions.mk first, then update the action default(s) to match."
  exit 1
fi
exit 0
