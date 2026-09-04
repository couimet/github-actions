#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/required-checks.sh"
FIXTURES="$PROJECT_ROOT/bats-tests/fixtures/required-checks"

# The multi fixture mirrors the rabbit-maximizer incident shape: caller job "ci"
# calls typescript-ci-checks and caller job "shell-ci-checks" calls
# shell-ci-checks. contexts-matching.txt holds exactly the contexts those two
# workflows produce; contexts-stale.txt drops the shell-ci-checks contexts (and
# ci / auto-fix) but keeps bare "shellcheck" and "bats-test" as required.

@test "matching required checks for discovered callers -> success" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/multi" \
    MOCK_CONTEXTS_FILE="$FIXTURES/contexts-matching.txt" \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
}

@test "stale bare contexts and missing checks -> failure with replacement suggestions" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/multi" \
    MOCK_CONTEXTS_FILE="$FIXTURES/contexts-stale.txt" \
    bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "MISSING"
  echo "$output" | grep -q "ci / auto-fix"
  echo "$output" | grep -q "shell-ci-checks / shellcheck"
  echo "$output" | grep -q "shell-ci-checks / bats-test"
  echo "$output" | grep -q "STALE"
  echo "$output" | grep -q "shellcheck -> shell-ci-checks / shellcheck"
  echo "$output" | grep -q "bats-test -> shell-ci-checks / bats-test"
}

@test "a bare required check with no reusable-workflow replacement is not reported stale" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/multi" \
    MOCK_CONTEXTS_FILE="$FIXTURES/contexts-matching.txt" \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
}

@test "named caller job becomes the check prefix" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/named" \
    PRINT_ONLY=1 \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "TypeScript Gate / format"
  echo "$output" | grep -q "TypeScript Gate / check-todos"
  [ "$(printf '%s\n' "$output" | grep -c 'TypeScript Gate / ')" -eq 9 ]
}

@test "PRINT_ONLY prints expected contexts sorted and unique without gh" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/multi" \
    PRINT_ONLY=1 \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ci / format"
  echo "$output" | grep -q "ci / auto-fix"
  echo "$output" | grep -q "shell-ci-checks / shellcheck"
  # 9 typescript-ci-checks contexts + 2 shell-ci-checks contexts
  [ "$(printf '%s\n' "$output" | grep -c ' / ')" -eq 11 ]
}

@test "DISABLED_JOBS drops toggled-off workflow jobs from the expected set" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/named" \
    DISABLED_JOBS="typescript-ci-checks:auto-fix typescript-ci-checks:guard-versions" \
    PRINT_ONLY=1 \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "TypeScript Gate / format"
  ! echo "$output" | grep -q "auto-fix"
  ! echo "$output" | grep -q "guard-versions"
  [ "$(printf '%s\n' "$output" | grep -c 'TypeScript Gate / ')" -eq 7 ]
}

@test "CALLER_JOBS override bypasses workflow scanning" {
  run env \
    WORKFLOWS_DIR="/nonexistent" \
    CALLER_JOBS="ci=typescript-ci-checks" \
    DISABLED_JOBS="typescript-ci-checks:markdownlint typescript-ci-checks:auto-fix" \
    PRINT_ONLY=1 \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ci / format"
  ! echo "$output" | grep -q "ci / markdownlint"
  [ "$(printf '%s\n' "$output" | grep -c 'ci / ')" -eq 7 ]
}

@test "PRINT_ONLY with no caller jobs -> exit 0 with no output" {
  mkdir -p "$TEST_TEMP_DIR/wf"
  printf '%s\n' "jobs:" "  build:" "    runs-on: ubuntu-latest" > "$TEST_TEMP_DIR/wf/plain.yml"

  run env \
    WORKFLOWS_DIR="$TEST_TEMP_DIR/wf" \
    PRINT_ONLY=1 \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no reusable-workflow caller jobs -> notice and exit 0" {
  mkdir -p "$TEST_TEMP_DIR/wf"
  printf '%s\n' \
    "jobs:" \
    "  build:" \
    "    runs-on: ubuntu-latest" \
    "    steps:" \
    "      - run: echo hi" > "$TEST_TEMP_DIR/wf/plain.yml"

  run env WORKFLOWS_DIR="$TEST_TEMP_DIR/wf" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No caller jobs"
}

@test "missing WORKFLOWS_DIR -> usage error" {
  run env WORKFLOWS_DIR="/nonexistent" bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "WORKFLOWS_DIR not found"
}

@test "MOCK_CONTEXTS_FILE not found -> exit 2" {
  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/multi" \
    MOCK_CONTEXTS_FILE="/nonexistent/contexts.txt" \
    bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "MOCK_CONTEXTS_FILE not found"
}

@test "exact missing-check scenario: only auto-fix missing -> failure naming just it" {
  # Contexts that match everything except ci / auto-fix must list only auto-fix.
  printf '%s\n' \
    "ci / format" \
    "ci / lint" \
    "ci / markdownlint" \
    "ci / build" \
    "ci / test" \
    "ci / guard-versions" \
    "ci / check-no-prerelease-deps" \
    "ci / check-todos" \
    "shell-ci-checks / shellcheck" \
    "shell-ci-checks / bats-test" > "$TEST_TEMP_DIR/ctx.txt"

  run env \
    WORKFLOWS_DIR="$FIXTURES/workflows/multi" \
    MOCK_CONTEXTS_FILE="$TEST_TEMP_DIR/ctx.txt" \
    bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "MISSING"
  echo "$output" | grep -q "ci / auto-fix"
  ! echo "$output" | grep -q "ci / format"
  ! echo "$output" | grep -q "STALE"
}
