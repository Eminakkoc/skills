#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "detamo" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "detamo" (case-insensitive, whole word), injects context
# telling Claude to treat it as "decline this and move on to the next item".
# Emits nothing otherwise, so it is a no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'detamo'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"detamo\" in this message is the user'"'"'s abbreviation for: \"decline this and move on to the next item\". Treat each occurrence of detamo in the message as that instruction: decline the current item (do not apply the suggested fix or change under discussion), then present the next item."
    }
  }'
fi
