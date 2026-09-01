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

# --- check mode (default) ---

@test "default inputs: runs prettier --check . with a repo config present" {
  touch .prettierrc.json
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "no repo config: falls back to bundled @couimet/eslint-config config" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check --config .*/prettier/node_modules/@couimet/eslint-config/prettier.js \.$"
}

@test "prettier.config.js present: no --config flag" {
  touch prettier.config.js
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "explicit config: passes --config before paths" {
  run env CONFIG=".prettierrc.yaml" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check --config .prettierrc.yaml .$"
}

@test "explicit config wins over a repo config file" {
  touch .prettierrc.json
  run env CONFIG=".prettierrc.yaml" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check --config .prettierrc.yaml .$"
}

@test "custom paths: word-splits PATHS into separate arguments" {
  touch .prettierrc.json
  run env PATHS="src/ tests/" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check src/ tests/$"
}

@test "working directory: cds to WORKING_DIRECTORY before running" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/test.js"
  touch "$TEST_TEMP_DIR/subdir/.prettierrc.yaml"
  run env WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier pwd: .*/subdir$"
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "working directory: honors a prettier config in an ancestor directory" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/test.js"
  touch "$TEST_TEMP_DIR/.prettierrc.json"
  run env WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "working directory: honors a prettier key in an ancestor package.json" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/test.js"
  cat > "$TEST_TEMP_DIR/package.json" <<'ENDOFJSON'
{ "prettier": { "singleQuote": true } }
ENDOFJSON
  run env WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "working directory: falls back to bundled config when no config exists in any ancestor" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/test.js"
  run env WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check --config .*/prettier/node_modules/@couimet/eslint-config/prettier.js \.$"
}

@test "per-target config: file under a directory with its own config runs plain" {
  mkdir -p sub
  touch sub/.prettierrc.json
  touch sub/file.js
  run env PATHS="sub/file.js" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check sub/file.js$"
}

@test "per-target config: mixed configured and unconfigured paths split into two invocations" {
  mkdir -p sub tests
  touch sub/.prettierrc.json
  touch sub/file.js
  touch tests/file.js
  run env PATHS="sub tests" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check --config .*/prettier/node_modules/@couimet/eslint-config/prettier.js tests$"
  echo "$output" | grep -q "prettier args: --check sub$"
}

@test "per-target config: nested config under the default . target needs no --config" {
  mkdir -p sub
  touch sub/.prettierrc.json
  touch sub/file.js
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "per-target config: nested package.json prettier key under the default . target needs no --config" {
  mkdir -p sub
  cat > sub/package.json <<'ENDOFJSON'
{ "prettier": { "singleQuote": true } }
ENDOFJSON
  touch sub/file.js
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --check .$"
}

@test "per-target config: glob target whose base directory has a config runs plain" {
  mkdir -p src
  touch src/.prettierrc.json
  touch src/file.js
  run env PATHS="src/*.js" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "prettier args: --check src/*.js"
}

@test "per-target config: brace glob with config under one expanded base runs plain" {
  mkdir -p src lib
  touch src/.prettierrc.json
  touch src/file.js lib/file.js
  run env PATHS='{src,lib}/**/*.js' bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "prettier args: --check {src,lib}/**/*.js"
}

# --- fix mode ---

@test "fix mode: runs prettier --write with a repo config present" {
  touch .prettierrc.json
  run env MODE=fix bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --write .$"
}

@test "fix mode: falls back to bundled config when the repo has none" {
  run env MODE=fix bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --write --config .*/prettier/node_modules/@couimet/eslint-config/prettier.js \.$"
}

@test "rejects invalid MODE" {
  run env MODE=bogus bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ERROR: MODE must be 'check' or 'fix', got 'bogus'"
}

@test "fix mode: passes --config before paths" {
  run env MODE=fix CONFIG=".prettierrc.yaml" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --write --config .prettierrc.yaml .$"
}

@test "fix mode: word-splits PATHS into separate arguments" {
  touch .prettierrc.json
  run env MODE=fix PATHS="src/ tests/" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --write src/ tests/$"
}

@test "fix mode: cds to WORKING_DIRECTORY before running" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/test.js"
  touch "$TEST_TEMP_DIR/subdir/.prettierrc.yaml"
  run env MODE=fix WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier pwd: .*/subdir$"
  echo "$output" | grep -q "prettier args: --write .$"
}

@test "fix mode: mixed configured and unconfigured paths split into two --write invocations" {
  mkdir -p sub tests
  touch sub/.prettierrc.json
  touch sub/file.js
  touch tests/file.js
  run env MODE=fix PATHS="sub tests" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "prettier args: --write --config .*/prettier/node_modules/@couimet/eslint-config/prettier.js tests$"
  echo "$output" | grep -q "prettier args: --write sub$"
}
