#!/usr/bin/env bash
set -euo pipefail

# Discover shell scripts and run shellcheck.
#
# Inputs (env):
#   PATHS       root(s) to search, space-separated (default: .)
#   EXTENSIONS  space-separated file extensions (default: sh bash)
#   EXCLUDE     space-separated path fragments to exclude (default: .claude-work .history node_modules .git)
#   SEVERITY    optional --severity flag value

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

EXTENSIONS="${EXTENSIONS:-sh bash}"
EXCLUDE="${EXCLUDE-.claude-work .history node_modules .git}"

# Build find -name arguments from space-separated extensions.
IFS=' ' read -ra ext_arr <<< "$EXTENSIONS"
name_args=()
for ext in "${ext_arr[@]}"; do
  name_args+=(-name "*.$ext" -o)
done
unset 'name_args[${#name_args[@]}-1]'

# Build find exclusion arguments from space-separated fragments.
IFS=' ' read -ra excl_arr <<< "$EXCLUDE"
exclude_args=()
for fragment in "${excl_arr[@]}"; do
  [[ -z "$fragment" ]] && continue
  exclude_args+=(-not -path "*/$fragment/*")
done

# Build shellcheck severity flag.
severity_args=()
if [[ -n "${SEVERITY:-}" ]]; then
  severity_args+=(--severity "$SEVERITY")
fi

find "${PATH_ARGS[@]}" -type f \( "${name_args[@]}" \) "${exclude_args[@]}" -exec shellcheck ${severity_args[@]+"${severity_args[@]}"} {} +
