---
name: catalog
description: Use when the user wants to add, remove, list, update or check skills, rules, hooks, MCP servers, plugins or CLI tools from their catalog (the Eminakkoc/skills index) — in this project or in ~/.claude — or asks to "check catalog updates" for the index's third-party sources.
---

# catalog

The user's skills, rules, hooks, MCP servers, plugins and CLI tools are listed in an
index repo (`Eminakkoc/skills`): `catalog/<type>/<name>.json` holds one file per item
(and `catalog/bundles/` one per bundle), `sources.json`
pins third-party upstreams. The `catalog` command (`~/.local/bin/catalog`)
does all installing, removing and updating.

**Never edit `.claude/settings.json`, `.mcp.json`, `.claude/skills/`,
`.claude/rules/`, `.claude/hooks/` or any `catalog.lock.json` by hand for
catalog items.** Run
`catalog` and show the user its output.

If `catalog` is not on PATH, tell the user to run:
`curl -fsSL https://raw.githubusercontent.com/Eminakkoc/skills/main/catalog.sh | bash -s -- setup`

## Using the catalog (any project)

| The user wants | Run |
|---|---|
| See what exists | `catalog list` |
| See what is installed here | `catalog list --installed` |
| Add items or a bundle to this project | `catalog add <item> ...` or `catalog add bundle:<name>` |
| Add to every project (user scope) | `catalog add --user <item>` |
| Remove | `catalog remove <item>` (`--user` for user scope) |
| Check a freshly cloned project | `catalog doctor --dry-run`, then `catalog doctor --yes` if they agree to install missing tools |
| Update installed items | `catalog update --dry-run`, show the changes, then `catalog update --yes` once they agree (this also refreshes the `catalog` command) |
| Update just the `catalog` command | `catalog self-update` |

Confirmations need a terminal, which you don't have: always show the
`--dry-run` result first and only pass `--yes` after the user agrees in chat.

Items have a scope. `user` items (prompt-expansion hooks, personal plugins)
belong in `~/.claude`; the command skips them for a project unless forced. Don't
pass `--force` unless the user asks for it.

After `catalog add` in a project, suggest committing `.claude/` and `.mcp.json`.
New plugins and MCP servers need a Claude Code restart to load.

## Checking the index for upstream updates (inside the index repo)

Run this only in a checkout of `Eminakkoc/skills`.

1. Run `catalog check-updates --json`.
2. For each entry with `status: "update"`, review by `risk`:
   - `low` (skills): read the `compareUrl` diff for the `affectedItems` paths
     and summarize what changed in a few lines.
   - `medium` (plugins): read the `changelog` / release notes. Flag new hooks,
     MCP servers, commands or permissions the plugin adds.
   - `high` (CLI tools, local MCP servers): read the actual code diff between
     the versions. Flag new shell commands, network calls, file writes outside
     the project, install scripts and permission changes.

   `status: "unaffected"` means upstream moved but none of the used paths
   changed: mention it, recommend skipping. `unknown` / `unreachable`: report.
3. Present a table (source, current → latest, risk, verdict) with the findings
   and ask which to accept.
4. For the accepted ones: create a branch, run `catalog bump <source>` for each,
   run `catalog readme`, commit, and open a PR whose body is the review.
5. Remind the user that `plugin` sources only record what was reviewed:
   after merging, they update the plugin itself with `claude plugin update <plugin>@<marketplace>`,
   and projects pick up new pins with `catalog update`.
