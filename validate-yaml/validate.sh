#!/usr/bin/env bash
set -euo pipefail

SCHEMA="${1:-}"
FILE="${2:-}"

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
#   uv run --with jsonschema,pyyaml ./validate.sh schema.json file.yml
#   pip install jsonschema pyyaml && ./validate.sh schema.json file.yml
python3 -c '
import json, sys
from jsonschema import Draft202012Validator
import jsonschema, yaml

with open(sys.argv[1]) as f:
    schema = json.load(f)
with open(sys.argv[2]) as f:
    data = yaml.safe_load(f)

try:
    jsonschema.validate(data, schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
except jsonschema.ValidationError as e:
    print(f"ERROR: {sys.argv[2]} — {e.message}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {sys.argv[2]} is valid")
' "$SCHEMA" "$FILE"
