#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "wtru" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "wtru" (case-insensitive, whole word), injects context
# putting Claude into walkthrough mode: one item per reply, each with a
# title, explanation, one-sentence summary and example, pausing for the
# user's confirmation between items. Emits nothing otherwise, so it is a
# no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if ! printf '%s' "$prompt" | grep -qiw 'wtru'; then
  exit 0
fi

# Held in a quoted heredoc and passed to jq with --arg, so the text can
# contain apostrophes and quotes without any shell escaping.
read -r -d '' context <<'TEXT' || true
The token "wtru" in this message is the user's abbreviation for "walk through". It requests WALKTHROUGH MODE for whatever the message is about.

In walkthrough mode:

1. Work out what the items are. If the subject is already a list, those are the items. If it is not divided into items, divide it yourself into the natural units a reader would want to take one at a time, and say up front how many there are.

2. Present exactly ONE item per reply. Never batch two items into one message, and do not summarize the remaining items ahead of time.

3. Give each item these four parts, in this order:
   - Title: a short name for the item.
   - Explanation: at most one paragraph. Whenever it refers to another item, file, component, term or entity the user may not already have in mind, add a few-word gloss in parentheses immediately after the reference, for example "reads from the manifest (generated file holding the srcsets)".
   - Summary: one sentence capturing the item.
   - Example: one concrete example, drawn either from the item's own context or from ordinary real-world usage.

4. Stop after each item and wait for the user to confirm before moving to the next. Do not continue on your own initiative. Proceed only when the user replies.

Keep track of position so that a reply of "yes", "next" or "continue" resumes at the correct item.
TEXT

jq -n --arg ctx "$context" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
