#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/markdownlint/install.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  setup_npm_mock
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

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

@test "MARKDOWNLINT_VERSION unset: runs npm ci and appends node_modules/.bin to GITHUB_PATH" {
  run env -u MARKDOWNLINT_VERSION bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fxq "ci" "$TEST_TEMP_DIR/npm.log"
  grep -Fxq "$PROJECT_ROOT/markdownlint/node_modules/.bin" "$TEST_TEMP_DIR/github_path"
}

@test "MARKDOWNLINT_VERSION empty: runs npm ci and appends node_modules/.bin to GITHUB_PATH" {
  run env MARKDOWNLINT_VERSION="" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fxq "ci" "$TEST_TEMP_DIR/npm.log"
  grep -Fxq "$PROJECT_ROOT/markdownlint/node_modules/.bin" "$TEST_TEMP_DIR/github_path"
}

@test "MARKDOWNLINT_VERSION set: provisions the fallback via npm ci, installs the requested cli2 globally, and does not touch GITHUB_PATH" {
  run env MARKDOWNLINT_VERSION="1.2.3" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_TEMP_DIR/npm.log")" -eq 2 ]
  [ "$(sed -n '1p' "$TEST_TEMP_DIR/npm.log")" = "ci" ]
  [ "$(sed -n '2p' "$TEST_TEMP_DIR/npm.log")" = "install -g markdownlint-cli2@1.2.3" ]
  [ ! -e "$TEST_TEMP_DIR/github_path" ]
}
