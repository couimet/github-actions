#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/check-todos/check.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export GITHUB_OUTPUT
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_STEP_SUMMARY
  GITHUB_STEP_SUMMARY="$(mktemp)"
  export SCAN_PATH="$TEST_TEMP_DIR"
  export BASE_REF=""
  export FILE_EXTENSIONS="ts,js,py,sh,md"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
  rm -f "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY"
}

# T1 — no files in scan path
@test "no files -> count 0" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=0" "$GITHUB_OUTPUT"
}

# T2 — TODOs and FIXMEs both counted
@test "TODOs and FIXMEs are counted" {
  echo "TODO: fix this" > "$TEST_TEMP_DIR/app.ts"
  echo "FIXME: broken" > "$TEST_TEMP_DIR/lib.js"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=2" "$GITHUB_OUTPUT"
}

# T3 — multiple TODO/FIXME on same line counted once per line
@test "multiple matches counted per line" {
  echo "TODO: fix this and FIXME: that" > "$TEST_TEMP_DIR/app.ts"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=1" "$GITHUB_OUTPUT"
}

# T4 — excluded directories are skipped
@test "excluded directories are skipped" {
  mkdir -p "$TEST_TEMP_DIR/node_modules/pkg"
  echo "TODO: fix this" > "$TEST_TEMP_DIR/app.ts"
  echo "FIXME: vendored bug" > "$TEST_TEMP_DIR/node_modules/pkg/index.js"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=1" "$GITHUB_OUTPUT"
}

# T5 — unmatched extensions are skipped
@test "unmatched extensions are skipped" {
  echo "TODO: fix this" > "$TEST_TEMP_DIR/app.txt"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=0" "$GITHUB_OUTPUT"
}

# T6 — multiple extensions match
@test "multiple extensions match" {
  echo "TODO: fix this" > "$TEST_TEMP_DIR/app.ts"
  echo "FIXME: broken" > "$TEST_TEMP_DIR/script.py"
  echo "TODO: refactor" > "$TEST_TEMP_DIR/docs.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=3" "$GITHUB_OUTPUT"
}

# T7 — non-PR mode writes summary with no delta
@test "non-PR mode writes summary" {
  echo "TODO: fix" > "$TEST_TEMP_DIR/app.ts"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "TODO/FIXME Analysis" "$GITHUB_STEP_SUMMARY"
  grep -q "No base branch comparison" "$GITHUB_STEP_SUMMARY"
}

# T8 — PR mode computes delta (more TODOs on current)
@test "PR delta with more TODOs -> positive delta" {
  ORIGIN_DIR="$(mktemp -d)"
  WORK_DIR="$(mktemp -d)"

  git init --bare "$ORIGIN_DIR"
  git clone "$ORIGIN_DIR" "$WORK_DIR"
  cd "$WORK_DIR"
  git config user.email "test@example.com"
  git config user.name "Test"
  git config init.defaultBranch main

  # Base commit: 1 TODO
  echo "TODO: old" > app.ts
  git add app.ts
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit -m "initial"
  git branch -m main
  git push origin main

  # Current state: add another TODO
  echo "FIXME: new" > lib.ts

  export GITHUB_OUTPUT
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_STEP_SUMMARY
  GITHUB_STEP_SUMMARY="$(mktemp)"
  export SCAN_PATH="."
  export BASE_REF="main"
  export FILE_EXTENSIONS="ts,js"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=2" "$GITHUB_OUTPUT"
  grep -q "todo-delta=1" "$GITHUB_OUTPUT"

  rm -rf "$ORIGIN_DIR" "$WORK_DIR"
}

# T9 — PR mode with fewer TODOs -> negative delta
@test "PR delta with fewer TODOs -> negative delta" {
  ORIGIN_DIR="$(mktemp -d)"
  WORK_DIR="$(mktemp -d)"

  git init --bare "$ORIGIN_DIR"
  git clone "$ORIGIN_DIR" "$WORK_DIR"
  cd "$WORK_DIR"
  git config user.email "test@example.com"
  git config user.name "Test"
  git config init.defaultBranch main

  # Base commit: 2 TODOs
  echo "TODO: old" > app.ts
  echo "FIXME: also old" > lib.ts
  git add app.ts lib.ts
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit -m "initial"
  git branch -m main
  git push origin main

  # Current state: remove lib.ts (only 1 TODO remains)
  rm lib.ts

  export GITHUB_OUTPUT
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_STEP_SUMMARY
  GITHUB_STEP_SUMMARY="$(mktemp)"
  export SCAN_PATH="."
  export BASE_REF="main"
  export FILE_EXTENSIONS="ts,js"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "todo-count=1" "$GITHUB_OUTPUT"
  grep -q "todo-delta=-1" "$GITHUB_OUTPUT"

  rm -rf "$ORIGIN_DIR" "$WORK_DIR"
}
