#!/usr/bin/env bash
set -euo pipefail

# Report links in the given paths that point to private, link-local, or
# loopback targets - the URLs lychee silently skips under --exclude-all-private.
#
# run.sh invokes lychee with --exclude-all-private so the action never contacts
# an internal host when it runs on pull_request events over contributor-
# controlled markdown. lychee does not report which URLs it excluded, so this
# scan re-discovers them: it extracts candidate http(s) URLs from the same
# paths run.sh hands to lychee, classifies each host as a private, link-local,
# loopback, or localhost address, and writes the unique matches to a comment
# file for action.yml to post. The step never fails; the report is
# informational.
#
# Inputs (env):
#   PATHS              space-separated paths or globs to scan (default: **/*.md)
#   WORKING_DIRECTORY  directory to scan in (default: .)
#   GITHUB_OUTPUT      file to append step outputs to (default: /dev/null)

cd "${WORKING_DIRECTORY:-.}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

# File discovery mirrors run.sh: the same PATHS globs lychee resolves, hidden
# directories included (its --hidden flag) and node_modules excluded (its
# --exclude-path flag). Resolution uses find rather than the shell globstar
# option, which is unavailable on the macOS /bin/bash 3.2 the test suite runs
# under; instead each file path is tested against the glob with [[ == ]], where
# "*" already crosses "/". A glob still needs to see root-level files (globset
# lets "**/" match zero directories), so a "**/" prefix is retried stripped.
IFS=' ' read -r -a PATH_ARGS <<< "${PATHS:-**/*.md}"

files=()

collect_file() {
  local f="$1"
  case "/$f" in
    */node_modules/*) return ;;
  esac
  files+=("$f")
}

collect_matches() {
  local pattern="$1" stripped="" f
  if [[ "$pattern" == '**/'* ]]; then
    stripped="${pattern#\*\*/}"
  fi
  if [[ -d "$pattern" ]]; then
    while IFS= read -r -d '' f; do
      collect_file "$f"
    done < <(find "$pattern" -type f -print0)
  elif [[ -f "$pattern" ]]; then
    collect_file "$pattern"
  else
    # Glob: test every file under the working directory against the pattern.
    while IFS= read -r -d '' f; do
      f="${f#./}"
      # shellcheck disable=SC2053  # unquoted RHS is an intentional glob match
      if [[ "$f" == $pattern || ( -n "$stripped" && "$f" == $stripped ) ]]; then
        collect_file "$f"
      fi
    done < <(find . -type f -print0)
  fi
}

for pattern in "${PATH_ARGS[@]}"; do
  collect_matches "$pattern"
done

# is_private_host <host>: exit 0 when the host is a private, link-local,
# loopback, or localhost address. Hostnames other than localhost are never
# resolved, so a host that merely resolves to a private IP is not reported.
is_private_host() {
  local h="$1" group o1 o2
  h="$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')"
  if [[ "$h" == \[*\]* ]]; then
    h="${h%%]*}"
    h="${h#[}"
  fi
  if [[ "$h" == *:* ]]; then
    # IPv6 literal. Loopback is ::1; fc00::/7 is unique-local; fe80::/10 is
    # link-local.
    case "$h" in
      ::1 | ::1:* | 0:0:0:0:0:0:0:1*) return 0 ;;
    esac
    group="${h%%:*}"
    case "$group" in
      fc* | fd*) return 0 ;;
      fe8* | fe9* | fea* | feb*) return 0 ;;
    esac
    return 1
  fi
  [[ "$h" == localhost ]] && return 0
  [[ "$h" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  o1="${h%%.*}"
  o2="${h#*.}"
  o2="${o2%%.*}"
  [[ "$o1" == 10 ]] && return 0                         # 10.0.0.0/8
  [[ "$o1" == 127 ]] && return 0                        # 127.0.0.0/8
  if [[ "$o1" == 172 ]] && (( 10#$o2 >= 16 && 10#$o2 <= 31 )); then
    return 0                                            # 172.16.0.0/12
  fi
  [[ "$o1" == 192 && "$o2" == 168 ]] && return 0        # 192.168.0.0/16
  [[ "$o1" == 169 && "$o2" == 254 ]] && return 0        # 169.254.0.0/16
  return 1
}

# Trailing punctuation a bare URL token can carry from prose. Held in a
# variable rather than inlined into a [[ ]] test: an unquoted ";" inside a
# bracket expression is a conditional-expression parse error, whereas a
# variable's value is only expanded at pattern-match time.
url_punct='[.,;:!?]'

# classify_url <url>: exit 0 when the URL's host is a private target.
classify_url() {
  local url="$1" host
  url="${url#*://}"
  host="${url%%[/?#]*}"
  host="${host##*@}"
  if [[ "$host" != \[*\]* ]]; then
    # Drop a trailing numeric port, then sentence punctuation, so a bare URL
    # ending in "." or "," still classifies from its host.
    host="${host%:[0-9]*}"
    while [[ "$host" == *$url_punct ]]; do
      host="${host%?}"
    done
  fi
  is_private_host "$host"
}

# Candidate URLs stop at whitespace and Markdown/HTML delimiters.
url_re='https?://[^[:space:]"`<>)]+'

private_urls=()
if (( ${#files[@]} > 0 )); then
  while IFS= read -r raw; do
    if classify_url "$raw"; then
      # Trim sentence punctuation from the token kept for display/dedup. A
      # closing paren cannot end the token (url_re excludes it), so the set
      # matches url_punct.
      while [[ "$raw" == *$url_punct ]]; do
        raw="${raw%?}"
      done
      private_urls+=("$raw")
    fi
  done < <(grep -hoiE "$url_re" "${files[@]}")
fi

if (( ${#private_urls[@]} == 0 )); then
  echo "validate-links: no links to private, link-local, or loopback targets found"
  exit 0
fi

unique=()
while IFS= read -r url; do
  unique+=("$url")
done < <(printf '%s\n' "${private_urls[@]}" | sort -u)

echo "validate-links: ${#unique[@]} link(s) to private, link-local, or loopback targets were excluded from checking:"
printf '  %s\n' "${unique[@]}"

comment_file="$(mktemp)"
{
  printf '## Private-target links not checked\n\n'
  printf 'These links point to private, link-local, or loopback targets. The '
  printf 'checker never contacts internal hosts, so they were excluded from '
  printf 'verification:\n\n'
  for url in "${unique[@]}"; do
    echo "- \`$url\`"
  done
} > "$comment_file"

echo "comment-file=$comment_file" >> "$GITHUB_OUTPUT"
