#!/usr/bin/env bats

load test_helper

WORKFLOW="$PROJECT_ROOT/.github/workflows/shell-ci-checks.yml"

# GitHub warns rather than fails when a composite action receives an unknown
# input, and the action's own default then applies in silence. A mistyped input
# name in this workflow would therefore measure the wrong directory on every
# consumer run instead of failing, which is why the relay is asserted here.

# Print one workflow_call input block, from its name line to the next input.
input_block() {
  awk -v name="$1" '
    $0 ~ "^      " name ":$" { f = 1; print; next }
    f && /^      [A-Za-z0-9_-]+:$/ { exit }
    f { print }
  ' "$WORKFLOW"
}

# Print the coverage job, from its id line to the next job.
coverage_job() {
  awk '
    /^  coverage:$/ { f = 1 }
    f && /^  [A-Za-z0-9_-]+:$/ && $0 != "  coverage:" { exit }
    f { print }
  ' "$WORKFLOW"
}

# Print the bats-test job, from its id line to the next job.
bats_test_job() {
  awk '
    /^  bats-test:$/ { f = 1 }
    f && /^  [A-Za-z0-9_-]+:$/ && $0 != "  bats-test:" { exit }
    f { print }
  ' "$WORKFLOW"
}

# Print the self-test job that calls this workflow, from its id line to the next
# job. That caller lives in this repository's ci.yml, not in $WORKFLOW.
self_test_caller() {
  awk '
    /^  self-test-shell-ci-checks:$/ { f = 1 }
    f && /^  [A-Za-z0-9_-]+:$/ && $0 != "  self-test-shell-ci-checks:" { exit }
    f { print }
  ' "$PROJECT_ROOT/.github/workflows/ci.yml"
}

@test "coverage job -> off unless the caller opts in" {
  run coverage_job
  [ "$status" -eq 0 ]
  [[ "$output" == *"if: inputs.run-coverage"* ]]
}

@test "run-coverage input -> boolean, defaulting to false" {
  run input_block run-coverage
  [ "$status" -eq 0 ]
  [[ "$output" == *"type: boolean"* ]]
  [[ "$output" == *"default: false"* ]]
}

@test "coverage job -> pinned runner and the kcov-build-aware timeout" {
  run coverage_job
  [ "$status" -eq 0 ]
  [[ "$output" == *"runs-on: ubuntu-24.04"* ]]
  [[ "$output" == *"timeout-minutes: \${{ fromJSON(inputs.coverage-timeout-minutes) }}"* ]]
}

# The coverage job must measure the suite the bats-test job runs. Relaying is
# what keeps the two in step when a consumer overrides any of these inputs.
#
# The misses are collected rather than asserted inside the loop: a bare [[ ]]
# in a loop body reports only the last iteration's status, so an earlier
# mismatch would pass unnoticed.
@test "coverage job -> relays every BATS input the bats-test job relays" {
  run coverage_job
  [ "$status" -eq 0 ]
  local input
  local missing=()
  for input in test-directory bats-version recursive support-install assert-install file-install detik-install; do
    [[ "$output" == *"${input}: \${{ inputs.${input} }}"* ]] || missing+=("$input")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "not relayed: ${missing[*]}" >&2
    return 1
  fi
}

@test "coverage job -> relays the coverage-only inputs to shell-coverage" {
  run coverage_job
  [ "$status" -eq 0 ]
  [[ "$output" == *"uses: couimet/github-actions/shell-coverage@main"* ]]
  [[ "$output" == *'exclude-pattern: ${{ inputs.coverage-exclude-pattern }}'* ]]
  [[ "$output" == *'exclude-region: ${{ inputs.coverage-exclude-region }}'* ]]
  [[ "$output" == *'exclude-line: ${{ inputs.coverage-exclude-line }}'* ]]
  [[ "$output" == *'outdir: ${{ inputs.coverage-outdir }}'* ]]
}

@test "coverage job -> uploads the report path the action outputs, under the coverage flag" {
  run coverage_job
  [ "$status" -eq 0 ]
  [[ "$output" == *'files: ${{ steps.coverage.outputs.report-path }}'* ]]
  [[ "$output" == *'flags: ${{ inputs.coverage-flag }}'* ]]
  [[ "$output" == *'token: ${{ secrets.codecov-token }}'* ]]
}

@test "workflow_call -> declares the codecov-token secret the coverage job passes" {
  run grep -A3 '^    secrets:' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codecov-token:"* ]]
}

@test "workflow_call -> declares every coverage input the job reads" {
  local input
  local missing=()
  for input in run-coverage coverage-exclude-pattern coverage-exclude-region coverage-exclude-line coverage-outdir coverage-flag coverage-timeout-minutes; do
    run input_block "$input"
    if [[ "$status" -ne 0 || -z "$output" ]]; then
      missing+=("$input")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "not declared: ${missing[*]}" >&2
    return 1
  fi
}

# This repository measures its own shell scripts, so its self-test job turns the
# coverage job on. A dropped run-coverage line would leave that path unwatched
# until a consumer met the defect instead.
#
# The two marker inputs are passed here so that GitHub resolves their names
# against the called workflow on every run: an undeclared input fails the caller.
# The BATS assertions above only prove the workflow holds the text.
@test "ci.yml self-test caller -> enables the coverage job" {
  run self_test_caller
  [ "$status" -eq 0 ]
  [[ "$output" == *"uses: ./.github/workflows/shell-ci-checks.yml"* ]]
  [[ "$output" == *"run-coverage: true"* ]]
  [[ "$output" == *"coverage-exclude-region: 'kcov-exclude-start:kcov-exclude-end'"* ]]
  [[ "$output" == *"coverage-exclude-line: 'kcov-exclude-line'"* ]]
}

# GitHub coerces a boolean-like literal before it assigns the value to the
# declared input type, so a string input cannot carry the opt-out at all:
# 'false' arrives as a boolean, and that failed assignment takes the caller's
# whole workflow file down with startup_failure and no jobs.
@test "ci.yml self-test caller -> passes publish-comment as a bare boolean" {
  run self_test_caller
  [ "$status" -eq 0 ]
  [[ "$output" == *"publish-comment: false"* ]]
  [[ "$output" != *"publish-comment: 'false'"* ]]
}

@test "publish-comment input -> boolean, defaulting to true" {
  run input_block publish-comment
  [ "$status" -eq 0 ]
  [[ "$output" == *"type: boolean"* ]]
  [[ "$output" == *"default: true"* ]]
}

# These five relay to composite actions. Composite action inputs are strings by
# construction, so declaring them as strings here reads as the consistent choice
# and is the one edit that breaks a caller: a bare `false` fails the whole
# workflow file with startup_failure, and no job runs. A boolean input accepts
# both `false` and 'false', so it is the only typing that cannot surprise a
# caller.
#
# The misses are collected rather than asserted inside the loop: a bare [[ ]] in
# a loop body reports only the last iteration's status, so an earlier mismatch
# would pass unnoticed.
@test "relay inputs -> boolean with an unquoted default" {
  local input
  local bad=()
  for input in recursive support-install assert-install detik-install file-install; do
    run input_block "$input"
    if [[ "$status" -ne 0 ]] \
      || [[ "$output" != *"type: boolean"* ]] \
      || [[ "$output" == *"'"* ]]; then
      bad+=("$input")
    fi
  done
  if [[ "${#bad[@]}" -gt 0 ]]; then
    echo "not a boolean with an unquoted default: ${bad[*]}" >&2
    return 1
  fi
}

# The test above asserts what the file claims. This one proves the claim holds
# at a real call site: actionlint resolves the local reusable workflow and
# rejects a bare boolean against a string input, which is the defect this pair
# of tests exists to catch. A work tree is required, because without one
# actionlint cannot resolve the call and reports success without checking it.
@test "boolean inputs -> actionlint accepts a bare boolean from a caller" {
  command -v actionlint >/dev/null 2>&1 || {
    echo "actionlint is required; run make install-prereqs" >&2
    return 1
  }
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  git -C "$TEST_TEMP_DIR" init -q
  cp "$WORKFLOW" "$TEST_TEMP_DIR/.github/workflows/shell-ci-checks.yml"
  cat > "$TEST_TEMP_DIR/.github/workflows/caller.yml" <<'EOF'
on:
  push:
jobs:
  a:
    uses: ./.github/workflows/shell-ci-checks.yml
    with:
      recursive: false
      support-install: false
      assert-install: false
      detik-install: true
      file-install: true
      publish-comment: false
      run-coverage: true
EOF

  run actionlint -no-color \
    "$TEST_TEMP_DIR/.github/workflows/caller.yml" \
    "$TEST_TEMP_DIR/.github/workflows/shell-ci-checks.yml"
  if [[ "$status" -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
}

# The old relay spelled the fork guard as `cond && 'false' || inputs.x`. That
# form works only because the string 'false' is truthy, so `||` short-circuits.
# Against a real boolean the left side is falsy and the expression falls
# through, silently returning the opt-in value on a fork pull request.
@test "bats-test job -> relays publish-comment as a boolean expression" {
  run bats_test_job
  [ "$status" -eq 0 ]
  [[ "$output" == *"publish-comment: \${{ github.event.pull_request.head.repo.fork != true && inputs.publish-comment }}"* ]]
}

@test "setup input -> free-form string, empty by default" {
  run input_block setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"type: string"* ]]
  [[ "$output" == *"default: ''"* ]]
}

# A consumer's suite shells out to tools this workflow does not install, so both
# jobs that execute it run the consumer's setup command first. A step missing
# from one job fails that job alone, which reads as a flaky suite rather than as
# a missing prerequisite.
@test "bats-test and coverage jobs -> both run the setup command" {
  local job
  local missing=()
  for job in bats_test_job coverage_job; do
    run "$job"
    [[ "$output" == *"if: inputs.setup != ''"* ]] || missing+=("$job")
    [[ "$output" == *'run: ${{ inputs.setup }}'* ]] || missing+=("$job")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "no setup step: ${missing[*]}" >&2
    return 1
  fi
}

# The shellcheck job reads files and runs no suite, so it needs no toolchain.
@test "shellcheck job -> runs no setup command" {
  run awk '
    /^  shellcheck:$/ { f = 1 }
    f && /^  [A-Za-z0-9_-]+:$/ && $0 != "  shellcheck:" { exit }
    f { print }
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" != *"inputs.setup"* ]]
}

@test "ci.yml self-test caller -> provisions the toolchain through the setup input" {
  run self_test_caller
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup: bash scripts/setup-ci-toolchain.sh"* ]]
}
