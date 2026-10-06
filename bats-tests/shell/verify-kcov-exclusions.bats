#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-kcov-exclusions.sh"

# The markers under test. This file writes them out, so it also has to survive
# them: kcov keeps one region counter per file and matches a marker as a raw
# substring, so every line here that names a region marker names both halves of
# the pair and the counter returns to zero.
LINE_MARKER="kcov-exclude-line"
REGION_MARKER="kcov-exclude-start:kcov-exclude-end"

# The fixture target: a marked single line on line 2, and a marked region across
# lines 4 to 6. The assertions below name those line numbers, so the fixture must
# not move.
write_target() {
  cat > "$WORKSPACE/scripts/target.sh" << 'TARGET'
#!/usr/bin/env bash
echo "one" # kcov-exclude-line
echo "before"
# kcov-exclude-start
echo "inside"
# kcov-exclude-end
echo "after"
TARGET
}

# A target that carries the line marker only, on line 2. A run against this file
# leaves the region marker with nothing to match.
write_line_only_target() {
  cat > "$WORKSPACE/scripts/target.sh" << 'TARGET'
#!/usr/bin/env bash
echo "one" # kcov-exclude-line
echo "two"
TARGET
}

# A target that carries the region pair only, across lines 2 to 4. A run against
# this file leaves the line marker with nothing to match. The pair stays balanced
# so this file's own region counter returns to zero, per the note above.
write_region_only_target() {
  cat > "$WORKSPACE/scripts/target.sh" << 'TARGET'
#!/usr/bin/env bash
# kcov-exclude-start
echo "inside"
# kcov-exclude-end
TARGET
}

# write_report <source-dir> <line-entries>
#
# The source element is what the guard resolves measured paths against, so it
# stands in for the common prefix kcov records at the top of a real report.
write_report() {
  mkdir -p "$(dirname "$REPORT_PATH")"
  cat > "$REPORT_PATH" << REPORT
<?xml version="1.0" ?>
<coverage line-rate="1.0" lines-covered="0" lines-valid="0">
  <sources>
    <source>$1/</source>
  </sources>
  <packages>
    <package name="bats" line-rate="1.0">
      <classes>
        <class name="target_sh__0" filename="scripts/target.sh" line-rate="1.0">
          <lines>
$2
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
REPORT
}

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  WORKSPACE="$TEST_TEMP_DIR/workspace"
  export WORKSPACE
  mkdir -p "$WORKSPACE/scripts"

  export REPORT_PATH="$WORKSPACE/coverage/cobertura.xml"
  export EXCLUDE_LINE="$LINE_MARKER"
  export EXCLUDE_REGION="$REGION_MARKER"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- The happy path ---------------------------------------------------------

@test "every marked line absent from the report -> exits 0" {
  write_target
  write_report "$WORKSPACE" '            <line number="3" hits="1"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 marked line(s) across 1 measured file(s)"* ]]
}

# kcov removes an excluded line from the report rather than reporting it at zero,
# so a marked line that is present but did execute is not a phantom miss.
@test "marked line present with hits -> exits 0" {
  write_target
  write_report "$WORKSPACE" '            <line number="2" hits="7"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# --- The failure this guard exists to catch ---------------------------------

@test "marked line present with zero hits -> exits 2, naming the file and line" {
  write_target
  write_report "$WORKSPACE" '            <line number="2" hits="0"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"::error file=${WORKSPACE}/scripts/target.sh,line=2::"* ]]
}

@test "region line present with zero hits -> exits 2, naming that line" {
  write_target
  write_report "$WORKSPACE" '            <line number="5" hits="0"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *",line=5::"* ]]
}

@test "several marked lines uncovered -> counts every one of them" {
  write_target
  write_report "$WORKSPACE" '            <line number="2" hits="0"/>
            <line number="4" hits="0"/>
            <line number="6" hits="0"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"3 marked line(s) still read as uncovered"* ]]
}

# --- Misconfiguration -------------------------------------------------------

@test "report missing -> exits 1, naming the path it looked for" {
  write_target

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no report at '${REPORT_PATH}'"* ]]
}

@test "EXCLUDE_LINE unset -> exits 1 rather than passing quietly" {
  write_target
  write_report "$WORKSPACE" '            <line number="3" hits="1"/>'

  run env -u EXCLUDE_LINE bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXCLUDE_LINE is unset"* ]]
}

@test "EXCLUDE_REGION unset -> exits 1 rather than passing quietly" {
  write_target
  write_report "$WORKSPACE" '            <line number="3" hits="1"/>'

  run env -u EXCLUDE_REGION bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXCLUDE_REGION is unset"* ]]
}

@test "region marker without a colon -> exits 1" {
  write_target
  write_report "$WORKSPACE" '            <line number="3" hits="1"/>'
  export EXCLUDE_REGION="$LINE_MARKER"

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must read"* ]]
}

@test "region marker with an empty half -> exits 1" {
  write_target
  write_report "$WORKSPACE" '            <line number="3" hits="1"/>'
  export EXCLUDE_REGION="kcov-exclude-start:"

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"two non-empty markers"* ]]
}

@test "report with no measured line -> exits 1" {
  write_target
  write_report "$WORKSPACE" ''

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"holds no measured line"* ]]
}

# A base mismatch would otherwise pass green while checking nothing, because no
# file would resolve and so no marked line would ever be compared.
@test "measured paths resolve nowhere -> exits 1 instead of reporting green" {
  write_target
  write_report "$TEST_TEMP_DIR/absent" '            <line number="2" hits="0"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"none resolve under"* ]]
}

# --- An enabled marker that matches nothing ---------------------------------

# A marker that matches no measured line skips its own comparison, so the run
# would pass green while proving nothing about that exclusion. That is the same
# false pass the base check above closes for a path mismatch.
@test "line marker matches no measured line -> exits 1, naming EXCLUDE_LINE" {
  write_region_only_target
  write_report "$WORKSPACE" '            <line number="1" hits="1"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXCLUDE_LINE ('${LINE_MARKER}') matches no line"* ]]
}

@test "region pair matches no measured line -> exits 1, naming EXCLUDE_REGION" {
  write_line_only_target
  write_report "$WORKSPACE" '            <line number="3" hits="1"/>'

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXCLUDE_REGION ('${REGION_MARKER}') matches no line"* ]]
}

# The new check fires per marker, so an empty marker keeps its meaning as an
# opt-out: the live region pair alone carries the run.
@test "line marker off beside a live region pair -> exits 0" {
  write_region_only_target
  write_report "$WORKSPACE" '            <line number="1" hits="1"/>'
  export EXCLUDE_LINE=""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 marked line(s) across 1 measured file(s)"* ]]
}

# --- The exclusions turned off ----------------------------------------------

# An empty marker turns its exclusion off, which is a supported setting. The
# report is left missing on purpose: a guard that read it anyway would fail here.
@test "both markers empty -> exits 0 without reading the report" {
  export EXCLUDE_LINE=""
  export EXCLUDE_REGION=""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"both exclusions are off"* ]]
}
