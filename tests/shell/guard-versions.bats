#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/guard-versions/guard.sh"

setup_repo() {
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  # Create an initial commit so we have a base ref
  echo '{"version": "1.0.0"}' > package.json
  git add package.json
  git commit --quiet -m "initial commit"
}

@test "no pre-release versions in changed package.json -> exits 0" {
  setup_repo
  # Change to a stable version
  echo '{"version": "2.0.0"}' > package.json
  git add package.json
  git commit --quiet -m "bump to stable"
  run env BASE_REF=HEAD~1 HEAD_REF=HEAD bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "pre-release version in changed package.json -> exits 1 with error" {
  setup_repo
  echo '{"version": "0.2.0-alpha.1"}' > package.json
  git add package.json
  git commit --quiet -m "add pre-release"
  run env BASE_REF=HEAD~1 HEAD_REF=HEAD bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Pre-release version"
}

@test "stable version in changed package.json -> exits 0" {
  setup_repo
  echo '{"version": "1.5.0"}' > package.json
  git add package.json
  git commit --quiet -m "bump stable"
  run env BASE_REF=HEAD~1 HEAD_REF=HEAD bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "no package.json in changed files -> exits 0" {
  setup_repo
  echo "hello" > README.md
  git add README.md
  git commit --quiet -m "add readme"
  run env BASE_REF=HEAD~1 HEAD_REF=HEAD bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No package.json files changed"
}

@test "missing ref arguments -> exits 2" {
  run env BASE_REF="" HEAD_REF="" bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
