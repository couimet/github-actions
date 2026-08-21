#!/usr/bin/env bash
set -euo pipefail

SCHEMA="${1:-}"
FILE="${2:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

if [ -z "$SCHEMA" ] || [ ! -f "$SCHEMA" ]; then
  echo "ERROR: Schema file not found: ${SCHEMA:-<none provided>}" >&2
  echo "Usage: validate.sh <schema.json> <file.yml>" >&2
  exit 1
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: YAML file not found: ${FILE:-<none provided>}" >&2
  echo "Usage: validate.sh <schema.json> <file.yml>" >&2
  exit 1
fi

# Run validation. Requires jsonschema and pyyaml.
# In CI, action.yml handles this via uv. For local use:
#   uv run --locked --with jsonschema,pyyaml ./validate.sh schema.json file.yml
#   pip install jsonschema pyyaml && ./validate.sh schema.json file.yml

# Capture the Python stderr so failures can be reported both in the step log
# and (via comment-file) in a sticky PR comment posted by action.yml.
error_file="$(mktemp)"
if ! python3 -c '
import json, os, sys
from jsonschema import Draft202012Validator
import jsonschema, yaml

# Display paths repo-relative when running under GITHUB_WORKSPACE (CI);
# keep the argument as-is otherwise (local runs).
display_path = sys.argv[2]
workspace = os.environ.get("GITHUB_WORKSPACE")
if workspace and display_path.startswith(workspace + os.sep):
    display_path = display_path[len(workspace) + 1 :]

with open(sys.argv[1]) as f:
    schema = json.load(f)
with open(sys.argv[2]) as f:
    try:
        data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        # Concise single-line message; problem (if present) is the readable
        # core of ParserError/ScannerError messages.
        detail = getattr(e, "problem", None) or " ".join(str(e).split())
        mark = getattr(e, "problem_mark", None)
        if mark:
            detail = f"{detail} (line {mark.line + 1}, column {mark.column + 1})"
        print(f"ERROR: {display_path} — {detail}", file=sys.stderr)
        sys.exit(1)

try:
    jsonschema.validate(data, schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
except jsonschema.ValidationError as e:
    print(f"ERROR: {display_path} — {e.message}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {display_path} is valid")
' "$SCHEMA" "$FILE" 2> "$error_file"; then
  # Validation failed: keep the step-log behavior and hand the error text to
  # action.yml as a comment-file for a sticky PR comment.
  cat "$error_file" >&2
  comment_file="$(mktemp)"
  {
    echo "## YAML validation check"
    echo ""
    echo '```'
    cat "$error_file"
    echo '```'
  } > "$comment_file"
  echo "comment-file=$comment_file" >> "$GITHUB_OUTPUT"
  exit 1
fi
rm -f "$error_file"
