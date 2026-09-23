#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "exi2s" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "exi2s" (case-insensitive, whole word), injects context
# telling Claude to treat it as "explain in two sentences". Emits nothing otherwise, so it is a
# no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'exi2s'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"exi2s\" in this message is the user'"'"'s abbreviation for: \"explain in two sentences\". Treat each occurrence of exi2s in the message as that instruction: answer with exactly two sentences, no lists, headings or follow-up."
    }
  }'
fi
