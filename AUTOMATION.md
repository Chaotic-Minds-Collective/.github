# Org Workflow Automation (chaos-workflow-automator)

This repo (.github) is the automation hub for the Chaotic-Minds-Collective organization.

## Architecture in one minute

- Every repo gets one tiny file (.github/workflows/ci.yml) that calls the shared workflow here.
- The shared workflow lives here and is the single source of truth.
- A bot scans the org every 4 hours; any repo missing CI gets a ready-to-merge PR.
- A daily monitor reports every failed workflow run in the org to Discord.

## Files

- .github/workflows/shared-ci.yml - reusable CI: install, lint, build, test (auto-skips steps that are not defined in package.json)
- .github/workflows/notify-failure.yml - reusable Discord alert, runs only when CI fails
- .github/workflows/deploy-pages.yml - reusable build + deploy to GitHub Pages (opt-in per repo)
- .github/workflows/onboard.yml - scheduled every 4 hours, also runnable by hand from the Actions tab
- .github/workflows/monitor.yml - scheduled daily at 6am Pacific
- automation/repos.txt - repo registry: active / ignore / hub
- automation/templates/ci.yml.tmpl - the caller file the bot adds to each repo
- automation/scripts/onboard.sh - the scanner that opens onboarding PRs
- automation/scripts/monitor.sh - the daily failure reporter

## Changing CI for the whole org

Edit shared-ci.yml here (feature branch + PR as always). Once merged, every repo using the caller gets the new behavior on its next push. No per-repo changes needed.

## Turning CI on in a repo

Nothing to do by hand. The bot opens a PR titled: ci: add shared org CI workflow. Review it, merge it, done. To exclude a repo, add its name followed by the word ignore to automation/repos.txt here.

## One-time setup (org owner, free)

1. Create a fine-grained personal access token at github.com/settings/personal-access-tokens
   - Resource owner: Chaotic-Minds-Collective
   - Repository access: All repositories
   - Permissions: Contents read/write, Pull requests read/write, Workflows read/write, Actions read-only, Metadata read-only
2. Add org secrets at github.com/organizations/Chaotic-Minds-Collective/settings/secrets/actions
   - ORG_AUTOMATION_TOKEN - the token from step 1 (lets the bot open PRs in other repos)
   - DISCORD_WEBHOOK_URL - a Discord webhook (Discord: Server Settings > Integrations > Webhooks > New Webhook, copy the URL)

Until both secrets exist, the bot and monitor skip themselves safely instead of failing.

## Rules

- Workflow files in individual repos are callers only; never edit behavior there.
- All hub changes go through a feature branch and PR.
