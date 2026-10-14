#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "junswer" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "junswer" (case-insensitive, whole word), injects context
# telling Claude to treat it as "Do not implement, just answer".
# Emits nothing otherwise, so it is a no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'junswer'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"junswer\" in this message is the user'"'"'s abbreviation for: \"Do not implement, just answer\". Treat each occurrence of junswer in the message as that instruction: answer the question in the message without editing files, running changes, or implementing anything."
    }
  }'
fi
