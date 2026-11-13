# Brand and Repository Naming Standard

This document defines the approved brand identities, abbreviations, repository naming conventions, and repository rename map for the Chaotic Minds Collective organization.

## Brand identities

| Brand | Prefix | Scope |
|---|---|---|
| Chaotic Minds Collective | `CMC` | Parent organization, shared infrastructure, collective websites, and organization-wide resources |
| Chaotic Minds Gaming | `CMG` | Gaming platforms, game integrations, plugins, mods, bots, SDKs, and gaming documentation |
| Chaotic Minds Command | `CC` | Discord management, command products, administration, and workflow automation |
| Chaotic Minds Solutions | `CMS` | Software solutions and services |
| Chaotic Minds Creations | `CMR` | Creative projects and ventures |

Use the full brand name in public-facing prose on first mention. Use the approved prefix in repository names, package scopes, identifiers, and concise technical references where appropriate.

## Repository naming convention

Use lowercase kebab-case. Prefer:

- `<brand>-<project>-site` for websites.
- `<brand>-<project>-app` for applications.
- `<brand>-<project>-plugin` for game plugins and integrations.
- `<brand>-<project>-docs` for product documentation.
- `<brand>-<project>-handbook` for organization-wide guidance.
- `<brand>-<project>-bot` for bots.
- `<brand>-<project>-automator` for automation tools.
- Established technical terms such as `sdk`, `mcp`, and `docs` may serve as the descriptor when they already identify the repository's function.

Do not add a suffix mechanically when the repository name already has a clear, established technical descriptor. Keep `.github` unchanged because GitHub requires that special repository name for organization-wide community health files and profile content.

## Approved repository rename map

The following names are the approved targets. The current names are included to make the transition auditable.

| # | Current repository | Approved repository name | Brand / purpose |
|---:|---|---|---|
| 1 | `ChaoticAtlasResourceMap` | `cmg-atlas-resource-map-plugin` | CMG plugin |
| 2 | `chaotic-atlas-restart-overlay` | `cmg-atlas-restart-overlay-plugin` | CMG plugin |
| 3 | `chaotic-atlas-status-host` | `cmg-atlas-status-host-plugin` | CMG plugin |
| 4 | `chaotic-admin-console` | `cmg-admin-console-plugin` | CMG plugin |
| 5 | `chaotic-atlas-admin` | `cmg-atlas-admin-plugin` | CMG plugin |
| 6 | `whats_poppin_app` | `cmc-whats-popping-app-site` | CMC app/site |
| 7 | `PARAN-App` | `cmc-paran-app-site` | CMC app/site |
| 8 | `chaotic-gaming` | `cmg-gaming-site` | CMG website |
| 9 | `grease-dojo` | `cmc-grease-dojo-site` | CMC website |
| 10 | `docs` | `cmc-collective-handbook` | CMC handbook |
| 11 | `chaotic-command` | `cc-command-site` | CC website |
| 12 | `chaotic-command-docs` | `cc-command-docs` | CC documentation |
| 13 | `chaos-workflow-automator` | `cc-workflow-automator` | CC automation |
| 14 | `agent-visibility-template` | `cmc-agent-visibility-template` | CMC shared template |
| 15 | `chaotic-solutions-site` | `cms-solutions-site` | CMS website |
| 16 | `chaotic-minds-collective` | `cmc-collective-site` | CMC website |
| 17 | `.github` | `.github` | GitHub organization metadata |
| 18 | `chaotic-minds-mcp` | `cmc-mcp-server` | CMC shared MCP server |
| 19 | `glitch-bot` | `cmg-discord-glitch-bot` | CMG Discord bot |
| 20 | `chaotic-gaming-ark` | `cmg-ark-plugin` | CMG game plugin |
| 21 | `chaotic-minds-gaming-atlas` | `cmg-atlas-plugin` | CMG game plugin |
| 22 | `chaotic-gaming-7dtd` | `cmg-7dtd-plugin` | CMG game plugin |
| 23 | `chaotic-minds-gaming-atlas-core` | `cmg-atlas-core-plugin` | CMG core plugin |
| 24 | `chaotic-gaming-sdk` | `cmg-sdk` | CMG SDK |
| 25 | `chaotic-gaming-docs` | `cmg-docs` | CMG documentation |
| 26 | `chaotic-gaming-atlas-tribes` | `cmg-atlas-tribes-plugin` | CMG plugin |
| 27 | `chaotic-gaming-atlas-commerce` | `cmg-atlas-commerce-plugin` | CMG plugin |
| 28 | `chaotic-gaming-atlas-connect` | `cmg-atlas-connect-plugin` | CMG plugin |
| 29 | `chaotic-gaming-atlas-player` | `cmg-atlas-player-plugin` | CMG plugin |
| 30 | `chaotic-gaming-atlas-world` | `cmg-atlas-world-plugin` | CMG plugin |
| 31 | `chaotic-gaming-atlas-sentinel` | `cmg-atlas-sentinel-plugin` | CMG plugin |
| 32 | `chaotic-gaming-atlas-gridforge` | `cmg-atlas-gridforge-plugin` | CMG plugin |
| 33 | `chaotic-gaming-atlas-adventures` | `cmg-atlas-adventures-plugin` | CMG plugin |

## Migration requirements

Repository renames and documentation updates must be coordinated rather than performed as blind global replacements.

For each repository:

1. Preserve Git history, authorship, issues, pull requests, releases, tags, and existing branches.
2. Update the README, project title, repository description, badges, and documentation navigation.
3. Review package names, namespaces, package scopes, and published metadata where applicable.
4. Update internal repository links, cross-repository references, submodules, automation, CI workflows, deployment configuration, and integration references.
5. Review website URLs, webhook endpoints, API references, and external integrations before changing identifiers.
6. Search for old repository names and old brand names; classify each occurrence before changing it.
7. Run the repository's existing checks and tests after changes.
8. Submit changes for review. Do not merge or deploy without separate authorization.

GitHub repository slug changes should be performed through repository settings or an authorized GitHub repository-administration operation. After each rename, verify GitHub redirects and update canonical references rather than relying indefinitely on redirects. Update `automation/repos.txt` to the new slug immediately after each rename. The `.github/repo-descriptions.txt` manifest uses the approved target slugs; dispatch its manual description-update workflow only after the corresponding repository slugs exist.

## Brand usage notes

- The Discord Glitch Bot is part of Chaotic Minds Gaming and uses the `cmg-` prefix.
- Chaotic Minds Command uses `cc-`, Chaotic Minds Solutions uses `cms-`, and Chaotic Minds Creations uses `cmr-` when those brands have dedicated repositories.
- The parent organization prefix `cmc-` is used for shared, collective, and organization-wide resources.
- Do not use `CG` as the gaming brand abbreviation. The approved gaming abbreviation is `CMG`.
- Do not replace technical identifiers, third-party names, historical attribution, or author credits merely because they contain an old brand string.
