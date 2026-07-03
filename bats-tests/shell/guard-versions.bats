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

# Creates a repo with a merge commit so HEAD^2 resolves (simulates forked PR fallback).
setup_merge_repo() {
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  echo '{"version": "1.0.0"}' > package.json
  git add package.json
  git commit --quiet -m "initial commit"
  git checkout --quiet -b feature
  echo '{"version": "2.0.0"}' > package.json
  git add package.json
  git commit --quiet -m "feature bump"
  git checkout --quiet -
  git merge --quiet --no-ff feature -m "merge feature"
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

@test "pre-release in nested package when run from subdir -> exits 1" {
  setup_repo
  mkdir -p apps/web
  echo '{"version": "0.3.0-beta.1"}' > apps/web/package.json
  git add apps/web/package.json
  git commit --quiet -m "add nested prerelease"
  cd apps/web
  run env BASE_REF=HEAD~1 HEAD_REF=HEAD bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Pre-release version"
}

@test "head ref not available locally -> falls back to HEAD^2 (forked PR)" {
  setup_merge_repo
  # Pass a non-existent SHA for head_ref to trigger fetch + HEAD^2 fallback.
  # BASE_REF=HEAD^1 (first parent of merge commit, i.e. main tip before merge).
  # The feature branch has stable "2.0.0" so guard should pass.
  run env BASE_REF=HEAD^1 HEAD_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "base ref not available and fetch from origin fails -> exits 2" {
  setup_repo
  # Non-existent base SHA; no origin remote in the test repo, so fetch fails.
  # git diff still can't resolve the ref, so the script exits 2.
  run env BASE_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa HEAD_REF=HEAD bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "git diff failed"
}

@test "missing ref arguments -> exits 2" {
  run env BASE_REF="" HEAD_REF="" bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
