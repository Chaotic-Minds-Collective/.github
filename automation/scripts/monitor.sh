#!/usr/bin/env bash
# Daily workflow-failure monitor.
#
# Scans active repos (including unlisted repos) and the hub for failures in the last
# 24 hours and posts a report to Discord.
#
# NOTE: Fine-grained PATs cannot read org-level Actions endpoints
# (/orgs/{org}/actions/runs returns 404), so we query each repo's own
# runs endpoint instead. A repo-level failure is logged and skipped, not
# fatal, so one missing/inaccessible repo never kills the whole scan.
set -uo pipefail

ORG='Chaotic-Minds-Collective'
REGISTRY="$(dirname "$0")/../repos.txt"

if [ -z "${GH_TOKEN:-}" ]; then
  echo 'GH_TOKEN not configured - cannot scan.'
  exit 1
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo 'DISCORD_WEBHOOK_URL not configured - skipping alert.'
  exit 0
fi

# Scan window is wider than the report window (48h by creation time) so that
# runs created just before the previous scan but finished after it are still
# caught by the updated_at filter below.
since_created=$(date -u -d '48 hours ago' '+%Y-%m-%dT%H:%M:%SZ') || exit $?

failures=""
skipped=""

# Match onboarding's discovery of non-archived repos. Keep registered active
# repos as candidates too, and always scan the automation hub.
discovered=$(gh api "orgs/$ORG/repos?per_page=100" --paginate \
  -q '.[] | select(.archived == false) | .name') || exit $?
registered=$(awk '$1 !~ /^#/ && $2 == "active" {print $1}' "$REGISTRY") || exit $?
repos=$(printf '%s\n' "$discovered" "$registered" '.github' | sort -u) || exit $?

while read -r repo; do
  [ -z "$repo" ] && continue
  status=$(awk -v r="$repo" '$1 == r {print $2; exit}' "$REGISTRY") || exit $?
  if [ "$repo" != '.github' ] && [ "${status:-active}" != 'active' ]; then
    continue
  fi

  runs=$(gh api "repos/$ORG/$repo/actions/runs?created=%3E$since_created&per_page=100" --paginate \
    -q '.workflow_runs[]
        | select(.conclusion == "failure" and (.updated_at > (now - 86400 | todateiso8601)))
        | [.repository.name, .name, .html_url] | @tsv' 2>/dev/null)

  runs_status=$?
  if [ "$runs_status" -ne 0 ]; then
    skipped="${skipped} ${repo}"
    failures="${failures}${repo}: not scanned (repository scan failed).
"
    continue
  fi

  if [ -n "$runs" ]; then
    failures="${failures}${runs}
"
  fi
done <<< "$repos"

if [ -n "$skipped" ]; then
  echo "WARNING: could not scan the following repos (missing token permission or repo not found):$skipped"
fi

if [ -z "$(printf '%s' "$failures" | tr -d '\n ')" ]; then
  echo 'No failed workflow runs in the last 24 hours. Nothing to report.'
  exit 0
fi

# send_chunk HEADER BODY - POST one Discord message. Captures the HTTP status
# code and response body so a rejected webhook produces a diagnosable error
# instead of a bare curl exit code. Never echoes DISCORD_WEBHOOK_URL. Any
# failure here is fatal: the workflow must not report success when the report
# was not sent.
send_chunk() {
  local header="$1" body="$2" payload http_code tmp
  payload=$(jq -n --arg h "$header" --arg b "$body" '{content: ($h + "\n" + $b)}') || return $?
  tmp=$(mktemp)
  http_code=$(curl -sS -o "$tmp" -w '%{http_code}' -X POST "$DISCORD_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload")
  if [ $? -ne 0 ] || [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "ERROR: Discord webhook POST failed (HTTP $http_code): $(head -c 300 "$tmp")" >&2
    rm -f "$tmp"
    return 22
  fi
  rm -f "$tmp"
}

# Discord rejects messages over 2000 characters - chunk the report.
count=0
body=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if [ -n "$body" ] && [ $(( ${#body} + ${#line} )) -gt 1800 ]; then
    count=$((count+1))
    send_chunk "**Org workflow failures, last 24h (part $count):**" "$body" || exit $?
    body=""
  fi
  body="${body:+$body
}$line"
done <<< "$failures"

if [ -n "$body" ]; then
  count=$((count+1))
  if [ "$count" -eq 1 ]; then
    send_chunk "**Org workflow failures, last 24h:**" "$body" || exit $?
  else
    send_chunk "**Org workflow failures, last 24h (part $count):**" "$body" || exit $?
  fi
fi

echo "Failure report sent to Discord ($count message(s))."
