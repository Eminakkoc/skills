# skills

An index of the Claude Code skills, rules, hooks, MCP servers, plugins and CLI tools I
use. Any machine or project pulls only what it needs from here, without cloning
this repo or installing it as a plugin. Third-party items are referenced at a
pinned version, not copied, and checked for upstream updates on demand.

Design: [`docs/catalog-design.md`](docs/catalog-design.md), with sequence
diagrams in [`docs/diagrams/`](docs/diagrams/).

## New machine

```bash
curl -fsSL https://raw.githubusercontent.com/Eminakkoc/skills/main/catalog.sh | bash -s -- setup
```

This installs the `catalog` command to `~/.local/bin` and every user-scope item
(my prompt-expansion hooks, personal plugins, the `catalog` skill). Needs `jq`,
`curl`, `git` and the `claude` CLI; `gh` for maintenance commands. Restart
Claude Code afterwards.

## In a project

```bash
catalog list                      # what the catalog offers
catalog add bundle:web            # or individual items: catalog add composition-patterns
catalog list --installed          # what this project and ~/.claude have
catalog doctor                    # after cloning: check files and required CLI tools
catalog update --dry-run          # see newer pinned versions, then: catalog update
catalog self-update               # refresh the catalog command itself (update does this too)
catalog remove agent-browser
```

Or ask Claude in plain words ("add the web bundle to this project"); the
`catalog` skill runs these commands. Commit the project's `.claude/` and
`.mcp.json` so the project carries its items; `.claude/catalog.lock.json`
records what was installed at which version.

Every item has a scope: `user` items go to `~/.claude` (`--user`), `project`
items into the current project. `user` items are skipped in a project unless
you pass `--force`.

## Catalog

<!-- catalog:start -->
| Item | Kind | Scope | Source | What it does |
|---|---|---|---|---|
| `expand-ebse` | hook | user | this repo | `ebse` → explain briefly in simple language and with examples |
| `expand-exi2s` | hook | user | this repo | `exi2s` → explain in two sentences |
| `expand-exios` | hook | user | this repo | `exios` → explain in one sentence |
| `expand-ruview` | hook | user | this repo | `ruview` → file-review request |
| `expand-wtru` | hook | user | this repo | `wtru` → walk through items one at a time |
| `context7` | plugin | user | anthropics/claude-plugins-official | Current library and framework docs (MCP) |
| `figma` | plugin | project | anthropics/claude-plugins-official | Figma MCP server and design-to-code skills |
| `millwright-inspector-development-machine` | plugin | user | Eminakkoc/Millwright-Inspector-Development-Machine | Millwright/inspector development workflow |
| `superpowers` | plugin | user | anthropics/claude-plugins-official | Process skills: brainstorming, TDD, planning, debugging |
| `vercel` | plugin | project | anthropics/claude-plugins-official | Vercel platform skills, agents and commands |
| `context7-docs` | rule | user | this repo | Rule: fetch library/framework docs through Context7 instead of relying on memory |
| `agent-browser` | skill | project | vercel-labs/agent-browser | Vercel: browser automation through the agent-browser CLI |
| `catalog` | skill | user | this repo | Drives catalog.sh: add, remove, update and check items from this index |
| `chrome-extensions` | skill | project | GoogleChrome/modern-web-guidance | Google Chrome: building and publishing Chrome extensions |
| `composition-patterns` | skill | project | vercel-labs/agent-skills | Vercel: React composition patterns |
| `modern-web-guidance` | skill | project | GoogleChrome/modern-web-guidance | Google Chrome: modern web platform best practices |
| `react-view-transitions` | skill | project | vercel-labs/agent-skills | Vercel: React view transitions |
| `web-design-guidelines` | skill | project | vercel-labs/agent-skills | Vercel: review UI code against web design guidelines |
| `web-images` | skill | project | this repo | Image performance: sizing, srcset, formats, LCP, layout shift |
| `agent-browser-cli` | tool | user | agent-browser | CLI behind the agent-browser skill |
| `plantuml-mcp-server` | tool | user | plantuml-mcp-server | CLI behind millwright-inspector's plantuml MCP |

| Bundle | What it is for | Items |
|---|---|---|
| `bundle:personal` | Everything I want on every machine: prompt shortcuts, the catalog skill, personal plugins and rules | catalog, expand-ebse, expand-wtru, expand-exios, expand-exi2s, expand-ruview, superpowers, context7, millwright-inspector-development-machine, context7-docs |
| `bundle:react` | React-only skills: composition patterns and view transitions | composition-patterns, react-view-transitions |
| `bundle:vercel` | Projects deployed on Vercel: the Vercel plugin plus design guidelines | vercel, web-design-guidelines |
| `bundle:web-frontend` | Frontend projects: the web bundle plus the Vercel and Figma plugins | web-images, web-design-guidelines, composition-patterns, react-view-transitions, modern-web-guidance, agent-browser, vercel, figma |
| `bundle:web` | Web skills for any web project: images, design guidelines, React patterns, modern web guidance, browser automation | web-images, web-design-guidelines, composition-patterns, react-view-transitions, modern-web-guidance, agent-browser |
<!-- catalog:end -->

Vercel skills already shipped by the `vercel` plugin (react-best-practices,
next-*, ai-sdk, workflow, vercel-cli, shadcn) are left out to avoid duplicates.

## Layout

```
catalog/              one small JSON file per item, in a folder per type:
  skills/ rules/ hooks/ plugins/ mcp/ tools/   <name>.json: scope, source, path, description
  bundles/                                     <name>.json: description + list of items
sources.json          third-party upstreams: location, pinned/reviewed version, risk
catalog.sh            the catalog command (install, update, doctor, maintenance)
skills/<name>/        my own skills, one folder each
hooks/<name>/         my own hooks: script + README
rules/<name>.md       my own rules (instructions loaded into every session)
docs/                 design and sequence diagrams
```

## Adding things

Every item is one file, `catalog/<type>/<name>.json`. The folder is its type
and the file name is its name (unique across all types). Copy a neighbour
and edit it.

- **My own skill:** create `skills/<name>/SKILL.md`, then
  `catalog/skills/<name>.json` with `"source": "self"` and `"path": "skills/<name>"`.
- **My own rule:** create `rules/<name>.md`, then `catalog/rules/<name>.json`
  with `"path": "rules/<name>.md"`. It installs as `.claude/rules/<name>.md`
  (user scope: `~/.claude/rules/`).
- **My own hook:** add `hooks/<name>/<name>.sh` (executable) and a README, then
  `catalog/hooks/<name>.json` with `"hook": {"event": ..., "script": ...}`.
- **A third-party skill:** add (or reuse) a `github` source in `sources.json`
  pinned to a commit SHA, then `catalog/skills/<name>.json` pointing at its
  `path` in that repo.
- **A third-party plugin:** add a `plugin` source (marketplace, its repo, plugin
  name, `reviewed` version), then `catalog/plugins/<name>.json`.
- **A CLI tool something needs:** add an `npm`/`pypi` source and
  `catalog/tools/<name>.json` with `bin` and `install` (`{version}` is replaced
  with the pin); list it in the dependent item's `requires`.
- **A bundle:** `catalog/bundles/<name>.json` with a `description` and the
  `items` it installs.
- **A third-party skill I want to modify:** copy it into `skills/<name>/` with a
  `SOURCE.md` noting the upstream URL and commit, and make it a `self` item.

Then run `./catalog.sh readme` to regenerate the table above.

## Keeping third-party items current

Inside this repo, ask Claude to "check catalog updates", or run:

```bash
./catalog.sh check-updates          # compare every source with upstream (read-only)
./catalog.sh bump <source>          # move a pin to the latest (or a given) version
```

The `catalog` skill reviews each update by risk (skills: summary; plugins:
changelog; CLI tools and MCP servers: full diff) and opens a PR with the bumps.
Projects pick up merged pins with `catalog update`.
