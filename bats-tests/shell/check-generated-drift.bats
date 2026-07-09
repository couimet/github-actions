#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/check-generated-drift/check.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_OUTPUT
  cd "$TEST_TEMP_DIR"
  git init
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "tracked content" > tracked-file.txt
  git add tracked-file.txt
  git commit -m "initial"

  # Ensure no env vars leak from previous tests
  unset COMMAND
  unset WORKING_DIRECTORY
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
  rm -f "$GITHUB_OUTPUT"
  cd "$PROJECT_ROOT"
}

# T1 — command succeeds, no git changes
@test "command succeeds, no git changes -> exit 0, no comment-file" {
  COMMAND='true' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  run cat "$GITHUB_OUTPUT"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}

# T2 — command succeeds, git changes detected
@test "command succeeds, git changes detected -> comment-file written" {
  COMMAND='echo "modified" >> tracked-file.txt' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "comment-file=" "$GITHUB_OUTPUT"

  # Extract the comment file path and verify its contents
  comment_file="$(grep "^comment-file=" "$GITHUB_OUTPUT" | sed 's/^comment-file=//')"
  [ -f "$comment_file" ]
  grep -q "Generated drift detected" "$comment_file"
  grep -q "tracked-file.txt" "$comment_file"
}

# T3 — COMMAND not set
@test "COMMAND not set -> exit 1 with error" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "error: COMMAND is required"
}

# T4 — WORKING_DIRECTORY set
@test "WORKING_DIRECTORY set -> command runs in subdirectory" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  WORKING_DIRECTORY="$TEST_TEMP_DIR/subdir" COMMAND='touch was-here' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/subdir/was-here" ]
}

# T5 — command creates untracked file, detected as drift
@test "command creates untracked file -> detected as drift" {
  COMMAND='echo "new content" > new-untracked-file.txt' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "comment-file=" "$GITHUB_OUTPUT"

  comment_file="$(grep "^comment-file=" "$GITHUB_OUTPUT" | sed 's/^comment-file=//')"
  [ -f "$comment_file" ]
  grep -q "Generated drift detected" "$comment_file"
  grep -q "new-untracked-file.txt" "$comment_file"
}
