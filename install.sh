#!/usr/bin/env bash
# Bootstrap a machine: add every marketplace and install every plugin listed in
# plugins.json (my own marketplace plus the third-party ones I use), all at
# user scope. Safe to re-run: present marketplaces and plugins are skipped.
#
# Usage: ./install.sh            # my marketplace from GitHub (Eminakkoc/skills)
#        ./install.sh --local    # my marketplace from this checkout (edits apply live)
set -euo pipefail

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found (hooks need it): brew install jq" >&2; exit 1; }

repo_dir=$(cd "$(dirname "$0")" && pwd)
manifest="$repo_dir/plugins.json"
own=$(jq -r '.name' "$repo_dir/.claude-plugin/marketplace.json")

known=$(claude plugin marketplace list --json | jq -r '.[].name')

jq -r '.marketplaces | to_entries[] | "\(.key) \(.value)"' "$manifest" | while read -r name source; do
  [[ "$name" == "$own" && "${1:-}" == "--local" ]] && source="$repo_dir"
  if grep -qx "$name" <<<"$known"; then
    claude plugin marketplace update "$name"
  else
    claude plugin marketplace add "$source"
  fi
done

jq -r '.plugins[]' "$manifest" | while read -r plugin; do
  claude plugin install "$plugin"
done

echo "Done. Restart Claude Code to pick up the plugins."
