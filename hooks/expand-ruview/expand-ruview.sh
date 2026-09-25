#!/usr/bin/env bash
# UserPromptSubmit hook: expand the "ruview" abbreviation.
#
# Reads the hook payload on stdin. If the submitted prompt contains the
# standalone token "ruview" (case-insensitive, whole word), injects context
# telling Claude to treat it as a request for a severity-tagged file review.
# Emits nothing otherwise, so it is a no-op on normal prompts.
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')

if printf '%s' "$prompt" | grep -qiw 'ruview'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The token \"ruview\" in this message is the user'"'"'s abbreviation for: \"Run a review on this file. Check if there are any potential errors, conflicts, inconsistencies, missing or open points which need decisions etc. and list your findings by adding severity tags to each one (ignore low severity ones). Add a brief explanation, add a one sentence summary and also your fix suggestion for each of your findings.\" Treat each occurrence of ruview in the message as that instruction, applied to the file the user names or, if none is named, the file most recently under discussion. For each finding give: a severity tag (e.g. [CRITICAL], [HIGH], [MEDIUM]; omit low-severity findings entirely), a one-sentence summary, a brief explanation, and a suggested fix."
    }
  }'
fi
