#!/usr/bin/env bash
set -euo pipefail

# Verify that every action directory with a package.json has a corresponding
# npm entry in .github/dependabot.yml. Dependabot does not support wildcards,
# so each directory must be registered individually. This check catches
# forgotten registrations at CI time.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

DEPENDABOT_YML="$REPO_ROOT/.github/dependabot.yml"

if [[ ! -f "$DEPENDABOT_YML" ]]; then
  echo "::error::.github/dependabot.yml not found at ${DEPENDABOT_YML}"
  exit 1
fi

# Collect directories with a package.json (direct children of repo root,
# excluding hidden dirs and tests/ which is a fixture workspace, not an action).
package_json_dirs=()
while IFS= read -r -d '' pkg; do
  dir="$(dirname "$pkg")"
  # Skip the repo root itself and non-action directories.
  if [[ "$dir" == "$REPO_ROOT" ]]; then
    continue
  fi
  rel="${dir#"$REPO_ROOT"/}"
  [[ "$rel" == "tests" ]] && continue
  package_json_dirs+=("/${rel}")
done < <(find "$REPO_ROOT" -maxdepth 2 -name package.json -not -path '*/.claude-work/*' -not -path '*/node_modules/*' -not -path '*/tests/*' -print0 2>/dev/null)

# Collect npm directories from dependabot.yml.
# Matches lines like: directory: '/markdownlint'
dependabot_dirs=()
while IFS= read -r dir; do
  [[ -n "$dir" ]] && dependabot_dirs+=("$dir")
done < <(awk '/package-ecosystem:.*npm/{found=1; next} found && /directory:/{gsub(/.*directory:[[:space:]]*/, ""); gsub(/[[:space:]]*#.*/, ""); gsub(/^'\''|'\''$|^"|"$/, ""); print; found=0}' "$DEPENDABOT_YML")

missing=0
if (( ${#package_json_dirs[@]} > 0 )); then
  for pkg_dir in "${package_json_dirs[@]}"; do
    found=false
    if (( ${#dependabot_dirs[@]} > 0 )); then
      for dep_dir in "${dependabot_dirs[@]}"; do
        if [[ "$pkg_dir" == "$dep_dir" ]]; then
          found=true
          break
        fi
      done
    fi
    if ! $found; then
      echo "::error::${pkg_dir}/package.json is not registered in .github/dependabot.yml. Add a package-ecosystem: 'npm' entry for directory '${pkg_dir}'."
      missing=1
    else
      echo "${pkg_dir} is registered in Dependabot npm entries"
    fi
  done
fi

if (( missing )); then
  echo "::error::One or more package.json files are missing from .github/dependabot.yml. See details above."
  exit 1
fi
exit 0
