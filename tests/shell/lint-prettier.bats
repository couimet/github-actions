#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/prettier/lint.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/prettier" <<'ENDOFSTUB'
#!/usr/bin/env bash
echo "prettier pwd: $(pwd)"
echo "prettier args: $*"
exit 0
ENDOFSTUB
  chmod +x "$TEST_TEMP_DIR/bin/prettier"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"

  cd "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

@test "default inputs: runs prettier --check ." {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "explicit config: passes --config before paths" {
  run env CONFIG=".prettierrc.yaml" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check --config .prettierrc.yaml .$"
}

@test "custom paths: word-splits PATHS into separate arguments" {
  run env PATHS="src/ tests/" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check src/ tests/$"
}

@test "working directory: cds to WORKING_DIRECTORY before running" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/test.js"
  run env WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier pwd: .*/subdir$"
  echo "$output" | grep -q "prettier args: --check .$"
}
