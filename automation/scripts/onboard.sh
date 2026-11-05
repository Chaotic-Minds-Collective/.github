#!/usr/bin/env bash
set -euo pipefail

ORG='Chaotic-Minds-Collective'
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/repos.txt"
TEMPLATE="$ROOT/templates/ci.yml.tmpl"

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

for repo in $(list_repos); do
  if [ "$repo" = '.github' ]; then
    continue
  fi

  action=$(configured "$repo")
  if [ "$action" = 'ignore' ]; then
    continue
  fi

  if gh api "repos/$ORG/$repo/contents/.github/workflows/ci.yml" > /dev/null 2>&1; then
    covered=$((covered+1))
    continue
  fi

  if ! gh api "repos/$ORG/$repo/contents/package.json" > /dev/null 2>&1; then
    echo "$repo: no package.json at root - skipping (add it to repos.txt if it needs CI another way)"
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

  gh api -X POST "repos/$ORG/$repo/git/refs" \
    -f "ref=refs/heads/$branch" -f "sha=$base_sha" > /dev/null

  nodev=$(node_version "$repo")
  content=$(sed -e "s|__NODE_VERSION__|$nodev|" -e "s|__DEFAULT_BRANCH__|$default_branch|" "$TEMPLATE" | base64 -w0)

  gh api -X PUT "repos/$ORG/$repo/contents/.github/workflows/ci.yml" \
    -f 'message=ci: add shared org CI workflow' \
    -f "branch=$branch" \
    -f "content=$content" > /dev/null

  gh pr create \
    -R "$ORG/$repo" \
    --head "$branch" \
    --base "$default_branch" \
    --title 'ci: add shared org CI workflow' \
    --body 'Adds the thin caller that runs the shared CI workflow from the org .github repo. Review and merge to enable standardized CI. See AUTOMATION.md in the .github repo.'

  echo "$repo: onboarding PR opened"
  created=$((created+1))
done

echo "Done. Onboarding PRs opened: $created. Repos already covered: $covered."
