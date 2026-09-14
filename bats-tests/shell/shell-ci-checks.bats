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
  for input in run-coverage coverage-exclude-pattern coverage-outdir coverage-flag coverage-timeout-minutes; do
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
@test "ci.yml self-test caller -> enables the coverage job" {
  run awk '
    /^  self-test-shell-ci-checks:$/ { f = 1 }
    f && /^  [A-Za-z0-9_-]+:$/ && $0 != "  self-test-shell-ci-checks:" { exit }
    f { print }
  ' "$PROJECT_ROOT/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uses: ./.github/workflows/shell-ci-checks.yml"* ]]
  [[ "$output" == *"run-coverage: 'true'"* ]]
}
