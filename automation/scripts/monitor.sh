#!/usr/bin/env bash
set -euo pipefail

ORG='Chaotic-Minds-Collective'

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo 'DISCORD_WEBHOOK_URL not configured - skipping alert.'
  exit 0
fi

since=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')

failures=$(gh api "orgs/$ORG/actions/runs?created=%3E$since&per_page=100" --paginate \
  -q '.workflow_runs[] | select(.conclusion == "failure") | [.repository_name, .name, .html_url] | @tsv' \
  || true)

if [ -z "$failures" ]; then
  echo 'No failed workflow runs in the last 24 hours. Nothing to report.'
  exit 0
fi

text="**Org workflow failures, last 24h:**"$'\n'"$failures"
payload=$(printf '%s' "$text" | jq -Rs '{content: .}')
curl -sf -X POST "$DISCORD_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload" > /dev/null

echo 'Failure report sent to Discord.'
