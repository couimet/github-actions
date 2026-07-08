#!/usr/bin/env bash
set -euo pipefail

COMMAND="${COMMAND:-}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-}"

GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

main() {
  if [[ -z "$COMMAND" ]]; then
    echo "error: COMMAND is required" >&2
    exit 1
  fi

  if [[ -n "$WORKING_DIRECTORY" ]]; then
    cd "$WORKING_DIRECTORY"
  fi

  bash -euo pipefail -c "$COMMAND"

  if ! git diff --quiet; then
    local comment_file
    comment_file="$(mktemp)"

    {
      echo "## Generated drift detected"
      echo ""
      echo "The following files are out of sync after running:"
      echo ""
      echo '```'
      echo "$COMMAND"
      echo '```'
      echo ""
      echo "### Drifted files"
      echo ""

      local drifted_file
      while IFS= read -r drifted_file; do
        echo "- \`$drifted_file\`"
      done < <(git diff --name-only)

      echo ""
      echo "Run the command locally and commit the result."
    } > "$comment_file"

    echo "comment-file=$comment_file" >> "$GITHUB_OUTPUT"
  fi
}

main
