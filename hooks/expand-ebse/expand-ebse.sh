#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "ebse" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "ebse" (case-insensitive, whole word), injects context
# telling Claude to treat it as "explain briefly in simple language and with
# examples". Emits nothing otherwise, so it is a no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'ebse'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"ebse\" in this message is the user'"'"'s abbreviation for: \"explain briefly in simple language and with examples\". Treat each occurrence of ebse in the message as that instruction."
    }
  }'
fi
