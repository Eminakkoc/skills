#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "atamo" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "atamo" (case-insensitive, whole word), injects context
# telling Claude to treat it as "apply this and move on to the next item".
# Emits nothing otherwise, so it is a no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'atamo'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"atamo\" in this message is the user'"'"'s abbreviation for: \"apply this and move on to the next item\". Treat each occurrence of atamo in the message as that instruction: apply the current item (the suggested fix or change under discussion), then present the next item."
    }
  }'
fi
