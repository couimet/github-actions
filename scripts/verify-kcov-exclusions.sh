#!/usr/bin/env bash
set -euo pipefail

# Verify that the exclusion markers a coverage run carried did their job.
#
# kcov's bash engine cannot observe every line: it attributes a statement's hit
# to the line where the statement ends, and an empty case arm holds no command
# for its trap to fire on. kcov marks such a line unreachable, and the Cobertura
# writer omits every unreachable line from the report. So a marker kcov honoured
# shows as a line absent from the report, and a marker kcov ignored shows as a
# line present with hits="0". This script fails on the second shape.
#
# It reads the marker strings from the environment and holds neither literal in
# its own source, which matters because this script is itself instrumented. kcov
# matches a marker as a raw substring against every instrumented line, and a
# region start with no matching end later in the same file would mark every line
# after it unreachable. A literal here would erase the guard from the report it
# exists to check.
#
# Inputs (env):
#   REPORT_PATH     consolidated Cobertura report (default: coverage/cobertura.xml)
#   EXCLUDE_LINE    the single-line marker; must be set, may be empty to skip it
#   EXCLUDE_REGION  the region markers as "<start>:<end>"; must be set, may be
#                   empty to skip them
#
# An enabled marker must match at least one line in a measured file that resolves
# on disk. A marker that matches nothing skips its whole comparison, so the run
# would report green while proving nothing about that exclusion.
#
# Exit codes:
#   1  a marker is unset, the region value holds no usable pair, the report is
#      missing, no measured file resolves on disk, or an enabled marker matches
#      no line in a resolved measured file
#   2  a marked line still appears in the report with zero hits

REPORT_PATH="${REPORT_PATH:-coverage/cobertura.xml}"

if [[ -z "${EXCLUDE_LINE+set}" ]]; then
  echo "::error::verify-kcov-exclusions: EXCLUDE_LINE is unset. Pass the marker the coverage run used, or an empty string to skip that marker." >&2
  exit 1
fi

if [[ -z "${EXCLUDE_REGION+set}" ]]; then
  echo "::error::verify-kcov-exclusions: EXCLUDE_REGION is unset. Pass the marker the coverage run used, or an empty string to skip that marker." >&2
  exit 1
fi

line_marker="$EXCLUDE_LINE"
start_marker=""
end_marker=""

if [[ -n "$EXCLUDE_REGION" ]]; then
  if [[ "$EXCLUDE_REGION" != *:* ]]; then
    echo "::error::verify-kcov-exclusions: EXCLUDE_REGION must read \"<start>:<end>\", got '${EXCLUDE_REGION}'." >&2
    exit 1
  fi
  start_marker="${EXCLUDE_REGION%%:*}"
  end_marker="${EXCLUDE_REGION#*:}"
  if [[ -z "$start_marker" || -z "$end_marker" ]]; then
    echo "::error::verify-kcov-exclusions: EXCLUDE_REGION needs two non-empty markers around the colon, got '${EXCLUDE_REGION}'." >&2
    exit 1
  fi
fi

# Both markers empty is a supported setting: it turns both exclusions off, so
# there is nothing left to verify and a failure here would be a false alarm.
if [[ -z "$line_marker" && -z "$start_marker" ]]; then
  echo "verify-kcov-exclusions: both exclusions are off, so no marker needs verifying."
  exit 0
fi

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "::error::verify-kcov-exclusions: no report at '${REPORT_PATH}'. Run this after the coverage action, and set REPORT_PATH when the outdir differs." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# kcov writes each measured path relative to the common prefix of the traced
# files, and records that prefix in <sources>. Reading it from the report keeps
# this guard independent of the directory it runs in.
base="$(sed -n 's:.*<source>\(.*\)</source>.*:\1:p' "$REPORT_PATH" | head -n 1 || true)"
base="${base%/}"
if [[ -z "$base" ]]; then base="/"; fi

# One "path<TAB>line<TAB>hits" row per measured line. <lines> is a container and
# <line .../> is an entry, so the entry pattern needs its trailing space.
measured="$work/measured.tsv"
awk '
  /<class / {
    if (match($0, /filename="[^"]*"/)) file = substr($0, RSTART + 10, RLENGTH - 11)
    next
  }
  /<line / {
    if (file == "") next
    if (!match($0, /number="[0-9]+"/)) next
    n = substr($0, RSTART + 8, RLENGTH - 9)
    if (!match($0, /hits="[0-9]+"/)) next
    h = substr($0, RSTART + 6, RLENGTH - 7)
    print file "\t" n "\t" h
  }
' "$REPORT_PATH" > "$measured"

files="$(cut -f1 "$measured" | sort -u)"
if [[ -z "$files" ]]; then
  echo "::error::verify-kcov-exclusions: '${REPORT_PATH}' holds no measured line, so the markers cannot be verified." >&2
  exit 1
fi

# Print "<kind><TAB><line>" for every marked line in one file, with "line" for a
# line-marker match and "region" for a region match. The caller counts the two
# kinds apart, so it can tell an exclusion that matched nothing from one that
# matched only the other kind. A region runs from its start marker through its
# end marker, both included, which is the span kcov skips.
find_marked_lines() {
  local file="$1"

  if [[ -n "$line_marker" ]]; then
    grep -nF -- "$line_marker" "$file" | cut -d: -f1 | awk '{ print "line\t" $0 }' || true
  fi

  if [[ -n "$start_marker" ]]; then
    MARK_START="$start_marker" MARK_END="$end_marker" awk '
      BEGIN { s = ENVIRON["MARK_START"]; e = ENVIRON["MARK_END"] }
      {
        if (index($0, s) > 0) inRegion = 1
        if (inRegion) print "region\t" NR
        if (index($0, e) > 0) inRegion = 0
      }' "$file"
  fi
}

checked=0
line_checked=0
region_checked=0
resolved=0
unresolved=0
violations=0

while IFS= read -r relative; do
  if [[ -z "$relative" ]]; then continue; fi

  if [[ "$relative" == /* ]]; then
    path="$relative"
  else
    path="${base}/${relative}"
  fi

  if [[ ! -f "$path" ]]; then
    unresolved=$((unresolved + 1))
    continue
  fi
  resolved=$((resolved + 1))

  while IFS=$'\t' read -r kind number; do
    if [[ -z "$number" ]]; then continue; fi
    checked=$((checked + 1))

    case "$kind" in
      line) line_checked=$((line_checked + 1)) ;;
      region) region_checked=$((region_checked + 1)) ;;
    esac

    hits="$(awk -F'\t' -v f="$relative" -v n="$number" '$1 == f && $2 == n { print $3; exit }' "$measured")"
    if [[ "$hits" == "0" ]]; then
      echo "::error file=${path},line=${number}::kcov reported this marked line with zero hits, so its exclusion marker did not apply."
      violations=$((violations + 1))
    fi
  done < <(find_marked_lines "$path" | sort -t$'\t' -k2,2n -k1,1 -u)
done <<< "$files"

# Every path failing to resolve points at a base mismatch rather than at a
# marker problem, and passing here would report green while checking nothing.
if [[ "$resolved" -eq 0 ]]; then
  echo "::error::verify-kcov-exclusions: the report lists ${unresolved} measured file(s) and none resolve under '${base}'. The report and the working tree disagree." >&2
  exit 1
fi

# An enabled marker that matched no line in any resolved file skipped its whole
# comparison, so passing here would report green while proving nothing about that
# exclusion. This is the false pass the base check above closes for a path
# mismatch, and it belongs on the same footing. The marker value comes from the
# environment for the reason in the header: a literal in this source would erase
# the guard from the report it runs against.
if [[ -n "$line_marker" && "$line_checked" -eq 0 ]]; then
  echo "::error::verify-kcov-exclusions: EXCLUDE_LINE ('${line_marker}') matches no line in the ${resolved} measured file(s) that resolved under '${base}'. Check the marker value against the measured set." >&2
  exit 1
fi

if [[ -n "$start_marker" && "$region_checked" -eq 0 ]]; then
  echo "::error::verify-kcov-exclusions: EXCLUDE_REGION ('${start_marker}:${end_marker}') matches no line in the ${resolved} measured file(s) that resolved under '${base}'. Check the marker value against the measured set." >&2
  exit 1
fi

if [[ "$violations" -gt 0 ]]; then
  echo "::error::verify-kcov-exclusions: ${violations} marked line(s) still read as uncovered." >&2
  exit 2
fi

echo "verify-kcov-exclusions: ${checked} marked line(s) across ${resolved} measured file(s) are absent from the report."
