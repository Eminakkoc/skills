#!/usr/bin/env bash
# Bootstrap a machine: register this repo as a Claude Code marketplace and
# install every plugin it lists (my own toolkit plus referenced third-party ones).
#
# Usage: ./install.sh            # register from GitHub (Eminakkoc/skills)
#        ./install.sh --local    # register from this checkout (edits apply live)
set -euo pipefail

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found (hooks need it): brew install jq" >&2; exit 1; }

repo_dir=$(cd "$(dirname "$0")" && pwd)
source="Eminakkoc/skills"
[[ "${1:-}" == "--local" ]] && source="$repo_dir"

marketplace=$(jq -r '.name' "$repo_dir/.claude-plugin/marketplace.json")

claude plugin marketplace add "$source" || claude plugin marketplace update "$marketplace"

jq -r '.plugins[].name' "$repo_dir/.claude-plugin/marketplace.json" | while read -r plugin; do
  claude plugin install "$plugin@$marketplace"
done

echo "Done. Restart Claude Code to pick up the plugins."
