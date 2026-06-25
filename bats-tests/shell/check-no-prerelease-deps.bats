#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/check-no-prerelease-deps/check-no-prerelease-deps.sh"

# T1 — auto-discover finds nothing
@test "no package.json files -> exits 0" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# T2 — empty package.json, to_entries produces nothing
@test "package.json with no deps -> exits 0" {
  cd "$TEST_TEMP_DIR"
  echo '{}' > package.json
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# T3 — clean string semver, all contains() checks false
@test "clean semver deps -> exits 0" {
  cd "$TEST_TEMP_DIR"
  cat > package.json <<'JSON'
{
  "dependencies": {
    "foo": "1.0.0"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# T4 — non-string dep (workspace protocol) filtered by type check
@test "workspace protocol dep -> exits 0" {
  cd "$TEST_TEMP_DIR"
  cat > package.json <<'JSON'
{
  "dependencies": {
    "foo": "workspace:*"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# T5 — -alpha in dependencies
@test "prerelease -alpha in dependencies -> exits 1" {
  cd "$TEST_TEMP_DIR"
  cat > package.json <<'JSON'
{
  "dependencies": {
    "pkg": "1.0.0-alpha.1"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "pkg@1.0.0-alpha.1"
}

# T6 — -beta in devDependencies
@test "prerelease -beta in devDependencies -> exits 1" {
  cd "$TEST_TEMP_DIR"
  cat > package.json <<'JSON'
{
  "devDependencies": {
    "pkg": "2.0.0-beta.3"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "pkg@2.0.0-beta.3"
}

# T7 — -rc in peerDependencies
@test "prerelease -rc in peerDependencies -> exits 1" {
  cd "$TEST_TEMP_DIR"
  cat > package.json <<'JSON'
{
  "peerDependencies": {
    "pkg": "3.0.0-rc.2"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "pkg@3.0.0-rc.2"
}

# T8 — -pre in optionalDependencies
@test "prerelease -pre in optionalDependencies -> exits 1" {
  cd "$TEST_TEMP_DIR"
  cat > package.json <<'JSON'
{
  "optionalDependencies": {
    "pkg": "4.0.0-pre.7"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "pkg@4.0.0-pre.7"
}

# T9 — node_modules excluded from discovery
@test "prerelease in node_modules is excluded -> exits 0" {
  cd "$TEST_TEMP_DIR"
  mkdir -p node_modules/some-pkg
  cat > node_modules/some-pkg/package.json <<'JSON'
{
  "dependencies": {
    "bad": "1.0.0-alpha.1"
  }
}
JSON
  cat > package.json <<'JSON'
{
  "dependencies": {
    "clean": "1.0.0"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# T10 — explicit file arg, clean
@test "explicit file arg with clean deps -> exits 0" {
  cd "$TEST_TEMP_DIR"
  cat > pkg.json <<'JSON'
{
  "dependencies": {
    "foo": "1.0.0"
  }
}
JSON
  run bash "$SCRIPT" pkg.json
  [ "$status" -eq 0 ]
}

# T11 — explicit file arg, prerelease
@test "explicit file arg with prerelease -> exits 1" {
  cd "$TEST_TEMP_DIR"
  cat > pkg.json <<'JSON'
{
  "dependencies": {
    "pkg": "1.0.0-alpha.1"
  }
}
JSON
  run bash "$SCRIPT" pkg.json
  [ "$status" -eq 1 ]
}

# T12 — multiple files via auto-discover, mixed clean+prerelease
@test "multiple files mixed clean and prerelease -> exits 1" {
  cd "$TEST_TEMP_DIR"
  mkdir a b
  cat > a/package.json <<'JSON'
{
  "dependencies": {
    "clean": "1.0.0"
  }
}
JSON
  cat > b/package.json <<'JSON'
{
  "dependencies": {
    "pkg": "1.0.0-beta.1"
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# T13 — jq not found. Shadow the `command` builtin to simulate missing jq.
@test "jq not found -> exits 2" {
  cd "$TEST_TEMP_DIR"
  # Shadow `command` to return 1 for `command -v jq`, pass through otherwise.
  run bash -c '
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "jq" ]; then
        return 1
      fi
      builtin command "$@"
    }
    . "$1"
  ' -- "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "jq is required"
}
