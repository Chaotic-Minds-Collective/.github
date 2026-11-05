#!/usr/bin/env bash
set -euo pipefail

ORG='Chaotic-Minds-Collective'
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/repos.txt"
TEMPLATE="$ROOT/templates/ci.yml.tmpl"
NOTIFY_TEMPLATE="$ROOT/templates/ci-notify.yml.tmpl"

list_repos() {
  gh api "orgs/$ORG/repos?per_page=100" --paginate \
    -q '.[] | select(.archived == false) | .name'
}

configured() {
  awk -v r="$1" '$1 == r { print $2 }' "$CONFIG" | head -n 1
}

node_version() {
  local v
  v=$(awk -v r="$1" '$1 == r { print $3 }' "$CONFIG" | head -n 1)
  echo "${v:-20}"
}

created=0
covered=0
skipped=0

for repo in $(list_repos); do
  if [ "$repo" = '.github' ]; then
    continue
  fi

  action=$(configured "$repo")
  if [ "$action" = 'ignore' ]; then
    echo "$repo: ignore"
    continue
  fi

  # Count files in .github/workflows. On any API failure or non-numeric
  # output treat the count as 0 so the repo is NOT silently marked covered.
  wf_count=$(gh api "repos/$ORG/$repo/contents/.github/workflows" \
    -q 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)
  case "$wf_count" in
    (*[!0-9]*|'') wf_count=0 ;;
  esac
  if [ "$wf_count" -gt 0 ]; then
    echo "$repo: covered ($wf_count workflow file(s))"
    covered=$((covered+1))
    continue
  fi

  if ! gh api "repos/$ORG/$repo/contents/package.json" > /dev/null 2>&1; then
    echo "$repo: package.json check failed (missing or API error) - skipping"
    skipped=$((skipped+1))
    continue
  fi

  branch='onboarding/ci'
  open_prs=$(gh api "repos/$ORG/$repo/pulls?head=$ORG:$branch&state=open" -q 'length')
  if [ "$open_prs" != '0' ]; then
    echo "$repo: onboarding PR already open - skipping"
    continue
  fi

  default_branch=$(gh api "repos/$ORG/$repo" -q '.default_branch')
  base_sha=$(gh api "repos/$ORG/$repo/git/ref/heads/$default_branch" -q '.object.sha')

  # Delete a stale onboarding branch from a previously closed PR before
  # recreating it, so one leftover ref cannot abort the whole run.
  if gh api "repos/$ORG/$repo/git/ref/heads/$branch" > /dev/null 2>&1; then
    gh api -X DELETE "repos/$ORG/$repo/git/refs/heads/$branch" > /dev/null
  fi

  gh api -X POST "repos/$ORG/$repo/git/refs" \
    -f "ref=refs/heads/$branch" -f "sha=$base_sha" > /dev/null

  nodev=$(node_version "$repo")
  ci_content=$(sed -e "s|__NODE_VERSION__|$nodev|" -e "s|__DEFAULT_BRANCH__|$default_branch|" "$TEMPLATE" | base64 -w0)
  notify_content=$(base64 -w0 "$NOTIFY_TEMPLATE")

  gh api -X PUT "repos/$ORG/$repo/contents/.github/workflows/ci.yml" \
    -f 'message=ci: add shared org CI workflow' \
    -f "branch=$branch" \
    -f "content=$ci_content" > /dev/null

  gh api -X PUT "repos/$ORG/$repo/contents/.github/workflows/ci-notify.yml" \
    -f 'message=ci: add trusted failure notification workflow' \
    -f "branch=$branch" \
    -f "content=$notify_content" > /dev/null

  gh pr create \
    -R "$ORG/$repo" \
    --head "$branch" \
    --base "$default_branch" \
    --title 'ci: add shared org CI workflow' \
    --body 'Adds two thin callers that use the shared org workflows from the .github repo: ci.yml (CI on push/PR) and ci-notify.yml (trusted workflow_run-based Discord alert on CI failure, which also covers fork and Dependabot PR runs). Review and merge to enable standardized CI. See AUTOMATION.md in the .github repo.'

  echo "$repo: onboarding PR opened"
  created=$((created+1))
done

echo "Done. Onboarding PRs opened: $created. Repos already covered: $covered. Skipped (package.json check failed): $skipped."
