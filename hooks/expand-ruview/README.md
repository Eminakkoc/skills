# expand-ruview

Expands the abbreviation `ruview` into a file-review request whenever it
appears in a prompt:

> Run a review on this file. Check if there are any potential errors,
> conflicts, inconsistencies, missing or open points which need decisions etc.
> and list your findings by adding severity tags to each one (ignore low
> severity ones). Add a brief explanation, add a one sentence summary and also
> your fix suggestion for each of your findings.

For example, `ruview docs/plan.md` reviews that file. With no file named, it
reviews the file most recently under discussion.

This is a **hook**, not a skill or a slash command. The distinction matters:

| | Who triggers it |
|---|---|
| Skill | The model, when the task matches |
| Slash command | You, by typing `/name` |
| Hook | The harness, at a lifecycle event |

`ruview` is a hook so it can be dropped inline anywhere in a prompt, with
nothing invoked separately.

## How it works

Claude Code runs the script on every prompt submission and pipes it the hook
payload as JSON on stdin. The script pulls out `.prompt`, greps it for the
standalone word `ruview`, and if it finds one, prints a JSON object whose
`additionalContext` tells the model what the abbreviation means.

The prompt itself is never rewritten. The model receives your original text
plus a note explaining the token. On prompts without `ruview` the script prints
nothing, so it is a no-op.

## Install

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   cp expand-ruview.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/expand-ruview.sh
   ```

2. Wire it up in `~/.claude/settings.json`. The script does nothing on its own;
   this entry is what makes it run.

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "~/.claude/hooks/expand-ruview.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. Restart Claude Code, then send `ruview <some file>` and check that the
   answer lists severity-tagged findings, each with a summary, explanation and
   fix.

Use `~/.claude/settings.json` for every project, or a project's
`.claude/settings.json` to scope it to one repo.

## Requirements

`jq`, for both reading the payload and emitting the response. The script runs
under `set -euo pipefail`, so on a machine without `jq` it fails rather than
degrading quietly. `brew install jq` on macOS.

## Adapting it

To change the review instructions, edit the `additionalContext` string. To use
a different abbreviation, change both the `grep -qiw` pattern and the text.

The match is case-insensitive and whole-word (`grep -qiw`), so `RUVIEW` and
`ruview,` match while `ruviews` does not.

## Known limitation

It fires on *mentions*, not just uses. Asking "what does ruview do?" expands it
too. Harmless in practice, since the model can tell from context that you are
asking about the token rather than using it.
