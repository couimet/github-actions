#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/codecov-typescript-upload/upload-per-package.sh"

# Creates mock curl and mock codecov so the script runs without network access.
# Mock curl creates a mock codecov binary that logs its arguments to a file.
setup_mocks() {
  cat > "$TEST_TEMP_DIR/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
cat > ./codecov <<'MOCK_CODECOV'
#!/usr/bin/env bash
echo "$@" >> "$TEST_TEMP_DIR/codecov.log"
MOCK_CODECOV
chmod +x ./codecov
MOCK_CURL
  chmod +x "$TEST_TEMP_DIR/curl"
  export PATH="$TEST_TEMP_DIR:$PATH"
}

@test "single package: extracts name and uploads with flag" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/mypkg/coverage"
  echo 'dummy coverage' > "$TEST_TEMP_DIR/packages/mypkg/coverage/lcov.info"

  run env \
    FILES="packages/mypkg/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/mypkg/coverage/lcov.info -F mypkg" "$TEST_TEMP_DIR/codecov.log"
}

@test "multiple packages: uploads each with correct flag" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/core/coverage"
  mkdir -p "$TEST_TEMP_DIR/packages/utils/coverage"
  echo 'core cov' > "$TEST_TEMP_DIR/packages/core/coverage/lcov.info"
  echo 'utils cov' > "$TEST_TEMP_DIR/packages/utils/coverage/lcov.info"

  run env \
    FILES="packages/core/coverage/lcov.info packages/utils/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/core/coverage/lcov.info -F core" "$TEST_TEMP_DIR/codecov.log"
  grep -qF -- "-f packages/utils/coverage/lcov.info -F utils" "$TEST_TEMP_DIR/codecov.log"
}

@test "flat repo: file path not matching packages/<name>/... pattern is skipped" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/coverage"
  echo 'flat cov' > "$TEST_TEMP_DIR/coverage/lcov.info"

  run env \
    FILES="coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/codecov.log" ]
}

@test "mixed: uploads matching files, skips non-matching" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/app/coverage"
  mkdir -p "$TEST_TEMP_DIR/coverage"
  echo 'app cov' > "$TEST_TEMP_DIR/packages/app/coverage/lcov.info"
  echo 'root cov' > "$TEST_TEMP_DIR/coverage/lcov.info"

  run env \
    FILES="packages/app/coverage/lcov.info coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/app/coverage/lcov.info -F app" "$TEST_TEMP_DIR/codecov.log"
  ! grep -qF -- "-f coverage/lcov.info" "$TEST_TEMP_DIR/codecov.log"
}

@test "custom working directory: resolves files relative to it" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/subdir/packages/foo/coverage"
  echo 'foo cov' > "$TEST_TEMP_DIR/subdir/packages/foo/coverage/lcov.info"

  run env \
    FILES="packages/foo/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR/subdir" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/foo/coverage/lcov.info -F foo" "$TEST_TEMP_DIR/codecov.log"
}

@test "default FILES: uses coverage/lcov.info when FILES is unset" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/coverage"
  echo 'default' > "$TEST_TEMP_DIR/coverage/lcov.info"

  run env \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  # Flat path — no package match, so no upload
  [ ! -f "$TEST_TEMP_DIR/codecov.log" ]
}

@test "default WORKING_DIRECTORY: uses '.' when unset" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/pkg/coverage"
  echo 'pkg cov' > "$TEST_TEMP_DIR/packages/pkg/coverage/lcov.info"

  run env \
    FILES="packages/pkg/coverage/lcov.info" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash -c "cd $TEST_TEMP_DIR && bash $SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/pkg/coverage/lcov.info -F pkg" "$TEST_TEMP_DIR/codecov.log"
}

@test "custom base directory: extracts name from apps/<name>/... pattern" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/apps/web/coverage"
  mkdir -p "$TEST_TEMP_DIR/apps/api/coverage"
  echo 'web cov' > "$TEST_TEMP_DIR/apps/web/coverage/lcov.info"
  echo 'api cov' > "$TEST_TEMP_DIR/apps/api/coverage/lcov.info"

  run env \
    FILES="apps/web/coverage/lcov.info apps/api/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="apps" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f apps/web/coverage/lcov.info -F web" "$TEST_TEMP_DIR/codecov.log"
  grep -qF -- "-f apps/api/coverage/lcov.info -F api" "$TEST_TEMP_DIR/codecov.log"
}

@test "empty base: extracts first path component as package name" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/rangelink-core-ts/coverage"
  mkdir -p "$TEST_TEMP_DIR/rangelink-vscode-extension/coverage"
  echo 'core cov' > "$TEST_TEMP_DIR/rangelink-core-ts/coverage/lcov.info"
  echo 'vscode cov' > "$TEST_TEMP_DIR/rangelink-vscode-extension/coverage/lcov.info"

  run env \
    FILES="rangelink-core-ts/coverage/lcov.info rangelink-vscode-extension/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f rangelink-core-ts/coverage/lcov.info -F rangelink-core-ts" "$TEST_TEMP_DIR/codecov.log"
  grep -qF -- "-f rangelink-vscode-extension/coverage/lcov.info -F rangelink-vscode-extension" "$TEST_TEMP_DIR/codecov.log"
}

@test "custom pattern: extracts flag from nested path structure" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/src/mylib/__tests__/coverage"
  echo 'lib cov' > "$TEST_TEMP_DIR/src/mylib/__tests__/coverage/lcov.info"

  run env \
    FILES="src/mylib/__tests__/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    PER_PACKAGE_FLAGS_PATTERN="s|src/\([^/]*\)/.*|\1|" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f src/mylib/__tests__/coverage/lcov.info -F mylib" "$TEST_TEMP_DIR/codecov.log"
}

@test "pattern takes precedence over base when both are set" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/mypkg/coverage"
  echo 'pkg cov' > "$TEST_TEMP_DIR/packages/mypkg/coverage/lcov.info"

  # base says "packages" but pattern extracts something else — pattern wins
  run env \
    FILES="packages/mypkg/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    PER_PACKAGE_FLAGS_PATTERN="s|packages/\([^/]*\)/coverage/.*|\1|" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/mypkg/coverage/lcov.info -F mypkg" "$TEST_TEMP_DIR/codecov.log"
}

@test "pattern does not match: file is skipped" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/app/coverage"
  echo 'app cov' > "$TEST_TEMP_DIR/packages/app/coverage/lcov.info"

  # Pattern targets src/* but file is under packages/* — should not match
  run env \
    FILES="packages/app/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_PATTERN="s|src/\([^/]*\)/.*|\1|" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/codecov.log" ]
}

@test "empty base with flat file: no directory to extract, skipped" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/coverage"
  echo 'flat' > "$TEST_TEMP_DIR/coverage/lcov.info"

  # cut -d/ -f1 on "coverage/lcov.info" gives "coverage" — same as path, skipped
  run env \
    FILES="coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/codecov.log" ]
}

@test "no matching files: exits successfully without uploading" {
  setup_mocks

  run env \
    FILES="nonexistent/*/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/codecov.log" ]
}

@test "fail-ci-if-error true: appends -Z flag to codecov invocation" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/mypkg/coverage"
  echo 'dummy coverage' > "$TEST_TEMP_DIR/packages/mypkg/coverage/lcov.info"

  run env \
    FILES="packages/mypkg/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    FAIL_CI_IF_ERROR="true" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/mypkg/coverage/lcov.info -F mypkg -Z" "$TEST_TEMP_DIR/codecov.log"
}

@test "fail-ci-if-error false: omits -Z flag from codecov invocation" {
  setup_mocks
  mkdir -p "$TEST_TEMP_DIR/packages/mypkg/coverage"
  echo 'dummy coverage' > "$TEST_TEMP_DIR/packages/mypkg/coverage/lcov.info"

  run env \
    FILES="packages/mypkg/coverage/lcov.info" \
    WORKING_DIRECTORY="$TEST_TEMP_DIR" \
    CODECOV_TOKEN="test-token" \
    PER_PACKAGE_FLAGS_BASE="packages" \
    FAIL_CI_IF_ERROR="false" \
    bash "$SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF -- "-f packages/mypkg/coverage/lcov.info -F mypkg" "$TEST_TEMP_DIR/codecov.log"
  ! grep -qF -- "-Z" "$TEST_TEMP_DIR/codecov.log"
}
