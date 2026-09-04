#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "wtru" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "wtru" (case-insensitive, whole word), injects context
# putting Claude into walkthrough mode: one item per reply, each with a
# title, a very brief plain-language explanation, a one-sentence summary,
# an example, a non-technical statement of impact and, for findings and
# bugs only, a suggested fix plus a concrete example of that fix. Pauses for
# the user's response between items. Emits nothing otherwise, so it is a
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

2. Present exactly ONE item per reply. Never batch two items into one message, and do not preview or summarize the remaining items.

3. Give each item these seven parts, in this order:
   - Title: a short name for the item.
   - Explanation: very simple and very brief. Two or three sentences of plain language, no jargon. Whenever it refers to another item, file, component or term the user may not already have in mind, add a few-word gloss in parentheses immediately after the reference, for example "reads from the manifest (the generated file holding the image sizes)".
   - Summary: one sentence capturing the item.
   - Example: one concrete example, drawn either from the item's own context or from ordinary real-world usage.
   - Impact: which modules or features this affects, in one or two lines, in NON-TECHNICAL language. Name the part of the product a person would recognise and what changes for them, not the files, components or symbols involved. Prefer "the photo at the top of the home page and the About page" over "ResponsiveImage and the generated manifest". If nothing user-facing changes, say so plainly.
   - Suggested fix: at most two sentences saying what to do about it. Include this part ONLY when the item is a finding, a bug, or something else that needs fixing. For an item that is simply being explained, omit the part entirely rather than writing "not applicable" or "none needed".
   - Suggested fix example: a concrete illustration of that fix, such as a short before and after, a snippet, or the exact change to make, small enough to take in at a glance. Include this part ONLY when a Suggested fix is present, and never on its own without one.

4. Stop after each item and wait for the user to respond before moving to the next. Do not continue on your own initiative. Proceed only when the user replies.

Keep track of position so that a reply of "yes", "next" or "continue" resumes at the correct item.
TEXT

jq -n --arg ctx "$context" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
