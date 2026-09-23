#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "exios" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "exios" (case-insensitive, whole word), injects context
# telling Claude to treat it as "explain in one sentence". Emits nothing otherwise, so it is a
# no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'exios'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"exios\" in this message is the user'"'"'s abbreviation for: \"explain in one sentence\". Treat each occurrence of exios in the message as that instruction: answer with exactly one sentence, no lists, headings or follow-up."
    }
  }'
fi
