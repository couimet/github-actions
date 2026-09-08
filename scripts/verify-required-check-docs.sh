#!/usr/bin/env bash
set -euo pipefail

# Verify the README "Required status checks" block of each reusable workflow
# lists exactly the jobs that workflow defines. Consumers read that block to
# configure branch protection when they adopt the workflow, so it must stay in
# sync with the workflow files or adopters will require stale or missing checks.
#
# A job deliberately documented as not a merge gate (auto-fix only reports on the
# fix run after a failure) is excluded from the required list: see exclusions_for.
#
# Inputs (env):
#   WORKFLOWS_DIR  dir of reusable workflow files (default: <repo_root>/.github/workflows)
#   README_PATH    README to check (default: <repo_root>/README.md)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

WORKFLOWS_DIR="${WORKFLOWS_DIR:-$REPO_ROOT/.github/workflows}"
README_PATH="${README_PATH:-$REPO_ROOT/README.md}"

# The reusable workflows whose required-check docs are verified. Add a new
# reusable workflow here when it grows a README "Required status checks" block.
REUSABLE_WORKFLOWS="ci-checks shell-ci-checks typescript-ci-checks"

# Jobs a workflow defines but deliberately does not list as required checks.
exclusions_for() {
  case "$1" in
    typescript-ci-checks) echo "auto-fix" ;;
    *) echo "" ;;
  esac
}

# Top-level job keys under 'jobs:' in a workflow file.
job_ids_from_yml() {
  local file="$1" line in_jobs=0 job
  while IFS= read -r line; do
    if [[ "$line" =~ ^jobs:[[:space:]]*$ ]]; then
      in_jobs=1
      continue
    fi
    [[ "$in_jobs" -eq 1 ]] || continue
    if [[ "$line" =~ ^[^[:space:]] ]]; then
      # A top-level key after jobs: ends the jobs section.
      in_jobs=0
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]{2}[A-Za-z0-9_.-]+:[[:space:]]*$ ]]; then
      job="${line%%:*}"
      job="${job#"${job%%[![:space:]]*}"}"
      echo "$job"
    fi
  done < "$file"
}

# Tokens after " / " inside ```text fences of the workflow's README section.
readme_section_tokens() {
  local wf="$1"
  awk -v wf="$wf" '
    BEGIN { section = 0; infence = 0; textfence = 0 }
    {
      if (section == 0) {
        if ($0 == "### `" wf "`") section = 1
        next
      }
      if ($0 ~ /^#{1,3} /) { section = 0; next }
      if ($0 ~ /^```/) {
        if (infence == 0) { infence = 1; textfence = ($0 == "```text") }
        else { infence = 0; textfence = 0 }
        next
      }
      if (textfence == 1 && $0 ~ / \/ /) {
        line = $0
        sub(/^.* \/ /, "", line)
        print line
      }
    }
  ' "$README_PATH"
}

list_has() {
  local tok="$1"
  shift
  local it
  for it in "$@"; do
    [[ "$it" == "$tok" ]] && return 0
  done
  return 1
}

violations=0

for wf in $REUSABLE_WORKFLOWS; do
  yml="$WORKFLOWS_DIR/$wf.yml"
  if [[ ! -f "$yml" ]]; then
    echo "::error::$yml not found"
    violations=$((violations + 1))
    continue
  fi

  # Job ids and documented tokens contain no spaces, so join with spaces before
  # read: read consumes only the first line of a newline-separated here-string.
  read -ra yml_jobs <<< "$(job_ids_from_yml "$yml" | sort -u | tr '\n' ' ')"
  read -ra doc_tokens <<< "$(readme_section_tokens "$wf" | sort -u | tr '\n' ' ')"
  read -ra excluded <<< "$(exclusions_for "$wf" | tr '\n' ' ')"

  # Jobs the workflow defines that the README must list, minus exclusions.
  # ${arr[@]+...} keeps empty arrays from tripping set -u on bash 3.2.
  read -ra expected <<< "$(for j in ${yml_jobs[@]+"${yml_jobs[@]}"}; do
    list_has "$j" ${excluded[@]+"${excluded[@]}"} || echo "$j"
  done | tr '\n' ' ')"

  undoc=()   # defined by the workflow but not listed as a required check
  extra=()   # listed as a required check but not a workflow job

  for j in ${expected[@]+"${expected[@]}"}; do
    list_has "$j" ${doc_tokens[@]+"${doc_tokens[@]}"} || undoc+=("$j")
  done
  for local_tok in ${doc_tokens[@]+"${doc_tokens[@]}"}; do
    list_has "$local_tok" ${expected[@]+"${expected[@]}"} || extra+=("$local_tok")
  done

  if [[ ${#undoc[@]} -gt 0 || ${#extra[@]} -gt 0 ]]; then
    echo "::error::README required-status-checks block for ${wf} is out of sync with the jobs in ${yml}."
    [[ ${#undoc[@]} -gt 0 ]] && printf '  not listed as required checks (add to the README block): %s\n' "${undoc[*]}"
    [[ ${#extra[@]} -gt 0 ]] && printf '  listed but not a workflow job (remove from the README block): %s\n' "${extra[*]}"
    violations=$((violations + 1))
  fi
done

if (( violations )); then
  echo "::error::${violations} reusable workflow(s) have a README required-status-checks block out of sync with their workflow file."
  exit 1
fi

echo "README required-status-checks blocks match workflow job ids: ${REUSABLE_WORKFLOWS}."
exit 0
