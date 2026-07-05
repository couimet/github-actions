#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-ci-checks-secrets.sh"

@test "valid ci-checks.yml with secrets passthrough -> success" {
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci-checks.yml" <<'EOF'
on:
  workflow_call:
    secrets:
      github-token:
        required: false
jobs:
  format:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  lint:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  build:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  test:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_CHECKS_PATH='$TEST_TEMP_DIR/.github/workflows/ci-checks.yml' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "missing workflow_call secret -> failure" {
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci-checks.yml" <<'EOF'
on:
  workflow_call:
    inputs:
      test:
        required: true
        type: string
jobs:
  format:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  lint:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  build:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  test:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_CHECKS_PATH='$TEST_TEMP_DIR/.github/workflows/ci-checks.yml' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
}

@test "job missing GITHUB_TOKEN env var -> failure" {
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci-checks.yml" <<'EOF'
on:
  workflow_call:
    secrets:
      github-token:
        required: false
jobs:
  format:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  lint:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  build:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
        env:
          GITHUB_TOKEN: ${{ secrets.github-token }}
  test:
    runs-on: ubuntu-latest
    secrets:
      github-token:
    permissions:
      contents: read
    steps:
      - run: echo ok
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_CHECKS_PATH='$TEST_TEMP_DIR/.github/workflows/ci-checks.yml' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
}

@test "missing file -> failure" {
  run bash -c "cd '$TEST_TEMP_DIR' && CI_CHECKS_PATH='$TEST_TEMP_DIR/.github/workflows/ci-checks.yml' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
}
