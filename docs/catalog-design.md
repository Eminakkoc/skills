# Catalog design

Status: implemented 2026-10-03 (`catalog.sh`, `catalog/`, `sources.json`, `skills/catalog`).

## Goal

Turn this repo from a plugin marketplace into an **index**: a catalog of the
skills, rules, hooks, MCP servers, plugins and CLI tools I use, which any machine or
project can pull from selectively, without cloning the repo or installing a
plugin. Third-party items are **referenced, not copied**, pinned to a version,
and checked for upstream updates on demand.

## Decisions

| # | Decision |
|---|---|
| 1 | Every item has a `scope`: `user` (goes into `~/.claude`) or `project` (goes into a project's `.claude/`). The fetcher refuses to put a `user` item into a project unless forced (`--force`). |
| 2 | The marketplace is retired. `.claude-plugin/` and `hooks/hooks.json` are deleted. Wrapped third-party skills become plain references; real third-party plugins stay plugins, the index only records where they come from. |
| 3 | `sources.json` has one entry per upstream repo/package with a single version. `catalog/` has one file per item, naming its source and path. Update checks report only the item paths that actually changed. |
| 4 | A source is either `pinned` (the fetcher enforces the version) or `reviewed` (records the last version I checked; the index cannot enforce it). Sources with no version (remote MCPs) have neither. A `github`, `npm` or `pypi` source may be pinned to `"latest"`: it then follows upstream, resolved to a concrete version once per run and recorded in the lock file, and skips the review in decision 6. |
| 5 | A `catalog.sh` script does all file work; a thin user-scope `catalog` skill teaches Claude when and how to run it. Claude never edits settings or lock files by hand. |
| 6 | Updates flow in two steps: (a) index pins move only through a PR I approve, after a risk-scaled review; (b) projects pick up new pins only when I run `catalog update` in them and confirm. |
| — | Third-party items are referenced, never vendored. An item I modify becomes my own item in this repo. |

## Repo layout (after)

```
catalog/              the catalog: one small JSON file per item and per bundle
  skills/<name>.json    the folder sets the kind, the file name sets the name
  rules/<name>.json
  hooks/<name>.json
  plugins/<name>.json
  mcp/<name>.json
  tools/<name>.json
  bundles/<name>.json   {description, items}
sources.json          third-party upstreams: location, version, risk
catalog.sh            the fetcher / updater (replaces install.sh)
skills/<name>/        my own skills' content
  catalog/SKILL.md    the bootstrap skill that drives catalog.sh
hooks/<name>/         my own hooks: script + README
rules/<name>.md       my own rules
docs/                 this design
README.md             catalog table generated from catalog/
```

Removed: `.claude-plugin/`, `hooks/hooks.json`, `plugins.json`, `install.sh`,
and (2026-10-04) the single `catalog.json`, split into `catalog/`.

## `catalog/`

Each item is a file `catalog/<type folder>/<name>.json`. The folder gives the
item's kind (`skills` → `skill`, `rules` → `rule`, `hooks` → `hook`, `plugins`
→ `plugin`, `mcp` → `mcp`, `tools` → `tool`) and the file name gives its name,
so neither is written inside the file. Names must be unique across all types,
because commands take bare names (`catalog add context7`).

```
catalog/hooks/expand-ebse.json
```
```json
{
  "scope": "user",
  "source": "self",
  "path": "hooks/expand-ebse",
  "hook": { "event": "UserPromptSubmit", "script": "expand-ebse.sh" },
  "requires": ["jq"],
  "description": "`ebse` → explain briefly in simple language and with examples"
}
```
```
catalog/skills/agent-browser.json
```
```json
{
  "scope": "project",
  "source": "agent-browser",
  "path": "skills/agent-browser",
  "requires": ["agent-browser-cli"],
  "description": "Vercel: browser automation through the agent-browser CLI"
}
```
```
catalog/bundles/web-frontend.json
```
```json
{
  "description": "Frontend projects: the web bundle plus the Vercel and Figma plugins",
  "items": ["web-images", "web-design-guidelines", "composition-patterns", "react-view-transitions",
            "modern-web-guidance", "agent-browser", "vercel", "figma"]
}
```

`catalog.sh` reads every file and assembles one in-memory document
(`{items: {<name>: {kind, ...}}, bundles: {<name>: {description, items}}}`),
which every command works from; `catalog list --json` prints its items. It
stops with an error naming the file if a folder is unknown, a name is used
twice, or a bundle lists an item that doesn't exist.

An `mcp` item would look like
`{"scope": "user", "source": "context7", "mcp": {"type": "http", "url": "https://mcp.context7.com/mcp"}, ...}`;
none exist yet (`context7` is installed as a plugin).

### Item fields

| Field | Required | Meaning |
|---|---|---|
| kind | — | Not a field: set by the folder (`skill`, `rule`, `hook`, `mcp`, `plugin`, `tool`) |
| `scope` | yes | `user` or `project` |
| `source` | yes | `self` (this repo) or a key in `sources.json` |
| `path` | skill, rule, hook | Directory (file, for a rule) inside the source repo |
| `hook` | hook | `event`, optional `matcher`, `script` filename |
| `mcp` | mcp | The server config as it goes into `.mcp.json`; `{version}` is substituted from the source pin |
| `install`, `bin` | tool | Install command (with `{version}`) and the binary to detect |
| `requires` | no | Other item names (usually `tool`s) or plain binaries that must be present |
| `include` | no | Skill or hook directories: only these files/folders (relative to `path`) are copied, for upstream skills that ship content they never read |
| `allow` | no | Permission rules merged into `permissions.allow` of the scope's `settings.json`; recorded in the lock entry and removed (or swapped) by `remove`/`update` |
| `description` | yes | One line, used for the README table and `catalog list` |

`kind: plugin` items take their marketplace and plugin name from the source.

## `sources.json`

Illustrative excerpt; the real pins live in `sources.json`.

```json
{
  "version": 1,
  "sources": {
    "vercel-agent-skills": {
      "type": "github",
      "repo": "vercel-labs/agent-skills",
      "pinned": "<sha>",
      "pinnedAt": "2026-10-03",
      "risk": "low",
      "changelog": "https://github.com/vercel-labs/agent-skills/commits/main"
    },
    "agent-browser": {
      "type": "github",
      "repo": "vercel-labs/agent-browser",
      "pinned": "<sha>",
      "pinnedAt": "2026-10-03",
      "risk": "low"
    },
    "modern-web-guidance": {
      "type": "github",
      "repo": "GoogleChrome/modern-web-guidance",
      "pinned": "<sha>",
      "pinnedAt": "2026-10-03",
      "risk": "low"
    },
    "plantuml-mcp-server": {
      "type": "npm",
      "package": "plantuml-mcp-server",
      "pinned": "<x.y.z>",
      "pinnedAt": "2026-10-03",
      "risk": "high"
    },
    "superpowers": {
      "type": "plugin",
      "marketplace": "claude-plugins-official",
      "marketplaceRepo": "anthropics/claude-plugins-official",
      "plugin": "superpowers",
      "reviewed": "<version>",
      "reviewedAt": "2026-10-03",
      "risk": "medium"
    },
    "context7": {
      "type": "remote-mcp",
      "url": "https://mcp.context7.com/mcp",
      "risk": "medium"
    }
  }
}
```

### Source types and how each is checked

| `type` | Version field | Latest-version check | Fetch |
|---|---|---|---|
| `github` | `pinned` (commit SHA) | `gh api repos/{repo}/commits/{branch:-HEAD}` → SHA; then `gh api repos/{repo}/compare/{pinned}...{latest}` and keep only files under paths that catalog items use | `curl https://codeload.github.com/{repo}/tar.gz/{sha}`, extract the item's `path` |
| `npm` | `pinned` (exact version) | `npm view {package} version` | `npm install -g {package}@{pinned}` or `npx -y {package}@{pinned}` in `.mcp.json` |
| `pypi` | `pinned` | `https://pypi.org/pypi/{package}/json` → `.info.version` | `uvx {package}=={pinned}` |
| `plugin` | `reviewed` | Read the marketplace's `.claude-plugin/marketplace.json` from `marketplaceRepo`; use the plugin's `version` if set, otherwise the last commit touching its source dir | `claude plugin install` (user scope) or settings entries (project scope); the marketplace decides the version |
| `remote-mcp` | none | HTTP reachability only | Config written to `.mcp.json` / user config |

### `risk`

Sets how deep the update review goes (see [Updates](#updates)).

- `low`: skills (prompt text). A short summary of what changed is enough.
- `medium`: plugins and remote MCPs (bundles of skills, hooks and servers I don't control).
- `high`: anything that runs code locally: hooks, local MCP servers, CLI tools. The agent reads the full diff.

## Where items land

| Kind | `scope: user` | `scope: project` |
|---|---|---|
| skill | `~/.claude/skills/<name>/` | `<project>/.claude/skills/<name>/` |
| rule | `~/.claude/rules/<name>.md` | `<project>/.claude/rules/<name>.md` |
| hook | Script → `~/.claude/hooks/<name>/`; entry merged into `~/.claude/settings.json` with command `~/.claude/hooks/<name>/<script>` | Script → `.claude/hooks/<name>/`; entry merged into `.claude/settings.json` with command `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>/<script>` |
| mcp | `claude mcp add --scope user …` | Merged into `<project>/.mcp.json` |
| plugin | `claude plugin marketplace add` + `claude plugin install` | `extraKnownMarketplaces` + `enabledPlugins` in `.claude/settings.json`, so whoever opens the project is prompted to install it |
| tool | Installed globally via `install` if `bin` is missing | Not allowed; tools are always `user` |

Hook entries are identified by their command path, so `remove` and `update` can
find and replace exactly the entry they own without touching hand-written hooks.

## Lock files

Every install target gets a lock file recording what the catalog put there:
`~/.claude/catalog.lock.json` for user scope, `<project>/.claude/catalog.lock.json`
for project scope. The project one is committed.

```json
{
  "version": 1,
  "index": { "repo": "Eminakkoc/skills", "sha": "<sha of this repo used>" },
  "items": {
    "composition-patterns": { "kind": "skill", "source": "vercel-agent-skills", "version": "<pinned sha>", "hash": "<content hash>", "files": [".claude/skills/composition-patterns"] },
    "web-images":           { "kind": "skill", "source": "self", "version": "<content hash>", "hash": "<content hash>", "files": [".claude/skills/web-images"] }
  }
}
```

`files` lists exactly what the catalog wrote (relative to the project, or to
`$HOME` for user scope), so `remove` deletes only that. `hash` is a content hash
of the copied files, so `update` and `doctor` can tell if I've edited them. For
my own (`self`) items the version is that same content hash, so a commit to this
repo only counts as an update for the items it actually changed. Hook entries
also record their `event` and `command`, plugins their id, for clean removal.

## `catalog.sh`

Requires `jq`, `curl`, `git` (and `gh` for `check-updates`). Runs on macOS's bash 3.2. By default it reads the index from GitHub
(`Eminakkoc/skills@main`, resolved to a SHA at run time). `--local <path>` reads
it from a checkout instead.

| Command | What it does |
|---|---|
| `setup [item\|bundle:name…]` | New machine: installs `catalog.sh` to `~/.local/bin/catalog`, then every `user` item except tools (they come in through `requires`), or only the items given. Replaces `install.sh`. |
| `list [--installed]` | Lists catalog items, or what this project/user has installed, with versions. |
| `add <item\|bundle:name>… [--user] [--force]` | Installs items into the current project (or user scope with `--user`), resolving `requires`. |
| `remove <item>…` | Removes an item's files and settings entries, using the lock file. |
| `update [<item>…]` | Compares the lock file with the current index, shows each version change (flagging ones that would overwrite local edits), applies it after confirmation. Plugins are only reported, with the `claude plugin update` command to run. |
| `self-update` | Replaces `~/.local/bin/catalog` with the index's `catalog.sh` (moved into place, so a running copy isn't disturbed). `update` runs it first. |
| `doctor` | Checks both lock files: files present, local edits, plugins installed, tools and `requires` on PATH. Offers to install missing tools. Exit 1 on problems. |
| `check-updates [--json]` | Index maintenance: compares every source's `pinned`/`reviewed` with upstream and outputs a report (see below). Read-only. |
| `bump <source> [<version>]` | Index maintenance: moves a source's pin (or `reviewed`) to the given or latest version and updates the date. A source pinned to `"latest"` needs an explicit version (which freezes it). |
| `readme` | Regenerates the README catalog and bundle tables from `catalog/`. |

Options: `--user` (target `~/.claude`), `--force` (put a `user` item in a
project, replace files the catalog didn't install, skip the local-edit prompt),
`--yes` (accept confirmations; needed when there's no terminal, e.g. when
Claude runs it), `--dry-run` (`update`/`doctor` report only), `--json`
(`list`, `check-updates`), `--local PATH` (read the index from a checkout).

Tools found on PATH that the catalog didn't install are recorded as
`"version": "external"` and left alone by `add` and `update`.

New-machine bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/Eminakkoc/skills/main/catalog.sh | bash -s -- setup
```

### `check-updates` report

```json
[
  {
    "source": "vercel-agent-skills",
    "type": "github",
    "risk": "low",
    "current": "<sha>",
    "latest": "<sha>",
    "commitsAhead": 40,
    "affectedItems": ["composition-patterns"],
    "compareUrl": "https://github.com/vercel-labs/agent-skills/compare/<sha>...<sha>"
  },
  {
    "source": "plantuml-mcp-server",
    "type": "npm",
    "risk": "high",
    "current": "1.4.2",
    "latest": "1.5.0",
    "affectedItems": ["plantuml-mcp-server"]
  }
]
```

`status` is one of `current`, `update`, `unaffected` (a `github` source moved
upstream but none of the used paths changed), `tracking` (pinned to `"latest"`;
`latest` shows what an install would get now; nothing to review), `unknown` (latest version
couldn't be determined), `reachable` / `unreachable` (remote MCPs). A `github`
source can set `branch` to track something other than the default branch.

## The `catalog` skill

User scope, installed by `setup`. It tells Claude:

- For "add / remove / list / update X in this project": run the matching
  `catalog` command, show the output, and never edit settings, `.mcp.json` or
  lock files directly.
- For "check catalog updates" (run in this repo):
  1. Run `catalog check-updates --json`.
  2. Review each entry according to its `risk`: `low` → summarize the changed
     files; `medium` → read the changelog or release notes and flag new
     skills, hooks or MCPs; `high` → read the full diff and flag new commands,
     network calls, file writes and permission changes.
  3. Present the findings, then on approval run `catalog bump` for the
     accepted sources on a branch, regenerate the README, and open a PR whose
     body is the review.
  4. For `reviewed` (plugin) sources, remind me to run `/plugin update` after
     merging.

## Updates

1. **Index**: triggered manually ("check catalog updates") or by an optional
   weekly scheduled routine running the same steps. Result: a PR with bumps and
   the review. Nothing merges without my approval.
2. **Projects**: `catalog update` in the project reads the lock file, compares
   it with the index at `main`, lists each change (`composition-patterns
   a1b2c3d → f9e8d7c`), and applies it on confirmation. My own (`source: self`)
   items update the same way, keyed on this repo's SHA.

## Migration from the current plugin setup

1. Write the catalog and `sources.json` from `.claude-plugin/marketplace.json`,
   `plugins.json` and `hooks/hooks.json`, pinning every third-party source at
   its current upstream version. Resolve `modern-web-guidance`'s skill paths
   (currently installed as a whole plugin) into individual items.
2. Write `catalog.sh` and the `catalog` skill.
3. On this machine: uninstall `toolkit`, `modern-web-guidance`,
   `vercel-agent-skills` and `agent-browser` plugins, remove the `eminakkoc`
   marketplace, then run `catalog setup`. Verify each hook fires and each skill
   is listed.
4. Delete `.claude-plugin/`, `hooks/hooks.json`, `plugins.json`, `install.sh`.
   Update each hook README's install section to point at `catalog add`.
5. Regenerate the README.

### Initial scopes

| Item | Kind | Scope |
|---|---|---|
| expand-ebse, expand-wtru, expand-exios, expand-exi2s, expand-ruview | hook | user |
| web-images | skill | project |
| web-design-guidelines, composition-patterns, react-view-transitions | skill (vercel-agent-skills) | project |
| agent-browser | skill | project |
| modern-web-guidance, chrome-extensions | skill (modern-web-guidance) | project |
| superpowers, context7 | plugin | user |
| vercel, figma | plugin | project |
| millwright-inspector-development-machine | plugin | user |
| plantuml-mcp-server, agent-browser CLI | tool | user |
| catalog | skill | user |
| context7-docs | rule | user |

## Scenario diagrams

PlantUML sequence diagrams for first use on a new machine, in
[`diagrams/`](diagrams/):

1. [`01-new-machine-setup.puml`](diagrams/01-new-machine-setup.puml): `catalog setup` installs the script and every `user` item.
2. [`02-add-items-to-project.puml`](diagrams/02-add-items-to-project.puml): asking Claude to add a bundle to a project.
3. [`03-clone-existing-project.puml`](diagrams/03-clone-existing-project.puml): opening a project that already uses the catalog, then `catalog doctor` and `catalog update`.

## Settled while building

- `catalog doctor` exists (scenario 3).
- `context7` stays a plugin, as installed before; the `mcp` kind and
  `remote-mcp` source type are supported for future direct MCP servers.
- `github` sources take an optional `branch`.
- No weekly routine yet; "check catalog updates" is run by hand. One can be
  added later with `/schedule` running the same skill steps.
- Plugin `reviewed` versions follow what Claude Code reports: the plugin's own
  `plugin.json` version, else the marketplace entry's `version`, else its pinned
  `sha`, else the last commit touching the plugin's directory.
