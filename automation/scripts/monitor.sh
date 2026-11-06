#!/usr/bin/env bash
# Daily workflow-failure monitor.
#
# Scans every registered 'active' repo for failed workflow runs in the last
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
since_created=$(date -u -d '48 hours ago' '+%Y-%m-%dT%H:%M:%SZ')

failures=""
skipped=""

while read -r line; do
  repo=$(printf '%s' "$line" | awk '{print $1}')
  status=$(printf '%s' "$line" | awk '{print $2}')
  [ -z "$repo" ] && continue
  case "$repo" in \#*) continue ;; esac
  [ "$status" != "active" ] && continue

  runs=$(gh api "repos/$ORG/$repo/actions/runs?created=%3E$since_created&per_page=100" --paginate \
    -q '.workflow_runs[]
        | select(.conclusion == "failure" and (.updated_at > (now - 86400 | todateiso8601)))
        | [.repository.name, .name, .html_url] | @tsv' 2>/dev/null)

  if [ -n "$runs" ]; then
    failures="${failures}${runs}
"
  elif [ $? -ne 0 ]; then
    skipped="${skipped} ${repo}"
  fi
done < "$REGISTRY"

if [ -n "$skipped" ]; then
  echo "WARNING: could not scan the following repos (missing token permission or repo not found):$skipped"
fi

if [ -z "$(printf '%s' "$failures" | tr -d '\n ')" ]; then
  echo 'No failed workflow runs in the last 24 hours. Nothing to report.'
  exit 0
fi

send_chunk() {
  local header="$1" body="$2" payload
  payload=$(jq -n --arg h "$header" --arg b "$body" '{content: ($h + "\n" + $b)}')
  curl -sf -X POST "$DISCORD_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload" > /dev/null
}

# Discord rejects messages over 2000 characters - chunk the report.
count=0
body=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if [ -n "$body" ] && [ $(( ${#body} + ${#line} )) -gt 1800 ]; then
    count=$((count+1))
    send_chunk "**Org workflow failures, last 24h (part $count):**" "$body"
    body=""
  fi
  body="${body:+$body
}$line"
done <<< "$failures"

if [ -n "$body" ]; then
  count=$((count+1))
  if [ "$count" -eq 1 ]; then
    send_chunk "**Org workflow failures, last 24h:**" "$body"
  else
    send_chunk "**Org workflow failures, last 24h (part $count):**" "$body"
  fi
fi

echo "Failure report sent to Discord ($count message(s))."
