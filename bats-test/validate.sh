#!/usr/bin/env bash
set -euo pipefail

# Interface (all via environment):
#   PUBLISH_COMMENT - "true" to require a token for comment publishing
#   GITHUB_TOKEN    - value of the action's github-token input
#
# Guard: when PUBLISH_COMMENT is "true" the token is required. This runs as a
# trusted composite step before BATS so the token never enters the Run BATS
# step environment, where PR-controlled .bats files execute.

PUBLISH_COMMENT="${PUBLISH_COMMENT:-false}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ "$PUBLISH_COMMENT" == "true" && -z "$GITHUB_TOKEN" ]]; then
  echo "::error::publish-comment is 'true' but github-token is empty. Pass secrets.GITHUB_TOKEN as the github-token input."
  exit 1
fi
