# expand-wtru

Turns `wtru` in a prompt into walkthrough mode: Claude splits the subject into
items and presents them one at a time, pausing for your confirmation between
each.

Useful when a reply would otherwise be a wall of text you have to read in one
go, such as reviewing a diff, understanding an unfamiliar module, or working
through a list of findings.

Like [`expand-ebse`](../expand-ebse), this is a **hook**, not a skill or a
slash command. It fires automatically on every prompt containing the token,
with nothing invoked.

## What it asks for

One item per reply, each in four parts:

| Part | Rule |
|---|---|
| **Title** | A short name for the item. |
| **Explanation** | At most one paragraph. Any reference to another item, file, component or term gets a few-word gloss in parentheses right after it. |
| **Summary** | One sentence. |
| **Example** | Concrete, from the item's own context or from real-world usage. |

Then it stops and waits. It does not continue on its own, and it does not
preview the remaining items.

If the subject is not already a list, Claude divides it into items itself and
says how many there are up front, so you know the length before you start.

The parenthetical glosses are the part that does the most work. They stop a
walkthrough from assuming you remember every name it mentions, which is the
usual reason this kind of explanation stops landing partway through.

## How it works

Claude Code runs the script on every prompt submission and pipes it the hook
payload as JSON on stdin. The script pulls out `.prompt`, greps it for the
standalone word `wtru`, and if it finds one, prints a JSON object whose
`additionalContext` carries the walkthrough instructions.

The prompt itself is never rewritten. On prompts without `wtru` the script
prints nothing, so it is a no-op.

## Install

1. Copy the script somewhere stable and make it executable:

   ```bash
   mkdir -p ~/.claude/hooks
   cp expand-wtru.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/expand-wtru.sh
   ```

2. Wire it up in `~/.claude/settings.json`. The script does nothing on its own;
   this entry is what makes it run.

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         {
           "hooks": [
             { "type": "command", "command": "~/.claude/hooks/expand-wtru.sh" }
           ]
         }
       ]
     }
   }
   ```

   Already running `expand-ebse`? Add this as a second object in the same
   `UserPromptSubmit` array. Both will run on every prompt, and each is a
   no-op unless its own token is present.

3. Restart Claude Code, then try `wtru the files in this directory`.

## Requirements

`jq`, for both reading the payload and emitting the response. The script runs
under `set -euo pipefail`, so on a machine without `jq` it fails rather than
degrading quietly. `brew install jq` on macOS.

## Composing with expand-ebse

The two are designed to stack. `wtru` controls the *shape* of the answer (one
item at a time, four parts, pause between). `ebse` controls the *register*
(brief, plain language, with examples). Using both in one prompt gives you a
walkthrough in plain language.

## Adapting it

The match is case-insensitive and whole-word (`grep -qiw`), so `WTRU` and
`wtru,` match while `wtruncated` does not.

To change what a walkthrough looks like, edit the heredoc between `<<'TEXT'`
and `TEXT`. It is passed to `jq` with `--arg`, so it can contain apostrophes
and quotes with no shell escaping.

## Known limitation

It fires on *mentions*, not just uses. Asking "what does wtru do?" triggers a
walkthrough of the answer. Harmless in practice, since Claude can tell from
context that you are asking about the token rather than using it.
