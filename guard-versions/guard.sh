#!/usr/bin/env bash
set -euo pipefail

base_ref="${BASE_REF:-}"
head_ref="${HEAD_REF:-}"

if [[ -z "$base_ref" || -z "$head_ref" ]]; then
  echo "::error::BASE_REF and HEAD_REF are required. Set base-ref and head-ref inputs, or run in a pull_request context."
  exit 2
fi

if ! changed_files=$(git diff --name-only "${base_ref}...${head_ref}" 2>/dev/null); then
  echo "::error::git diff failed — cannot resolve refs '${base_ref}...${head_ref}'"
  exit 2
fi

# Check for pre-release versions in changed package.json files
echo "::group::Checking package.json version fields"
pkg_jsons=$(echo "$changed_files" | grep 'package\.json$' || true)
if [[ -z "$pkg_jsons" ]]; then
  echo "No package.json files changed. Nothing to guard."
  echo "::endgroup::"
  exit 0
fi

had_errors=0
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if [[ ! -f "$file" ]]; then
    echo "::warning file=${file}::File not found in working tree, skipping"
    continue
  fi
  ver=$(jq -r '.version // empty' "$file" 2>/dev/null || true)
  if [[ -n "$ver" ]] && echo "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-.+'; then
    echo "::error file=${file}::Pre-release version '${ver}' found in ${file}. Use a stable semver (x.y.z) for main branch PRs."
    had_errors=1
  fi
done <<< "$pkg_jsons"
echo "::endgroup::"

if [[ "$had_errors" -ne 0 ]]; then
  echo ""
  echo "Pre-release versions are not allowed in main-branch PRs."
  exit 1
fi

echo "All package.json versions are stable."
exit 0
