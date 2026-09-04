#!/usr/bin/env bash
set -euo pipefail

# Diff the required status checks of a branch against the checks the couimet
# reusable workflows it calls produce.
#
# A reusable workflow never runs on its own, so it reports each of its jobs as a
# status check named "{caller job} / {inner job}". Adopting one is therefore a
# branch-protection change: required checks set under the old (often bare) names
# are no longer reported and block merges with "Expected - Waiting for status to
# be reported" even while every reported check is green. Run this script inside
# the consumer repo before merging the adoption so the diff is visible up front.
#
# Output: MISSING contexts (produced by the reusable workflows but not yet
# required) and STALE contexts (required under a bare inner-job name that the
# reusable workflow now reports under a caller prefix). Exit 1 when either list
# is non-empty.
#
# Inputs (env):
#   REPO               owner/repo to inspect (default: derived from origin remote)
#   BRANCH             branch whose required checks to compare (default: current)
#   WORKFLOWS_DIR      directory of workflow files to scan (default: .github/workflows)
#   CALLER_JOBS        optional override "caller=workflow ..." pairs, bypasses scanning
#   DISABLED_JOBS      optional "workflow:job ..." pairs the consumer toggles off
#   PRINT_ONLY         when non-empty, print the expected contexts and exit 0 (no gh)
#   MOCK_CONTEXTS_FILE optional file of currently required contexts to diff against
#                      instead of calling gh (test seam)

REPO="${REPO:-}"
BRANCH="${BRANCH:-}"
WORKFLOWS_DIR="${WORKFLOWS_DIR:-.github/workflows}"
CALLER_JOBS="${CALLER_JOBS:-}"
DISABLED_JOBS="${DISABLED_JOBS:-}"
PRINT_ONLY="${PRINT_ONLY:-}"
MOCK_CONTEXTS_FILE="${MOCK_CONTEXTS_FILE:-}"

EXPECTED_LINES=()
ACTUAL_LINES=()

# Job ids each reusable workflow reports. None of the workflows names its inner
# jobs, so each reported check uses the job id as written in the workflow file.
workflow_jobs() {
  case "$1" in
    ci-checks) echo "format lint build test" ;;
    shell-ci-checks) echo "shellcheck bats-test" ;;
    typescript-ci-checks) echo "format lint markdownlint build test guard-versions check-no-prerelease-deps check-todos auto-fix" ;;
    *) return 1 ;;
  esac
}

# Flat list of every inner job id, used to recognise bare stale contexts.
ALL_INNER_JOBS="format lint markdownlint build test guard-versions check-no-prerelease-deps check-todos auto-fix shellcheck bats-test"

inner_in_all() {
  [[ " $ALL_INNER_JOBS " == *" $1 "* ]]
}

repo_from_remote() {
  local url
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -z "$url" ]] && return 1
  case "$url" in
    https://github.com/*) url="${url#https://github.com/}" ;;
    http://github.com/*) url="${url#http://github.com/}" ;;
    git@github.com:*) url="${url#git@github.com:}" ;;
    ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
  esac
  url="${url%.git}"
  echo "$url"
}

# Parse the consumer's workflow files for jobs that call a couimet reusable
# workflow and print one "caller|workflow" line per job. The caller segment is
# the job's name: when it sets one, else its job id.
discover_pairs() {
  local file line in_jobs=0 cur_job="" cur_name="" wf
  for file in "$WORKFLOWS_DIR"/*.yml; do
    [[ -e "$file" ]] || continue
    while IFS= read -r line; do
      if [[ "$line" =~ ^jobs: ]]; then
        in_jobs=1
        cur_job=""
        cur_name=""
        continue
      fi
      [[ "$in_jobs" -ne 1 ]] && continue
      if [[ "$line" =~ ^[[:space:]]{2}[A-Za-z0-9_.-]+: ]]; then
        cur_job="${line%%:*}"
        cur_job="${cur_job#"${cur_job%%[![:space:]]*}"}"
        cur_name=""
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]{4}name:[[:space:]]+(.*)$ ]]; then
        cur_name="${BASH_REMATCH[1]}"
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]{4}uses:[[:space:]]+couimet/github-actions/.github/workflows/([A-Za-z0-9_.-]+)\.yml@main ]]; then
        wf="${BASH_REMATCH[1]}"
        if workflow_jobs "$wf" >/dev/null 2>&1 && [[ -n "$cur_job" ]]; then
          printf '%s|%s\n' "${cur_name:-$cur_job}" "$wf"
        fi
      fi
    done < "$file"
  done
}

pairs_from_override() {
  local item
  for item in $CALLER_JOBS; do
    printf '%s\n' "${item/=/|}"
  done
}

disabled_contains() {
  local wf="$1" job="$2" pair
  for pair in $DISABLED_JOBS; do
    [[ "$pair" == "${wf}:${job}" ]] && return 0
  done
  return 1
}

build_expected() {
  local caller wf job list ctx
  while IFS='|' read -r caller wf; do
    [[ -z "$caller" ]] && continue
    list="$(workflow_jobs "$wf")"
    for job in $list; do
      disabled_contains "$wf" "$job" && continue
      ctx="${caller} / ${job}"
      EXPECTED_LINES+=("$ctx")
    done
  done
}

actual_contains() {
  local ctx="$1" line
  for line in "${ACTUAL_LINES[@]}"; do
    [[ "$line" == "$ctx" ]] && return 0
  done
  return 1
}

fetch_actual() {
  ACTUAL_LINES=()
  if [[ -n "$MOCK_CONTEXTS_FILE" ]]; then
    [[ -f "$MOCK_CONTEXTS_FILE" ]] || { echo "MOCK_CONTEXTS_FILE not found: ${MOCK_CONTEXTS_FILE}" >&2; exit 2; }
    while IFS= read -r line; do
      [[ -n "$line" ]] && ACTUAL_LINES+=("$line")
    done < "$MOCK_CONTEXTS_FILE"
    return 0
  fi
  if [[ -z "$REPO" ]]; then
    REPO="$(repo_from_remote)" || { echo "REPO is not set and no origin remote is available to derive it from" >&2; exit 2; }
  fi
  if [[ -z "$BRANCH" ]]; then
    BRANCH="$(git branch --show-current 2>/dev/null || true)"
    [[ -z "$BRANCH" ]] && { echo "BRANCH is not set and the current checkout is detached" >&2; exit 2; }
  fi
  local body
  if ! body="$(gh api "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks/contexts" --jq '.[]' 2>&1)"; then
    echo "Could not read required status checks for ${REPO} @ ${BRANCH} through the classic branch-protection API. If the repo protects its default branch with a ruleset, check the ruleset's required status checks rule manually. Otherwise confirm gh is authenticated with access to branch protection." >&2
    return 1
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && ACTUAL_LINES+=("$line")
  done <<< "$body"
}

# For a bare stale context, name the expected "caller / job" context that now
# reports it, so the consumer knows what to require in its place.
suggestion_for() {
  local bare="$1" ctx first=""
  for ctx in ${EXPECTED_LINES[@]+"${EXPECTED_LINES[@]}"}; do
    case "$ctx" in
      *" / $bare") if [[ -z "$first" ]]; then first="$ctx"; fi ;;
    esac
  done
  echo "$first"
}

usage_error() {
  echo "$1" >&2
  exit 2
}

if [[ -n "$CALLER_JOBS" ]]; then
  pairs="$(pairs_from_override)"
else
  [[ -d "$WORKFLOWS_DIR" ]] || usage_error "WORKFLOWS_DIR not found: ${WORKFLOWS_DIR}"
  pairs="$(discover_pairs)"
fi

build_expected <<< "$pairs"

if [[ -n "$PRINT_ONLY" ]]; then
  # ${arr[@]+...} keeps an empty array from tripping set -u on bash 3.2.
  printf '%s\n' ${EXPECTED_LINES[@]+"${EXPECTED_LINES[@]}"} | sort -u
  exit 0
fi

if [[ ${#EXPECTED_LINES[@]} -eq 0 ]]; then
  echo "No caller jobs for the couimet reusable workflows (ci-checks, shell-ci-checks, typescript-ci-checks) found in ${WORKFLOWS_DIR}. Pass CALLER_JOBS (e.g. CALLER_JOBS='ci=typescript-ci-checks shell-ci-checks=shell-ci-checks') to check explicit caller jobs."
  exit 0
fi

fetch_actual || exit 0

missing=()
for ctx in ${EXPECTED_LINES[@]+"${EXPECTED_LINES[@]}"}; do
  actual_contains "$ctx" || missing+=("$ctx")
done

stale=()
for ctx in ${ACTUAL_LINES[@]+"${ACTUAL_LINES[@]}"}; do
  if [[ "$ctx" != *" / "* ]] && inner_in_all "$ctx"; then
    replacement="$(suggestion_for "$ctx")"
    [[ -n "$replacement" ]] && stale+=("${ctx} -> ${replacement}")
  fi
done

if [[ ${#missing[@]} -eq 0 && ${#stale[@]} -eq 0 ]]; then
  if [[ -n "$BRANCH" ]]; then
    echo "OK: the required checks for ${BRANCH} already cover every check the couimet reusable workflows produce."
  else
    echo "OK: the required checks already cover every check the couimet reusable workflows produce."
  fi
  exit 0
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "MISSING: produced by the reusable workflows but not required. Add these to branch protection:"
  printf '  %s\n' "${missing[@]}"
fi
if [[ ${#stale[@]} -gt 0 ]]; then
  echo "STALE: required under a bare job name the reusable workflow no longer reports (the '->' shows the context to require instead). Confirm these are not produced by an unrelated inline job before removing them:"
  printf '  %s\n' "${stale[@]}"
fi
echo "Update branch protection in the same change that adopts the reusable workflows, then re-run this script."
exit 1
