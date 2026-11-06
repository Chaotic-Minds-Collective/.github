#!/usr/bin/env bash
set -euo pipefail
ORG='Chaotic-Minds-Collective'; HUB='.github'; REG='automation/repos.txt'
# fail MESSAGE - print a fatal error to stderr and exit 1.
# Used only for report-flow failures: the workflow must fail rather than send
# a wrong, empty, or silently-dropped report.
fail(){ echo "Monitor failed: $1" >&2; exit 1; }
[ -n "${DISCORD_WEBHOOK_URL:-}" ] || { echo 'DISCORD_WEBHOOK_URL not configured - skipping alert.'; exit 0; }
# 48h scan window vs 24h report window; report-flow inputs are fatal.
since_created=$(date -u -d '48 hours ago' '+%Y-%m-%dT%H:%M:%SZ') || fail 'could not compute scan window'
cutoff=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ') || fail 'could not compute report cutoff'
# Org-level runs endpoint was removed from the API: enumerate repos via search,
# scan each individually. Unlisted repos default to active (onboarded).
if ! repos=$(gh api --paginate "search/repositories?q=org%3A$ORG+fork:false&per_page=100" 2>/dev/null \
    | jq -r '.items[] | select(.fork == false) | .name' | sort -u) || [ -z "$repos" ]; then
  echo 'Warning: repository search failed or empty; using registry fallback.' >&2
  repos=$(awk 'NF && $1 !~ /^#/ && $2 != "ignore" {print $1}' "$REG" 2>/dev/null) || repos=""
fi
[ -n "$repos" ] || fail 'could not enumerate repositories'
# Always scan the .github hub.
repos="$repos"$'\n'"$HUB"
# Registry ignore entries are never scanned, from any candidate list; dedupe.
if [ -s "$REG" ]; then
  repos=$(printf '%s\n' "$repos" \
    | awk 'NR==FNR{if($1!~/^#/&&$2=="ignore")ign[$1];next} NF&&!($0 in ign)&&!seen[$0]++' "$REG" -) || repos=""
fi
# scan_repo REPO - print failure TSV lines (repo,name,url,updated_at) for one
# repository, following every page of its workflow runs. Returns nonzero when
# the repository cannot be scanned; the caller treats that as non-fatal and
# records the repository as skipped.
scan_repo(){
  local repo="$1" page=1 total=0 count resp
  while :; do
    resp=$(gh api "repos/$ORG/$repo/actions/runs?created=%3E$since_created&per_page=100&page=$page" 2>/dev/null) || return 1
    jq -r '.workflow_runs[]|select(.conclusion=="failure")|[.repository.name,.name,.html_url,.updated_at]|@tsv' <<<"$resp" || return 1
    count=$(jq 'if (.workflow_runs|type)=="array" then .workflow_runs|length else error("workflow_runs must be an array") end' <<<"$resp") || return 1
    case "$count" in ''|*[!0-9]*) return 1;; esac
    total=$((total+count))
    [ "$total" -ge 1000 ] && { echo "Warning: $repo has 1,000+ runs in the scan window; its scan may be incomplete." >&2; break; }
    [ "$count" -lt 100 ] && break
    page=$((page+1))
  done
}
failures=""; skipped=""
while read -r line; do
  [ -n "$line" ] || continue
  status=0
  runs=$(scan_repo "$line") || status=$?
  # Capture the exit status above, check it before testing the output; on
  # failure the partial output is discarded and the repo is skipped (non-fatal).
  if [ "$status" -ne 0 ]; then skipped="$skipped $line"; continue; fi
  [ -n "$runs" ] || continue
  rf=$(printf '%s\n' "$runs" | awk -F'\t' -v c="$cutoff" '$4 > c' | cut -f1-3)
  [ -n "$rf" ] && failures="$failures$rf"$'\n'
done <<< "$repos"
# Skipped repositories are recorded in the report too: a failure-only exit
# would otherwise drop the Discord report entirely, hiding repos we could
# not scan. Keep the warning and mark them clearly in the report body.
if [ -n "$skipped" ]; then
  echo "Warning: could not scan:$skipped" >&2
  for s in $skipped; do
    failures="$failures$s"$'\t'"could not scan"$'\t'"(repository not scanned)"$'\n'
  done
fi
failures="${failures%$'\n'}"
[ -n "$failures" ] || { echo 'No failed workflow runs in the last 24 hours. Nothing to report.'; exit 0; }
# send_chunk HEADER BODY - POST one Discord message. Any failure here is
# fatal: the workflow must not report success when the report was not sent.
send_chunk(){
  local payload
  payload=$(jq -n --arg h "$1" --arg b "$2" '{content:($h+"\n"+$b)}') || fail 'could not build the Discord payload'
  curl -sf -X POST "$DISCORD_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload" >/dev/null || fail 'Discord rejected the report chunk'
}
count=0; body=""
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
  if [ "$count" -eq 1 ]; then send_chunk "**Org workflow failures, last 24h:**" "$body"
  else send_chunk "**Org workflow failures, last 24h (part $count):**" "$body"; fi
fi
echo "Failure report sent to Discord ($count message(s))."
