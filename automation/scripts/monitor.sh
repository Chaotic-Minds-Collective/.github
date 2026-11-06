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
# Paginate through every page of results; keep only non-fork repositories.
# Reject incomplete pages even when they contain items, discarding partial lists.
discovery_failed=0
if ! repos=$(gh api --paginate "search/repositories?q=org%3A$ORG+fork:false&per_page=100" \
  | jq -sr 'if length > 0 and all(.[]; .incomplete_results == false) then
      .[].items[] | select(.fork == false) | .name
    else error("repository search response is incomplete or missing incomplete_results") end' \
  | sort -u); then
  discovery_failed=1
  repos=""
fi

if [ -z "$repos" ]; then
  if [ "$discovery_failed" -eq 1 ]; then
    echo "Warning: repository discovery failed; using registry fallback." >&2
  else
    echo "Warning: repository search returned no repositories; using registry fallback." >&2
  fi
  # Fallback: use the checked-in registry (format: "<repo> <active|ignore|hub>")
  # when search fails or the complete paginated result is empty.
  repos=$(grep -vE '^(#|$)' automation/repos.txt | awk '{print $1}')
fi

if [ -z "$repos" ]; then
  echo "Could not enumerate repositories for org $ORG."
  exit 1
fi

# Print failure TSV lines (repo, name, url, updated_at) for one repository,
# following every page of its workflow runs. Returns 1 if the repo cannot be
# scanned completely due to a request or response error.
scan_repo() {
  local repo="$1" page=1 total=0 count resp
  while :; do
    if ! resp=$(gh api "repos/$ORG/$repo/actions/runs?created=%3E$since_created&per_page=100&page=$page"); then
      return 1
    fi
    if ! count=$(jq -e '.workflow_runs | if type == "array" then length else error("workflow_runs must be an array") end' <<<"$resp"); then
      return 1
    fi
    if ! jq -r '.workflow_runs[]
        | select(.conclusion == "failure")
        | [.repository.name, .name, .html_url, .updated_at]
        | @tsv' <<<"$resp"; then
      return 1
    fi
    total=$((total + count))
    # This endpoint returns at most 1,000 runs per query; hitting that many
    # means any deeper pages are unreachable, so the scan may be incomplete.
    if [ "$total" -ge 1000 ]; then
      echo "Warning: $repo has 1,000+ runs in the scan window; its scan may be incomplete." >&2
      break
    fi
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
  done
}

failures=""
skipped=""
for repo in $repos; do
  if ! repo_failures=$(scan_repo "$repo" \
      | awk -F'\t' -v cutoff="$cutoff" '$4 > cutoff' \
      | cut -f1-3); then
    skipped="$skipped $repo"
    continue
  fi
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
