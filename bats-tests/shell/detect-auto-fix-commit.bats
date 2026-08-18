#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/detect-auto-fix-commit/detect.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty --quiet -m "chore: auto-fix [skip ci]"

  GITHUB_OUTPUT="$TEST_TEMP_DIR/output.txt"
  export GITHUB_OUTPUT
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- detection of auto-fix commits ---

@test "head commit subject matches AUTO_FIX_COMMIT_MESSAGE -> outputs is-auto-fix=true" {
  run env AUTO_FIX_COMMIT_MESSAGE="chore: auto-fix [skip ci]" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "is-auto-fix=true" "$GITHUB_OUTPUT"
}

@test "head commit subject differs -> outputs is-auto-fix=false" {
  git commit --allow-empty --quiet -m "feat: other"
  run env AUTO_FIX_COMMIT_MESSAGE="chore: auto-fix [skip ci]" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "is-auto-fix=false" "$GITHUB_OUTPUT"
}

@test "missing AUTO_FIX_COMMIT_MESSAGE fails with an error message" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "error: AUTO_FIX_COMMIT_MESSAGE is required"
}
