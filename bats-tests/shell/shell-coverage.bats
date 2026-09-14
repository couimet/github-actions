#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/shell-coverage/run.sh"

# The script drives kcov and BATS, neither of which is installed on every
# machine that runs this suite, so both are stubbed. The kcov stub builds the
# report tree the real kcov would write, under the control of STUB_* variables
# so each guard can be exercised.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  WORKSPACE="$TEST_TEMP_DIR/workspace"
  STUB_BIN_DIR="$TEST_TEMP_DIR/bin"
  STUB_LOG_DIR="$TEST_TEMP_DIR/logs"
  export WORKSPACE STUB_BIN_DIR STUB_LOG_DIR
  mkdir -p "$WORKSPACE" "$STUB_BIN_DIR" "$STUB_LOG_DIR"

  export GITHUB_WORKSPACE="$WORKSPACE"
  export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output"
  export TEST_DIRECTORY="bats-tests/"
  export OUTDIR="coverage"
  export INCLUDE_PATH="$WORKSPACE"
  export EXCLUDE_PATTERN="bats-tests/,.git/"

  # Defaults: one tree holding one class, a successful run.
  export STUB_KCOV_EXIT=0
  export STUB_TREE_COUNT=1
  export STUB_CLASS_COUNT=1
  export STUB_WRITE_MERGED=false

  stub_kcov
  stub_bats

  # Pin PATH to the stub dir plus the system binaries the script needs. A
  # developer machine with the real kcov or BATS installed would otherwise let
  # the script's prerequisite check pass against the real tool, bypassing the
  # stubs and turning these tests into passes that assert nothing. The stub dir
  # comes first, so pinning alone is enough; the check below proves it held.
  export PATH="$STUB_BIN_DIR:/usr/bin:/bin"

  # Fail loudly rather than skip. A skip here would silently turn every guard
  # test below into a no-op that still reports green.
  local tool resolved
  for tool in kcov bats; do
    resolved="$(command -v "$tool" || true)"
    if [[ "$resolved" != "$STUB_BIN_DIR/$tool" ]]; then
      echo "${tool} resolves to '${resolved:-nothing}' instead of the suite stub at $STUB_BIN_DIR/$tool" >&2
      return 1
    fi
  done
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# The kcov stub records its arguments, then writes STUB_TREE_COUNT report trees
# plus, when asked, the kcov-merged report the real kcov emits alongside them.
stub_kcov() {
  cat > "$STUB_BIN_DIR/kcov" << 'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG_DIR/kcov.log"

# kcov's first non-option argument is the output directory; everything after it
# is the program to trace plus that program's arguments. Real kcov runs that
# program as its child, so the stub does too, which is what puts a line in the
# bats log for the argument-passing tests to assert against.
outdir=""
program=()
seen_outdir=0
for arg in "$@"; do
  if [[ "$seen_outdir" -eq 0 ]]; then
    case "$arg" in
      --*) continue ;;
      *) outdir="$arg"; seen_outdir=1; continue ;;
    esac
  fi
  program+=("$arg")
done

if [[ "${#program[@]}" -gt 0 ]]; then
  "${program[@]}" > /dev/null 2>&1 || true
fi

if [[ -f "$STUB_LOG_DIR/kcov-writes-log" ]]; then
  echo "kcov: tracing (simulated)" >&2
fi

if [[ "${STUB_KCOV_EXIT:-0}" -ne 0 ]]; then
  echo "kcov: simulated failure" >&2
  exit "$STUB_KCOV_EXIT"
fi

i=1
while [[ "$i" -le "${STUB_TREE_COUNT:-1}" ]]; do
  dir="$outdir/target${i}.deadbeef"
  mkdir -p "$dir"
  {
    printf '<coverage line-rate="1.0">\n  <packages>\n'
    j=1
    while [[ "$j" -le "${STUB_CLASS_COUNT:-1}" ]]; do
      printf '    <class name="target_sh__%s" filename="scripts/target%s.sh" />\n' "$j" "$j"
      j=$((j + 1))
    done
    printf '  </packages>\n</coverage>\n'
  } > "$dir/cobertura.xml"
  i=$((i + 1))
done

if [[ "${STUB_WRITE_MERGED:-false}" == "true" ]]; then
  mkdir -p "$outdir/kcov-merged"
  printf '<coverage><packages></packages></coverage>\n' > "$outdir/kcov-merged/cobertura.xml"
fi
exit 0
STUB
  chmod +x "$STUB_BIN_DIR/kcov"
}

stub_bats() {
  cat > "$STUB_BIN_DIR/bats" << 'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG_DIR/bats.log"
exit 0
STUB
  chmod +x "$STUB_BIN_DIR/bats"
}

@test "happy path -> consolidates the nested report and writes report-path" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$WORKSPACE/coverage/cobertura.xml" ]
  grep -q 'report-path=coverage/cobertura.xml' "$GITHUB_OUTPUT"
  [[ "$output" == *"coverage/cobertura.xml"* ]]
}

@test "happy path -> passes --include-path, --exclude-pattern, and the outdir to kcov" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "--include-path=$WORKSPACE" "$STUB_LOG_DIR/kcov.log"
  grep -q -- "--exclude-pattern=bats-tests/,.git/" "$STUB_LOG_DIR/kcov.log"
  grep -q -- "--clean" "$STUB_LOG_DIR/kcov.log"
}

@test "recursive true -> passes --recursive through to bats" {
  export RECURSIVE=true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STUB_LOG_DIR/bats.log" ]
  grep -q -- "--recursive" "$STUB_LOG_DIR/bats.log"
}

# The file assertion is load-bearing: a negative grep passes on a missing file,
# so without it this test would report green whenever bats was never run.
@test "recursive false -> omits --recursive" {
  export RECURSIVE=false
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STUB_LOG_DIR/bats.log" ]
  ! grep -q -- "--recursive" "$STUB_LOG_DIR/bats.log"
}

@test "test directory -> passed to bats as a single argument" {
  export TEST_DIRECTORY="bats-tests/"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STUB_LOG_DIR/bats.log" ]
  grep -qE -- "--recursive bats-tests/$|bats-tests/$" "$STUB_LOG_DIR/bats.log"
}

# --- Prerequisite guard -----------------------------------------------------

@test "kcov missing from PATH -> exits 1 naming the tool" {
  rm -f "$STUB_BIN_DIR/kcov"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "required tool 'kcov' not found" ]]
}

@test "bats missing from PATH -> exits 1 naming the tool" {
  rm -f "$STUB_BIN_DIR/bats"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "required tool 'bats' not found" ]]
}

# --- kcov failure -----------------------------------------------------------

@test "kcov non-zero exit -> exits 2 and surfaces the log tail" {
  export STUB_KCOV_EXIT=1
  export STUB_WRITE_LOG=1
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "the kcov run failed" ]]
}

# --- Zero-tree guard --------------------------------------------------------

@test "zero report trees -> exits 3" {
  export STUB_TREE_COUNT=0
  run bash "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" =~ "no cobertura.xml" ]]
  [ ! -f "$WORKSPACE/coverage/cobertura.xml" ]
}

# --- Multi-tree guard -------------------------------------------------------

@test "two report trees -> exits 4 and names kcov --merge" {
  export STUB_TREE_COUNT=2
  run bash "$SCRIPT"
  [ "$status" -eq 4 ]
  [[ "$output" =~ "found 2" ]]
  [[ "$output" =~ "kcov --merge" ]]
}

# kcov writes its own merged report into the outdir. A naive count treats it as
# a third tree and misreports the situation, so it must be excluded.
@test "kcov-merged report -> not counted as a per-target tree" {
  export STUB_WRITE_MERGED=true
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$WORKSPACE/coverage/cobertura.xml" ]
}

@test "kcov-merged report beside two real trees -> still exits 4, not 5" {
  export STUB_TREE_COUNT=2
  export STUB_WRITE_MERGED=true
  run bash "$SCRIPT"
  [ "$status" -eq 4 ]
  [[ "$output" =~ "found 2" ]]
}

# --- Zero-class guard -------------------------------------------------------

# A suite whose only targets are non-bash yields one valid tree with no classes.
# The tree-count guards cannot see it, so without this guard the step succeeds
# and uploads an empty report that reads as 0% in Codecov.
@test "report tree with zero classes -> exits 5 and names the effective paths" {
  export STUB_CLASS_COUNT=0
  run bash "$SCRIPT"
  [ "$status" -eq 5 ]
  [[ "$output" =~ "no <class> elements" ]]
  [[ "$output" =~ "Effective include-path: $WORKSPACE" ]]
  [[ "$output" =~ "Effective exclude-pattern: bats-tests/,.git/" ]]
  [ ! -f "$WORKSPACE/coverage/cobertura.xml" ]
}

# --- Repeat runs ------------------------------------------------------------

# A previous run's consolidated copy sits directly in the outdir. Left in place
# it counts as an extra tree and the multi-tree guard misfires on the next run.
@test "stale consolidated report -> removed, so a repeat run still exits 0" {
  mkdir -p "$WORKSPACE/coverage"
  printf '<coverage><packages><class name="stale" /></packages></coverage>\n' \
    > "$WORKSPACE/coverage/cobertura.xml"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'class name="target_sh__1"' "$WORKSPACE/coverage/cobertura.xml"
}

@test "outdir with a trailing slash -> consolidated path has no double slash" {
  export OUTDIR="coverage/"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'report-path=coverage/cobertura.xml' "$GITHUB_OUTPUT"
}

@test "outdir created when missing -> kcov is still invoked" {
  [ ! -d "$WORKSPACE/coverage" ]
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "coverage" "$STUB_LOG_DIR/kcov.log"
}

@test "GITHUB_OUTPUT unset -> still exits 0 and prints the report path" {
  run env -u GITHUB_OUTPUT bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage/cobertura.xml"* ]]
}
