#!/usr/bin/env bats

load test_helper

SCRIPT_SRC="$PROJECT_ROOT/scripts/verify-dependabot-npm-coverage.sh"

# Copy the script into a fixture tree so that SCRIPT_DIR resolves to
# $TEST_TEMP_DIR/scripts and REPO_ROOT (its parent) resolves to $TEST_TEMP_DIR.
# Fixtures then live at $TEST_TEMP_DIR/.github/dependabot.yml and
# $TEST_TEMP_DIR/<dir>/package.json.
setup_fixture_tree() {
  mkdir -p "$TEST_TEMP_DIR/scripts" "$TEST_TEMP_DIR/.github"
  cp "$SCRIPT_SRC" "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
}

write_dependabot() {
  cat > "$TEST_TEMP_DIR/.github/dependabot.yml"
}

@test "all package.json dirs registered in dependabot.yml -> success" {
  setup_fixture_tree
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar"
  touch "$TEST_TEMP_DIR/foo/package.json" "$TEST_TEMP_DIR/bar/package.json"
  write_dependabot <<'EOF'
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/foo"
    schedule:
      interval: "weekly"
  - package-ecosystem: "npm"
    directory: "/bar"
    schedule:
      interval: "weekly"
EOF
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "/foo is registered"
  echo "$output" | grep -q "/bar is registered"
}

@test "unregistered package.json dir -> failure with 'not registered' message" {
  setup_fixture_tree
  mkdir -p "$TEST_TEMP_DIR/foo"
  touch "$TEST_TEMP_DIR/foo/package.json"
  write_dependabot <<'EOF'
version: 2
updates: []
EOF
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not registered"
}

@test "missing dependabot.yml -> failure with 'not found' message" {
  setup_fixture_tree
  mkdir -p "$TEST_TEMP_DIR/foo"
  touch "$TEST_TEMP_DIR/foo/package.json"
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not found"
}

@test "no package.json dirs found -> success" {
  setup_fixture_tree
  write_dependabot <<'EOF'
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/foo"
    schedule:
      interval: "weekly"
EOF
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -eq 0 ]
}

@test "root package.json (\".\") is skipped -> success" {
  setup_fixture_tree
  touch "$TEST_TEMP_DIR/package.json"
  write_dependabot <<'EOF'
version: 2
updates: []
EOF
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -eq 0 ]
}

@test "tests/ directory package.json is excluded -> success" {
  setup_fixture_tree
  mkdir -p "$TEST_TEMP_DIR/tests"
  touch "$TEST_TEMP_DIR/tests/package.json"
  write_dependabot <<'EOF'
version: 2
updates: []
EOF
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -eq 0 ]
}

@test "mixed registered and unregistered package.json dirs -> failure" {
  setup_fixture_tree
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar"
  touch "$TEST_TEMP_DIR/foo/package.json" "$TEST_TEMP_DIR/bar/package.json"
  write_dependabot <<'EOF'
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/foo"
    schedule:
      interval: "weekly"
EOF
  run bash "$TEST_TEMP_DIR/scripts/verify-dependabot-npm-coverage.sh"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "/foo is registered"
  echo "$output" | grep -q "/bar/package.json is not registered"
  echo "$output" | grep -q "One or more package.json files are missing"
}
