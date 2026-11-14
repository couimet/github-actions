#!/usr/bin/env bash
set -euo pipefail

# Verify that every job calling a local reusable workflow grants the permissions
# that the called workflow's jobs request.
#
# GitHub validates a reusable workflow call before any job starts: the calling
# job's permissions block is a ceiling for every job in the called workflow, and
# a nested job that requests more than the ceiling rejects the whole caller file.
# Every job in that file then reports startup_failure with a duration of zero
# seconds, and the message names the caller's job key. This guard reports the
# same line, so the two agree.
#
# actionlint does not model this rule, so this check cannot live in the pin or
# lint guards.
#
# Inputs (env):
#   WORKFLOW_DIR  directory holding the workflow files
#                 (default: <repo_root>/.github/workflows)
#
# What this guard reads:
#   - A call site is a job whose `uses:` names ./.github/workflows/<file>.yml. A
#     step naming a composite action is not a call site.
#   - A caller job with no `permissions:` block, at the job level or the workflow
#     level, uses the repository default. This guard cannot read that setting, so
#     it reports the call site as not checked rather than as a pass.
#   - The caller's grant is the job-level block, or the workflow-level block when
#     the job declares none, or a scope it does not name reads as none.
#   - The requests of a called workflow are its job-level blocks plus its
#     workflow-level block, because either can exceed the caller's grant. A
#     nested job's block does not exempt the workflow-level block: GitHub reads
#     the called workflow as a whole and rejects the call with "The workflow is
#     requesting 'pull-requests: write', but is only allowed 'pull-requests:
#     none'." even when every nested job declares a block of its own.
#
# Exit codes:
#   1  no workflow file, no call site, no call site this guard can judge, a
#      layout the parser cannot read, an unknown permission level, or a call
#      site naming a file that is absent
#   2  a requested scope level is above the caller's grant

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

WORKFLOW_DIR="${WORKFLOW_DIR:-$REPO_ROOT/.github/workflows}"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
  echo "::error::verify-workflow-permissions: no workflow directory at '${WORKFLOW_DIR}'." >&2
  exit 1
fi

files="$(find "$WORKFLOW_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)"
if [[ -z "$files" ]]; then
  echo "::error::verify-workflow-permissions: '${WORKFLOW_DIR}' holds no workflow file." >&2
  exit 1
fi

# Print one record per line for one workflow file:
#   PERM<TAB>job<TAB>scope<TAB>level   a granted or a requested scope
#   USE<TAB>job<TAB>path<TAB>line      a local reusable workflow call site
# A workflow-level permissions block reports under the job name "(workflow)".
# The line a USE record carries is the line of the job key, which is the line
# GitHub names when it rejects the call.
extract_records() {
  awk '
    function trim(t) {
      sub(/^[[:space:]]+/, "", t)
      sub(/[[:space:]]+$/, "", t)
      return t
    }

    # One record per scope for a permissions value written on the same line as
    # its key. The shorthands ride the wildcard scope, because granted_level
    # matches it. A value this function cannot read reports BADPERM, and the
    # caller then exits 1 rather than reading the line as no request at all.
    function emit_inline(block, text,   t, inner, n, parts, i, item, scope, level, ok, emitted) {
      t = trim(text)
      if (t == "read-all") { printf "PERM\t%s\t*\tread\n", block; return }
      if (t == "write-all") { printf "PERM\t%s\t*\twrite\n", block; return }
      if (substr(t, 1, 1) == "{" && substr(t, length(t), 1) == "}") {
        inner = substr(t, 2, length(t) - 2)
        n = split(inner, parts, ",")
        ok = 1
        emitted = 0
        for (i = 1; i <= n; i++) {
          item = trim(parts[i])
          gsub(/[\042\047]/, "", item)
          if (item == "") continue
          if (item !~ /^[A-Za-z0-9_-]+:[[:space:]]*[A-Za-z0-9_-]+$/) { ok = 0; break }
          scope = item; sub(/:.*$/, "", scope)
          level = item; sub(/^[^:]*:[[:space:]]*/, "", level)
          printf "PERM\t%s\t%s\t%s\n", block, scope, level
          emitted = 1
        }
        if (!ok) { printf "BADPERM\t%s\t*\t%s\n", block, t; return }
        # "{}" and "{ }" both grant nothing, which is the wildcard at none.
        if (!emitted) printf "PERM\t%s\t*\tnone\n", block
        return
      }
      printf "BADPERM\t%s\t*\t%s\n", block, t
    }

    {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) next

      ind = 0
      while (ind < length($0) && substr($0, ind + 1, 1) == " ") ind++

      if (inPerms && ind <= permIndent) inPerms = 0

      if (inPerms) {
        s = substr($0, ind + 1)
        scope = s; sub(/:.*$/, "", scope)
        level = s; sub(/^[^:]*:[[:space:]]*/, "", level)
        sub(/[[:space:]]+#.*$/, "", level)
        gsub(/[\042\047]/, "", level)
        printf "PERM\t%s\t%s\t%s\n", permJob, scope, level
        next
      }

      if (ind == 0) {
        if ($0 ~ /^permissions:/) {
          rest = $0
          sub(/^permissions:[[:space:]]*/, "", rest)
          sub(/[[:space:]]+#.*$/, "", rest)
          if (rest == "") {
            permJob = "(workflow)"
            permIndent = 0
            inPerms = 1
            inJobs = 0
            job = ""
            next
          }
          emit_inline("(workflow)", rest)
          next
        }
        inJobs = ($0 ~ /^jobs:[[:space:]]*(#.*)?$/) ? 1 : 0
        job = ""
        next
      }

      if (ind == 2 && inJobs) {
        job = substr($0, 3)
        sub(/:.*$/, "", job)
        jobLine = NR
        next
      }

      if (ind == 4 && inJobs && job != "") {
        if ($0 ~ /^    permissions:/) {
          rest = $0
          sub(/^    permissions:[[:space:]]*/, "", rest)
          sub(/[[:space:]]+#.*$/, "", rest)
          if (rest == "") {
            permJob = job
            permIndent = 4
            inPerms = 1
            next
          }
          emit_inline(job, rest)
          next
        }
        if ($0 ~ /^    uses:[[:space:]]*[\042\047]?\.\/\.github\/workflows\//) {
          p = $0
          sub(/^    uses:[[:space:]]*/, "", p)
          sub(/[[:space:]]+#.*$/, "", p)
          gsub(/[\042\047]/, "", p)
          printf "USE\t%s\t%s\t%d\n", job, p, jobLine
          next
        }
      }
    }
  ' "$1"
}

# The numeric weight of a permission level, for comparison only.
level_value() {
  case "$1" in
    none) echo 0 ;;
    read | read-all) echo 1 ;;
    write | write-all) echo 2 ;;
    *) echo 0 ;;
  esac
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

perms="$work/perms.tsv"
uses="$work/uses.tsv"
: > "$perms"
: > "$uses"

raw_calls=0
parsed_calls=0

while IFS= read -r file; do
  if [[ -z "$file" ]]; then continue; fi

  # A call line the parser does not turn into a USE record would pass unread, so
  # the two counts must agree.
  raw="$(grep -cE '^[[:space:]]*uses:[[:space:]]*["'"'"']?\./\.github/workflows/' "$file" || true)"
  raw_calls=$((raw_calls + raw))

  while IFS=$'\t' read -r tag a b c; do
    if [[ -z "$tag" ]]; then continue; fi

    case "$tag" in
      BADPERM)
        echo "::error file=${file}::verify-workflow-permissions: cannot read the permissions value '${c}' on '${a}'. Use a block, '{}', 'read-all', 'write-all', or a flow mapping such as '{ contents: read }'." >&2
        exit 1
        ;;
      PERM)
        case "$c" in
          none | read | write | read-all | write-all) ;;
          *)
            echo "::error file=${file}::verify-workflow-permissions: unknown permission level '${c}' for '${a}'. Expected none, read, or write." >&2
            exit 1
            ;;
        esac
        printf '%s\t%s\t%s\t%s\n' "$file" "$a" "$b" "$c" >> "$perms"
        ;;
      USE)
        printf '%s\t%s\t%s\t%s\n' "$file" "$a" "$b" "$c" >> "$uses"
        parsed_calls=$((parsed_calls + 1))
        ;;
    esac
  done <<< "$(extract_records "$file")"
done <<< "$files"

if [[ "$raw_calls" -ne "$parsed_calls" ]]; then
  echo "::error::verify-workflow-permissions: '${WORKFLOW_DIR}' holds ${raw_calls} reusable-workflow call line(s), but this guard read ${parsed_calls}. It cannot read this layout, so it cannot verify the grants." >&2
  exit 1
fi

# The level the block named by `block` grants one scope. A scope the block never
# names is none.
granted_level() {
  local target_file="$1" block="$2" target_scope="$3"

  awk -F'\t' -v f="$target_file" -v j="$block" -v s="$target_scope" '
    function weight(x) {
      if (x == "read" || x == "read-all") return 1
      if (x == "write" || x == "write-all") return 2
      return 0
    }
    $1 == f && $2 == j && ($3 == s || $3 == "*") && weight($4) > best {
      best = weight($4)
      name = $4
    }
    END { print (name == "" ? "none" : name) }
  ' "$perms"
}

# Whether the caller names any grant at all for this job, at either level.
has_grant() {
  local target_file="$1" target_job="$2"

  awk -F'\t' -v f="$target_file" -v j="$target_job" '
    ($1 == f && ($2 == j || $2 == "(workflow)")) { found = 1; exit }
    END { print (found ? "yes" : "no") }
  ' "$perms"
}

# Whether the caller job declares a block of its own. A job block replaces the
# workflow block whole, so its presence decides which one holds the ceiling: a
# scope the job block omits reads as none, not as the workflow's value.
has_job_block() {
  local target_file="$1" target_job="$2"

  awk -F'\t' -v f="$target_file" -v j="$target_job" '
    ($1 == f && $2 == j) { found = 1; exit }
    END { print (found ? "yes" : "no") }
  ' "$perms"
}

checked=0
judged=0
unchecked=0
violations=0

while IFS=$'\t' read -r file job path line; do
  if [[ -z "$path" ]]; then continue; fi

  called="${WORKFLOW_DIR}/$(basename "$path")"
  if [[ ! -f "$called" ]]; then
    echo "::error file=${file},line=${line}::verify-workflow-permissions: job '${job}' calls '${path}', but that file does not exist." >&2
    exit 1
  fi

  if [[ "$(has_grant "$file" "$job")" == "no" ]]; then
    echo "verify-workflow-permissions: not checked: '${job}' in ${file} declares no permissions block, so the repository default applies."
    unchecked=$((unchecked + 1))
    continue
  fi

  if [[ "$(has_job_block "$file" "$job")" == "yes" ]]; then
    block="$job"
  else
    block="(workflow)"
  fi
  judged=$((judged + 1))

  while IFS=$'\t' read -r tag njob scope level; do
    if [[ "$tag" != "PERM" ]]; then continue; fi

    allowed="$(granted_level "$file" "$block" "$scope")"
    if [[ "$(level_value "$level")" -gt "$(level_value "$allowed")" ]]; then
      echo "::error file=${file},line=${line}::verify-workflow-permissions: job '${job}' grants '${scope}: ${allowed}', but the nested job '${njob}' requests '${scope}: ${level}' in ${path}. Add '${scope}: ${level}' to the '${job}' permissions block."
      violations=$((violations + 1))
    fi
    checked=$((checked + 1))
  done <<< "$(extract_records "$called")"
done <<< "$(cat "$uses")"

if [[ "$violations" -gt 0 ]]; then
  echo "::error::verify-workflow-permissions: ${violations} requested scope(s) exceed the caller's grant." >&2
  exit 2
fi

if [[ "$parsed_calls" -eq 0 ]]; then
  echo "::error::verify-workflow-permissions: no job under '${WORKFLOW_DIR}' calls a local reusable workflow, so this guard read nothing." >&2
  exit 1
fi

# A call site the guard cannot judge is not a pass. Every site reading as
# unchecked would pass here while proving nothing, which is the false pass this
# guard exists to remove. A judged site whose called workflow declares no
# permission block is a pass: it inherits the caller's, so it cannot exceed them.
if [[ "$judged" -eq 0 ]]; then
  echo "::error::verify-workflow-permissions: no call site could be judged, so this guard checked nothing." >&2
  exit 1
fi

if [[ "$unchecked" -gt 0 ]]; then
  echo "::error::verify-workflow-permissions: ${unchecked} call site(s) were not checked, as listed above." >&2
  exit 1
fi

echo "verify-workflow-permissions: ${checked} requested scope(s) across ${judged} judged call site(s) are within the caller's grants."
