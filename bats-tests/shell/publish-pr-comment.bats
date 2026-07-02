#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/publish-pr-comment/resolve.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  export GITHUB_OUTPUT
  GITHUB_OUTPUT="$(mktemp)"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
  rm -f "$GITHUB_OUTPUT"
}

# T1 — valid PR number writes pr_number to output
@test "valid PR number writes pr_number" {
  export PR_NUMBER=42
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "pr_number=42" "$GITHUB_OUTPUT"
}

# T2 — empty PR number fails
@test "empty PR number fails" {
  export PR_NUMBER=""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# T3 — null PR number fails
@test "null PR number fails" {
  export PR_NUMBER="null"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# T4 — non-numeric PR number fails
@test "non-numeric PR number fails" {
  export PR_NUMBER="abc"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

HEADER_SCRIPT="$PROJECT_ROOT/publish-pr-comment/header.sh"

# T5 — create-new='false' leaves header unchanged
@test "create-new=false leaves header unchanged" {
  export CREATE_NEW="false"
  export HEADER="my-header"
  run bash "$HEADER_SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "header=my-header" "$GITHUB_OUTPUT"
}

# T6 — create-new='true' appends -${GITHUB_RUN_ID} suffix
@test "create-new=true appends run ID suffix" {
  export CREATE_NEW="true"
  export HEADER="my-header"
  export GITHUB_RUN_ID="12345"
  run bash "$HEADER_SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "header=my-header-12345" "$GITHUB_OUTPUT"
}
