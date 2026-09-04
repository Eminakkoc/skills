# expand-wtru

Turns `wtru` in a prompt into walkthrough mode: Claude splits the subject into
items and presents them one at a time, pausing for your response between each.
Every item comes with a plain-language explanation, an example, and a
non-technical statement of what it affects. Findings and bugs also get a short
suggested fix and a concrete example of that fix.

Useful when a reply would otherwise be a wall of text you have to read in one
go, such as reviewing a diff, understanding an unfamiliar module, or working
through a list of findings.

Like [`expand-ebse`](../expand-ebse), this is a **hook**, not a skill or a
slash command. It fires automatically on every prompt containing the token,
with nothing invoked.

## What it asks for

One item per reply, each in up to seven parts:

| Part | Rule |
|---|---|
| **Title** | A short name for the item. |
| **Explanation** | Very simple and very brief. Two or three sentences of plain language, no jargon. Any reference to another item, file, component or term gets a few-word gloss in parentheses right after it. |
| **Summary** | One sentence. |
| **Example** | Concrete, from the item's own context or from real-world usage. |
| **Impact** | Which modules or features this affects, in one or two lines of non-technical language. |
| **Suggested fix** | At most two sentences. Only for findings and bugs; omitted entirely otherwise. |
| **Suggested fix example** | A short before/after, snippet, or exact change. Only when there is a Suggested fix. |

Then it stops and waits. It does not continue on its own, and it does not
preview the remaining items.

If the subject is not already a list, Claude divides it into items itself and
says how many there are up front, so you know the length before you start.

The last two parts are conditional and come as a pair. They appear when the
item is a finding, a bug, or something else that needs fixing, and are left out
completely for items that are simply being explained, rather than padding every
one with "not applicable". So the same walkthrough works for both a code review
and a tour of an unfamiliar module.

The example is tied to the fix, not to the item: a fix stated in prose is easy
to nod along to and hard to act on, so the pair gives you the intent and the
concrete shape of the change together. It never appears without a fix above
it.

Two parts do most of the work.

**The parenthetical glosses** stop a walkthrough from assuming you remember
every name it mentions, which is the usual reason this kind of explanation
stops landing partway through.

**Impact** is deliberately non-technical: it names the part of the product a
person would recognise and what changes for them, not the files or symbols
involved. So "the photo at the top of the home page and the About page"
rather than "ResponsiveImage and the generated manifest". When nothing
user-facing changes, it says so plainly instead of inventing a consequence.

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

The two are designed to stack, and they overlap on purpose. `wtru` controls
the *shape* of the answer (one item at a time, up to seven parts, pause
between) and
already asks for plain language and examples within each item. `ebse` controls
the *register* of a reply generally. Using both is harmless and reinforces the
same thing; using `ebse` alone is the right call when you want brevity without
the item-by-item pacing.

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
