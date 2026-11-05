#!/usr/bin/env bash
set -euo pipefail

ORG='Chaotic-Minds-Collective'

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo 'DISCORD_WEBHOOK_URL not configured - skipping alert.'
  exit 0
fi

# Scan window is wider than the report window (48h by creation time) so that
# runs created just before the previous scan but finished after it are still
# caught by the updated_at filter below.
since_created=$(date -u -d '48 hours ago' '+%Y-%m-%dT%H:%M:%SZ')

failures=$(gh api "orgs/$ORG/actions/runs?created=%3E$since_created&per_page=100" --paginate \
  -q '.workflow_runs[]
      | select(.conclusion == "failure" and (.updated_at > (now - 86400 | todateiso8601)))
      | [.repository.name, .name, .html_url] | @tsv')

if [ -z "$failures" ]; then
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
