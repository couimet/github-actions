#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/prettier/install.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  setup_npm_mock
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Mocks npm so the script's npm invocations log their arguments instead of
# running against the real registry. GITHUB_PATH points at a test file so
# the script's PATH append can be asserted.
setup_npm_mock() {
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/npm" <<'NPM'
#!/usr/bin/env bash
echo "$@" >> "$TEST_TEMP_DIR/npm.log"
NPM
  chmod +x "$TEST_TEMP_DIR/bin/npm"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
  export GITHUB_PATH="$TEST_TEMP_DIR/github_path"
}

@test "PRETTIER_VERSION unset -> runs npm ci and appends node_modules/.bin to GITHUB_PATH" {
  run env -u PRETTIER_VERSION bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx "ci" "$TEST_TEMP_DIR/npm.log"
  [ "$(cat "$TEST_TEMP_DIR/github_path")" = "$PROJECT_ROOT/prettier/node_modules/.bin" ]
}

@test "PRETTIER_VERSION empty -> runs npm ci and appends node_modules/.bin to GITHUB_PATH" {
  run env PRETTIER_VERSION= bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx "ci" "$TEST_TEMP_DIR/npm.log"
  [ "$(cat "$TEST_TEMP_DIR/github_path")" = "$PROJECT_ROOT/prettier/node_modules/.bin" ]
}

@test "PRETTIER_VERSION set -> runs npm install -g prettier@VERSION and does not touch GITHUB_PATH" {
  run env PRETTIER_VERSION=3.0.0 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx "install -g prettier@3.0.0" "$TEST_TEMP_DIR/npm.log"
  [ ! -f "$TEST_TEMP_DIR/github_path" ]
}
