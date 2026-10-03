# skills

My Claude Code skills and hooks, packaged as a plugin marketplace so any
machine can pick them up with two commands.

## Install

Inside Claude Code:

```
/plugin marketplace add Eminakkoc/skills
/plugin install toolkit@eminakkoc
/plugin install modern-web-guidance@eminakkoc
/plugin install vercel-agent-skills@eminakkoc
/plugin install agent-browser@eminakkoc
```

Or from a shell: `./install.sh` (add `--local` to register this checkout
instead of GitHub, so edits take effect without pushing).

Pull updates later with `/plugin marketplace update eminakkoc`.

Hooks need `jq` (`brew install jq`).

## Layout

```
.claude-plugin/
  marketplace.json   the catalog: my toolkit plus referenced external plugins
  plugin.json        manifest for the "toolkit" plugin (this repo)
skills/<name>/SKILL.md   my own skills, one folder each, folder = skill name
hooks/hooks.json         wires the hook scripts into the plugin
hooks/<name>/            one hook per folder: script + README
install.sh               shell bootstrap for a new machine
```

## What's in it

**toolkit** (this repo)

| Kind | Name | What it does |
|---|---|---|
| Skill | `toolkit:web-images` | Image performance: sizing, srcset, formats, LCP, layout shift |
| Hook | `ebse`, `wtru`, `exios`, `exi2s`, `ruview` | Expand inline abbreviations in prompts; see each `hooks/<name>/README.md` |

**External, referenced and not copied**

| Plugin | Source |
|---|---|
| `modern-web-guidance` | [GoogleChrome/modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance) |
| `vercel-agent-skills` | [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills): `web-design-guidelines`, `composition-patterns`, `react-view-transitions` only |
| `agent-browser` | [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser); needs `npm i -g agent-browser && agent-browser install` |

Vercel skills already shipped by the `vercel@claude-plugins-official` plugin
(react-best-practices, next-*, ai-sdk, workflow, vercel-cli, shadcn) are left
out to avoid duplicates.

## Adding things

- **My own skill:** create `skills/<name>/SKILL.md` with `name: <name>` in the
  frontmatter. It shows up as `toolkit:<name>`.
- **My own hook:** add `hooks/<name>/<name>.sh` (executable) and an entry in
  `hooks/hooks.json` using `${CLAUDE_PLUGIN_ROOT}/hooks/<name>/<name>.sh`.
- **Someone else's plugin:** add an entry to `.claude-plugin/marketplace.json`
  with a `github` source. To take only some skills from a repo of plain
  `SKILL.md` folders (no plugin manifest), use a `git-subdir` source pointing
  at the folder that holds them, set `"strict": false`, and list the ones you
  want in `"skills"` (see `vercel-agent-skills`). Pointing at the repo root
  instead loads every skill in its `skills/` folder regardless of the list. Leaving it unpinned follows upstream; add `"ref"` or
  `"sha"` to freeze a version.
- **Someone else's skill I want to modify:** copy it into `skills/<name>/` and
  add a `SOURCE.md` noting the upstream URL, commit, and date copied.

Bump `version` in `.claude-plugin/plugin.json` when you change the toolkit, so
installed copies update.

Run `claude plugin validate .` before pushing.
