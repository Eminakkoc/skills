# expand-detamo

Expands the abbreviation `detamo` into "decline this and move on to the next item"
whenever it appears in a prompt: Claude declines the current item (the suggested
fix or change under discussion), then presents the next one. Pairs naturally
with [`expand-wtru`](../expand-wtru) walkthroughs, and is the counterpart of
[`expand-atamo`](../expand-atamo).

This is a **hook**, not a skill or a slash command. The distinction matters:

| | Who triggers it |
|---|---|
| Skill | The model, when the task matches |
| Slash command | You, by typing `/name` |
| Hook | The harness, at a lifecycle event |

`detamo` has to be a hook because it fires automatically, mid-sentence, with
nothing invoked. A skill cannot intercept a prompt at all, and a command would
mean typing `/detamo` as a separate step instead of dropping the word inline.

## How it works

Claude Code runs the script on every prompt submission and pipes it the hook
payload as JSON on stdin. The script pulls out `.prompt`, greps it for the
standalone word `detamo`, and if it finds one, prints a JSON object whose
`additionalContext` tells the model what the abbreviation means.

The prompt itself is never rewritten. The model receives your original text
plus a note explaining the token. On prompts without `detamo` the script prints
nothing, so it is a no-op.

## Install

`catalog add --user expand-detamo` (see the repo README) installs and wires this hook up
automatically. The manual steps below are for using it without the catalog.

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   cp expand-detamo.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/expand-detamo.sh
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
               "command": "~/.claude/hooks/expand-detamo.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. Restart Claude Code, then send a prompt containing `detamo` and check that the
   current item is skipped without changes and the next one is presented.

Use `~/.claude/settings.json` for every project, or a project's
`.claude/settings.json` to scope it to one repo.

## Requirements

`jq`, for both reading the payload and emitting the response. The script runs
under `set -euo pipefail`, so on a machine without `jq` it fails rather than
degrading quietly. `brew install jq` on macOS.

## Adapting it

To change the phrase, edit the `additionalContext` string. To use a different
abbreviation, change both the `grep -qiw` pattern and the text.

The match is case-insensitive and whole-word (`grep -qiw`), so `DETAMO` and
`detamo,` match while `detamox` does not.

## Known limitation

It fires on *mentions*, not just uses. Asking "what does detamo do?" expands it
too. Harmless in practice, since the model can tell from context that you are
asking about the token rather than using it. If it ever gets in the way, match
something less likely to appear in ordinary prose.
