# expand-exios

Expands the abbreviation `exios` into "explain in one sentence" whenever
it appears in a prompt, and asks for exactly one sentence, with no lists,
headings or follow-up.

This is a **hook**, not a skill or a slash command. The distinction matters:

| | Who triggers it |
|---|---|
| Skill | The model, when the task matches |
| Slash command | You, by typing `/name` |
| Hook | The harness, at a lifecycle event |

`exios` has to be a hook because it fires automatically, mid-sentence, with
nothing invoked. A skill cannot intercept a prompt at all, and a command would
mean typing `/exios` as a separate step instead of dropping the word inline.

## How it works

Claude Code runs the script on every prompt submission and pipes it the hook
payload as JSON on stdin. The script pulls out `.prompt`, greps it for the
standalone word `exios`, and if it finds one, prints a JSON object whose
`additionalContext` tells the model what the abbreviation means.

The prompt itself is never rewritten. The model receives your original text
plus a note explaining the token. On prompts without `exios` the script prints
nothing, so it is a no-op.

## Install

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   cp expand-exios.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/expand-exios.sh
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
               "command": "~/.claude/hooks/expand-exios.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. Restart Claude Code, then send a prompt containing `exios` and check that the
   answer comes back as exactly one sentence.

Use `~/.claude/settings.json` for every project, or a project's
`.claude/settings.json` to scope it to one repo.

## Requirements

`jq`, for both reading the payload and emitting the response. The script runs
under `set -euo pipefail`, so on a machine without `jq` it fails rather than
degrading quietly. `brew install jq` on macOS.

## Adapting it

To change the phrase, edit the `additionalContext` string. To use a different
abbreviation, change both the `grep -qiw` pattern and the text.

The match is case-insensitive and whole-word (`grep -qiw`), so `EXIOS` and
`exios,` match while `exiosx` does not.

## Known limitation

It fires on *mentions*, not just uses. Asking "what does exios do?" expands it
too. Harmless in practice, since the model can tell from context that you are
asking about the token rather than using it. If it ever gets in the way, match
something less likely to appear in ordinary prose.
