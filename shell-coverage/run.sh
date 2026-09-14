#!/usr/bin/env bash
set -euo pipefail

# Run the BATS suite under kcov and consolidate its Cobertura report.
#
# Interface (all via environment):
#   TEST_DIRECTORY   directory containing .bats files (default: bats-tests/)
#   RECURSIVE        "true" to pass --recursive to BATS
#   INCLUDE_PATH     kcov --include-path; the tree kcov is allowed to instrument
#   EXCLUDE_PATTERN  kcov --exclude-pattern
#   OUTDIR           where kcov writes and where cobertura.xml lands
#   GITHUB_OUTPUT    path to the outputs file (default: /dev/null)
#
# Exit codes:
#   1  a required tool is missing from PATH
#   2  the kcov run failed
#   3  kcov produced no per-target report tree
#   4  kcov produced more than one per-target report tree
#   5  the single report tree is empty (zero <class> elements)
#
# Limits a consumer should know, all three of which are silent rather than loud:
# kcov's bash engine covers bash only, so a suite that tests zsh, python, node,
# or a compiled binary contributes no coverage for those targets and the report
# omits them; kcov does not run on macOS, so this check is CI-only; and a suite
# whose only targets are non-bash produces one valid tree with zero classes,
# which the tree-count guards below cannot catch. That last case is why the
# zero-class guard exists at all: without it the step succeeds and uploads an
# empty report, which reads in Codecov as 0% rather than as missing data.

TEST_DIRECTORY="${TEST_DIRECTORY:-bats-tests/}"
RECURSIVE="${RECURSIVE:-false}"
INCLUDE_PATH="${INCLUDE_PATH:-${GITHUB_WORKSPACE:-$PWD}}"
EXCLUDE_PATTERN="${EXCLUDE_PATTERN:-}"
OUTDIR="${OUTDIR:-coverage/}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

readonly ERR_PREREQ=1
readonly ERR_KCOV_FAILED=2
readonly ERR_NO_TREE=3
readonly ERR_MULTI_TREE=4
readonly ERR_EMPTY_TREE=5

for tool in kcov bats; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "shell-coverage error: required tool '${tool}' not found on PATH." >&2
    echo "  Run the install-kcov step first, or pass install-kcov: 'false' only" >&2
    echo "  when the tool is already available on the runner." >&2
    exit "$ERR_PREREQ"
  fi
done

# Run from the workspace root so kcov records repo-relative paths. Codecov
# matches report paths against the repository tree, so an absolute runner path
# would show as an unmatched file rather than as a failed upload.
cd "${GITHUB_WORKSPACE:-$PWD}"

# A trailing slash would make the consolidated path read "coverage//cobertura.xml"
# and the kcov-merged exclusion below miss its target.
OUTDIR="${OUTDIR%/}"
if [[ -z "$OUTDIR" ]]; then
  echo "shell-coverage error: outdir resolves to an empty path." >&2
  exit "$ERR_PREREQ"
fi

# bash sets the log redirect up before kcov runs, so the directory must exist or
# kcov is never invoked at all.
mkdir -p "$OUTDIR"

args=()
if [[ "$RECURSIVE" == "true" ]]; then args+=(--recursive); fi

# kcov's bash instrumentation is chatty on stderr, so it goes to a log and only
# the tail is surfaced on failure; otherwise CI logs flood on every run.
kcov_log="$OUTDIR/kcov.log"
set +e
kcov --clean \
  --include-path="$INCLUDE_PATH" \
  --exclude-pattern="$EXCLUDE_PATTERN" \
  "$OUTDIR" \
  bats ${args[@]+"${args[@]}"} "$TEST_DIRECTORY" >"$kcov_log" 2>&1
kcov_exit=$?
set -e

if [[ "$kcov_exit" -ne 0 ]]; then
  echo "shell-coverage error: the kcov run failed (exit ${kcov_exit}); last log lines follow." >&2
  if [[ -f "$kcov_log" ]]; then
    tail -n 50 "$kcov_log" >&2 || true
  else
    echo "  (the log at ${kcov_log} is gone, so the failing output is unavailable)" >&2
  fi
  exit "$ERR_KCOV_FAILED"
fi

# A previous run's consolidated copy must not count as a fresh report tree on a
# repeat run into the same outdir, or the count below trips its own multi-tree
# guard.
rm -f "$OUTDIR/cobertura.xml"

# kcov writes one report tree per traced binary, at <outdir>/<target>.<hash>/.
# <outdir>/kcov-merged/ is kcov's own merged output rather than a per-target
# tree, so it is excluded here; counting it was observed to report 3 trees where
# the real answer was 2.
trees() {
  find "$OUTDIR" -name cobertura.xml -not -path "${OUTDIR}/kcov-merged/*" "$@"
}

report_count="$(trees | wc -l | tr -d ' ')"

if [[ "$report_count" -eq 0 ]]; then
  echo "shell-coverage error: kcov produced no cobertura.xml under ${OUTDIR}." >&2
  echo "  Nothing was traced. Check that '${TEST_DIRECTORY}' holds .bats files" >&2
  echo "  and that the run log has no error:" >&2
  echo "    ${kcov_log}" >&2
  exit "$ERR_NO_TREE"
fi

if [[ "$report_count" -gt 1 ]]; then
  echo "shell-coverage error: expected one per-target report tree but found ${report_count} under ${OUTDIR}." >&2
  trees >&2
  echo "  This action runs kcov once, so more than one tree means the outdir was" >&2
  echo "  reused by another kcov invocation tracing a different program." >&2
  echo "  kcov can merge them natively:" >&2
  echo "    kcov --merge ${OUTDIR}/merged <kcov-dirs...>" >&2
  exit "$ERR_MULTI_TREE"
fi

report_path="$(trees -print -quit)"
class_count="$(grep -c '<class' "$report_path" || true)"

if [[ "$class_count" -eq 0 ]]; then
  echo "shell-coverage error: the report tree under ${OUTDIR} has no <class> elements." >&2
  echo "  kcov's bash engine instruments bash only, so a suite whose only targets" >&2
  echo "  are zsh, python, node, or a compiled binary produces a valid but empty" >&2
  echo "  report. Uploading it would read in Codecov as 0% rather than as absent." >&2
  echo "  Effective include-path: ${INCLUDE_PATH}" >&2
  echo "  Effective exclude-pattern: ${EXCLUDE_PATTERN}" >&2
  echo "  Widen include-path or narrow exclude-pattern if a bash script was missed." >&2
  exit "$ERR_EMPTY_TREE"
fi

cp "$report_path" "$OUTDIR/cobertura.xml"
echo "report-path=${OUTDIR}/cobertura.xml" >> "$GITHUB_OUTPUT"
printf '%s\n' "${OUTDIR}/cobertura.xml"
