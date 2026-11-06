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
cutoff=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')

# GitHub removed GET /orgs/{org}/actions/runs from the REST API, so enumerate
# the org's repositories via the search API and scan each repo individually.
repos=$(gh api "search/repositories?q=org%3A$ORG+fork:false&per_page=100" --paginate \
  -q '.items[].name')

if [ -z "$repos" ]; then
  # Fallback: use the checked-in registry (format: "<repo> <active|ignore|hub>").
  repos=$(grep -vE '^(#|$)' automation/repos.txt | awk '{print $1}')
fi

if [ -z "$repos" ]; then
  echo "Could not enumerate repositories for org $ORG."
  exit 1
fi

failures=""
skipped=""
for repo in $repos; do
  # The created filter caps results at 1,000; flag an incomplete scan rather
  # than silently treating a truncated result as complete.
  repo_failures=$(gh api "repos/$ORG/$repo/actions/runs?created=%3E$since_created&per_page=100" --paginate \
    -q 'if .total_count > 1000 then error("Workflow run search exceeds the 1,000-result limit")
        else .workflow_runs[]
        | select(.conclusion == "failure")
        | [.repository.name, .name, .html_url, .updated_at]
        | @tsv end' \
    | awk -F'\t' -v cutoff="$cutoff" '$4 > cutoff' \
    | cut -f1-3) || { skipped="$skipped $repo"; continue; }
  if [ -n "$repo_failures" ]; then
    failures="${failures}${repo_failures}"$'\n'
  fi
done

if [ -n "$skipped" ]; then
  echo "Warning: could not scan:$skipped" >&2
fi

failures="${failures%%$'\n'}"

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
