#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-workflow-permissions.sh"

# write_caller <permissions-block> <called-path>
#
# Builds a one-job call site. The block is written as-is and must carry its own
# indentation, so a test can leave it empty to stand in for a job that declares
# no permissions at all. The job key sits on line 2 of every caller, which the
# assertions below name.
write_caller() {
  mkdir -p "$WORKFLOW_DIR"
  cat > "$WORKFLOW_DIR/caller.yml" << CALLER
name: Caller
jobs:
  caller:
    uses: ${2}
${1}
CALLER
}

# write_called <job-permissions-block> <workflow-permissions-block>
#
# Builds a called workflow holding one job named "nested". Both blocks are
# optional and written as-is, so a test can pin either shape.
write_called() {
  mkdir -p "$WORKFLOW_DIR"
  cat > "$WORKFLOW_DIR/called.yml" << CALLED
name: Called
on:
  workflow_call:
${2}
jobs:
  nested:
    runs-on: ubuntu-latest
${1}
    steps:
      - run: echo "hi"
CALLED
}

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  WORKFLOW_DIR="$TEST_TEMP_DIR/workflows"
  export WORKFLOW_DIR
  mkdir -p "$WORKFLOW_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- Within the grant -------------------------------------------------------

@test "caller grants what the nested job requests -> exits 0" {
  write_caller "    permissions:
      contents: read
      pull-requests: write" "./.github/workflows/called.yml"
  write_called "    permissions:
      contents: read
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 requested scope(s) across 1 judged call site(s)"* ]]
}

# A nested job that declares no block inherits the caller's, so it cannot exceed
# them and the call site owes nothing. Nothing is compared, yet the site is a
# pass rather than a hole, so the summary reports the zero.
@test "nested job declares no permissions -> exits 0 with nothing to compare" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 requested scope(s) across 1 judged call site(s)"* ]]
}

# --- Above the grant --------------------------------------------------------

@test "nested job requests a higher level -> exits 2, naming the caller's job line" {
  write_caller "    permissions:
      contents: read
      pull-requests: read" "./.github/workflows/called.yml"
  write_called "    permissions:
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"file=${WORKFLOW_DIR}/caller.yml,line=3::"* ]]
  [[ "$output" == *"grants 'pull-requests: read', but the nested job 'nested' requests 'pull-requests: write'"* ]]
}

# This is the shape that broke CI: the caller omits the scope, so it reads as
# none, and the nested job's request is rejected before any job starts.
@test "caller omits the requested scope -> exits 2, naming the scope" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions:
      contents: read
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"grants 'pull-requests: none'"* ]]
  [[ "$output" == *"1 requested scope(s) exceed the caller's grant"* ]]
}

@test "nested job requests write where the caller grants none -> exits 2" {
  write_caller "    permissions:
      contents: none" "./.github/workflows/called.yml"
  write_called "    permissions:
      contents: read" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"grants 'contents: none'"* ]]
}

# --- The workflow-level caller block ----------------------------------------

# A caller job with no block of its own falls back to its workflow's block, which
# is what decides the ceiling in that case.
@test "caller job falls back to its workflow-level block -> exits 0 when covered" {
  mkdir -p "$WORKFLOW_DIR"
  cat > "$WORKFLOW_DIR/caller.yml" << 'CALLER'
name: Caller
permissions:
  contents: read
  pull-requests: write
jobs:
  caller:
    uses: ./.github/workflows/called.yml
CALLER
  write_called "    permissions:
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "caller job falls back to its workflow-level block -> exits 2 when short" {
  mkdir -p "$WORKFLOW_DIR"
  cat > "$WORKFLOW_DIR/caller.yml" << 'CALLER'
name: Caller
permissions:
  contents: read
jobs:
  caller:
    uses: ./.github/workflows/called.yml
CALLER
  write_called "    permissions:
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"grants 'pull-requests: none'"* ]]
}

# A called workflow's own workflow-level block is a ceiling too, so it is read
# as a request.
@test "called workflow-level block above the grant -> exits 2" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "" "permissions:
  pull-requests: write"

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nested job '(workflow)' requests 'pull-requests: write'"* ]]
}

# --- The call site this guard cannot judge ----------------------------------

# Without a block at either level the repository default decides, which this
# guard cannot read, so it says so rather than passing quietly.
@test "caller declares no permissions at all -> reports the site as not checked" {
  write_caller "" "./.github/workflows/called.yml"
  write_called "    permissions:
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not checked: 'caller'"* ]]
  [[ "$output" == *"no call site could be judged"* ]]
}

@test "an unchecked site beside a checked one -> exits 1" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions:
      contents: read" ""

  cat > "$WORKFLOW_DIR/second.yml" << 'SECOND'
name: Second
jobs:
  second:
    uses: ./.github/workflows/called.yml
SECOND

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 call site(s) were not checked"* ]]
}

# --- Inline permissions values ----------------------------------------------

# Every value below is valid YAML for the `permissions` key. Before the parser
# read them, each one emitted no record at all, so a called workflow that used
# one passed with zero scopes compared.

@test "nested job '{}' grants nothing -> exits 0" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions: {}" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "nested job 'read-all' above a narrow grant -> exits 2" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions: read-all" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requests '*: read'"* ]]
}

@test "nested job 'write-all' above the grant -> exits 2" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions: write-all" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requests '*: write'"* ]]
}

@test "nested job flow mapping above the grant -> exits 2" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions: { contents: read, pull-requests: write }" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requests 'pull-requests: write'"* ]]
}

@test "caller 'read-all' covers a nested read request -> exits 0" {
  write_caller "    permissions: read-all" "./.github/workflows/called.yml"
  write_called "    permissions:
      contents: read" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "caller 'write-all' covers a nested write request -> exits 0" {
  write_caller "    permissions: write-all" "./.github/workflows/called.yml"
  write_called "    permissions:
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "caller '{}' leaves a nested request above the grant -> exits 2" {
  write_caller "    permissions: {}" "./.github/workflows/called.yml"
  write_called "    permissions:
      pull-requests: write" ""

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

# A flow mapping is a grant, so the call site is judged and not reported as one
# the guard could not check.
@test "caller flow mapping covers a nested request -> exits 0" {
  write_caller "    permissions: { contents: read }" "./.github/workflows/called.yml"
  write_called "    permissions:
      contents: read" ""

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "called workflow-level 'read-all' above the grant -> exits 2" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "" "permissions: read-all"

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nested job '(workflow)' requests '*: read'"* ]]
}

@test "an unreadable permissions value -> exits 1" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions: contents" ""

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the permissions value 'contents'"* ]]
}

# --- Misconfiguration -------------------------------------------------------

@test "no workflow directory -> exits 1" {
  WORKFLOW_DIR="$TEST_TEMP_DIR/absent"

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no workflow directory at"* ]]
}

@test "no call site in the directory -> exits 1 rather than passing quietly" {
  write_called "    permissions:
      contents: read" ""

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"calls a local reusable workflow, so this guard read nothing"* ]]
}

@test "call site names a file that is absent -> exits 1" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/absent.yml"

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"that file does not exist"* ]]
}

@test "unknown permission level -> exits 1 rather than comparing it" {
  write_caller "    permissions:
      contents: read" "./.github/workflows/called.yml"
  write_called "    permissions:
      pull-requests: admin" ""

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown permission level 'admin'"* ]]
}

# A call line the parser does not turn into a record would pass unread, so the
# guard fails when its own count disagrees with the file.
@test "a call line the parser cannot read -> exits 1" {
  mkdir -p "$WORKFLOW_DIR"
  cat > "$WORKFLOW_DIR/caller.yml" << 'CALLER'
name: Caller
jobs:
  caller:
    permissions:
      contents: read
    steps:
      - name: not a job-level call
        uses: ./.github/workflows/called.yml
CALLER
  write_called "    permissions:
      contents: read" ""

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read this layout"* ]]
}
