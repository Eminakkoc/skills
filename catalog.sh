#!/usr/bin/env bash
# catalog: install skills, hooks, MCP servers, plugins and CLI tools from the
# Eminakkoc/skills index into ~/.claude (user scope) or a project's .claude/
# (project scope), keep them up to date, and maintain the index itself.
#
# Design: docs/catalog-design.md. Runs on macOS's bash 3.2, so no associative
# arrays or mapfile; lists are newline-separated strings.
#
# New machine:  curl -fsSL https://raw.githubusercontent.com/Eminakkoc/skills/main/catalog.sh | bash -s -- setup
set -euo pipefail

INDEX_REPO="${CATALOG_INDEX_REPO:-Eminakkoc/skills}"
INDEX_BRANCH="${CATALOG_INDEX_BRANCH:-main}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-catalog"
BIN_DIR="${CATALOG_BIN_DIR:-$HOME/.local/bin}"

LOCAL_INDEX="${CATALOG_LOCAL:-}"
OPT_USER=0 OPT_FORCE=0 OPT_YES=0 OPT_JSON=0 OPT_DRY=0
INDEX_DIR="" INDEX_SHA="" INDEX_ID="" CATALOG="" SOURCES=""
PROJECT_BASE=""

usage() {
  cat <<'EOF'
Usage: catalog <command> [args] [options]

Using the catalog
  setup [item|bundle:name ...]   install this script to ~/.local/bin and every
                                 user-scope item (or only those given)
  list [--installed]             list catalog items, or what is installed here
  add <item|bundle:name> ...     install items into this project (--user: ~/.claude)
  remove <item> ...              remove items installed by the catalog
  update [item ...]              move installed items to the index's current versions
                                 (also refreshes the catalog command itself)
  self-update                    replace ~/.local/bin/catalog with the index's catalog.sh
  doctor                         check installed items, files and required tools

Maintaining the index (run inside a checkout of the index repo)
  check-updates                  compare every source with upstream (read-only)
  bump <source> [version]        move a source's pin to a version (default: latest)
  readme                         regenerate the catalog table in README.md

Options
  --user        target ~/.claude instead of the current project
  --force       install user-scope items into a project / overwrite unmanaged files
  --yes, -y     answer yes to every confirmation
  --dry-run     show what update/doctor would change, change nothing
  --json        machine-readable output (list, check-updates)
  --local PATH  read the index from a local checkout instead of GitHub
EOF
}

die() { echo "catalog: $*" >&2; exit 1; }
say() { echo "$*"; }
warn() { echo "catalog: warning: $*" >&2; }

confirm() {
  [ "$OPT_YES" = 1 ] && return 0
  local answer
  if ! { exec 3</dev/tty; } 2>/dev/null; then
    die "$1 — no terminal to ask on; re-run with --yes to accept"
  fi
  printf '%s [y/N] ' "$1" >/dev/tty
  read -r answer <&3 || answer=""
  exec 3<&-
  case "$answer" in [yY]*) return 0 ;; *) return 1 ;; esac
}

need() { command -v "$1" >/dev/null || die "$1 not found${2:+ ($2)}"; }

# ---------------------------------------------------------------- index ----

fetch_repo() { # <owner/repo> <sha> -> prints the extracted directory (cached)
  local dir="$CACHE_DIR/${1//\//__}/$2" tmp
  if [ ! -d "$dir" ]; then
    mkdir -p "$CACHE_DIR"
    tmp=$(mktemp -d "$CACHE_DIR/.download.XXXXXX")
    if ! curl -fsSL "https://codeload.github.com/$1/tar.gz/$2" | tar -xz -C "$tmp" --strip-components=1; then
      rm -rf "$tmp"
      die "download failed: $1@$2"
    fi
    mkdir -p "$(dirname "$dir")"
    mv "$tmp" "$dir"
  fi
  echo "$dir"
}

github_head() { # <owner/repo> [branch] -> commit SHA
  local ref="HEAD"
  [ -n "${2:-}" ] && ref="refs/heads/$2"
  git ls-remote "https://github.com/$1" "$ref" | head -1 | cut -f1
}

load_index() {
  [ -n "$INDEX_DIR" ] && return 0
  if [ -n "$LOCAL_INDEX" ]; then
    INDEX_DIR=$(cd "$LOCAL_INDEX" && pwd)
    INDEX_SHA=$(git -C "$INDEX_DIR" rev-parse HEAD 2>/dev/null || echo "local")
    INDEX_ID="local:$INDEX_DIR"
  else
    INDEX_SHA=$(github_head "$INDEX_REPO" "$INDEX_BRANCH")
    [ -n "$INDEX_SHA" ] || die "cannot resolve $INDEX_REPO@$INDEX_BRANCH"
    INDEX_DIR=$(fetch_repo "$INDEX_REPO" "$INDEX_SHA")
    INDEX_ID="$INDEX_REPO"
  fi
  SOURCES="$INDEX_DIR/sources.json"
  [ -d "$INDEX_DIR/catalog" ] && [ -f "$SOURCES" ] || die "no catalog/ or sources.json in $INDEX_DIR"
  build_catalog
}

# The index keeps one file per item, catalog/<type>/<name>.json, and one per
# bundle, catalog/bundles/<name>.json. Everything else in this script reads a
# single combined document, built here into a temp file:
#   {version, items: {<name>: {kind, ...}}, bundles: {<name>: {description, items}}}
# The folder sets the kind and the file name sets the name, so neither is
# written inside the files. Item names must be unique across all types.
build_catalog() {
  local files
  files=$(find "$INDEX_DIR/catalog" -mindepth 2 -maxdepth 2 -name '*.json' | LC_ALL=C sort)
  [ -n "$files" ] || die "no item files in $INDEX_DIR/catalog"
  CATALOG=$(mktemp "${TMPDIR:-/tmp}/catalog.XXXXXX")
  trap 'rm -f "$CATALOG"' EXIT
  # shellcheck disable=SC2086 # file paths come from find and contain no spaces by convention
  jq -n --arg root "$INDEX_DIR/catalog/" '
    {skills: "skill", rules: "rule", hooks: "hook", plugins: "plugin", mcp: "mcp", tools: "tool"} as $kinds
    | reduce inputs as $x ({version: 1, items: {}, bundles: {}};
        (input_filename | ltrimstr($root) | split("/")) as [$dir, $file]
        | ($file | rtrimstr(".json")) as $name
        | if $dir == "bundles" then
            .bundles[$name] = {description: ($x.description // ""), items: ($x.items // [])}
          elif $kinds[$dir] == null then
            error("catalog/\($dir)/\($file): unknown folder (expected bundles, \($kinds | keys | join(", ")))")
          elif .items[$name] then
            error("catalog/\($dir)/\($file): the name \($name) is already used by a \(.items[$name].kind)")
          else
            .items[$name] = ({kind: $kinds[$dir]} + ($x | del(.kind)))
          end)
    | . as $c
    | [$c.bundles | to_entries[] | .key as $b | .value.items[] | select($c.items[.] == null) | "\($b): \(.)"] as $bad
    | if $bad == [] then $c else error("bundles list unknown items: \($bad | join(", "))") end
    ' $files >"$CATALOG" 2>"$CATALOG.err" || { cat "$CATALOG.err" >&2; rm -f "$CATALOG.err"; die "invalid catalog"; }
  rm -f "$CATALOG.err"
}

# Maintenance commands edit the index, so they need a local checkout.
load_maint_index() {
  if [ -z "$LOCAL_INDEX" ]; then
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$top" ] && [ -d "$top/catalog" ] && [ -f "$top/sources.json" ]; then
      LOCAL_INDEX="$top"
    else
      die "run inside a checkout of the index repo, or pass --local PATH"
    fi
  fi
  load_index
}

has_item() { jq -e --arg n "$1" '.items | has($n)' "$CATALOG" >/dev/null; }
iget() { jq -r --arg n "$1" --arg k "$2" '.items[$n][$k] // empty' "$CATALOG"; }
sget() { jq -r --arg s "$1" --arg k "$2" '.sources[$s][$k] // empty' "$SOURCES"; }
irequires() { jq -r --arg n "$1" '.items[$n].requires // [] | .[]' "$CATALOG"; }

expand_names() { # args -> item names, one per line, bundles expanded
  local a b
  for a in "$@"; do
    case "$a" in
      bundle:*)
        b=${a#bundle:}
        jq -e --arg b "$b" '.bundles | has($b)' "$CATALOG" >/dev/null || die "unknown bundle: $b"
        jq -r --arg b "$b" '.bundles[$b].items[]' "$CATALOG"
        ;;
      *)
        has_item "$a" || die "unknown item: $a (see: catalog list)"
        echo "$a"
        ;;
    esac
  done
}

# ---------------------------------------------------------------- scope ----

# Lock path for reporting commands: empty instead of dying when there is no project.
soft_lock_of() {
  if [ "$1" = project ]; then
    local b
    b=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    [ "$b" = "$HOME" ] && return 0
    PROJECT_BASE=$b
  fi
  lock_of "$1"
}

project_base() {
  if [ -z "$PROJECT_BASE" ]; then
    PROJECT_BASE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    [ "$PROJECT_BASE" != "$HOME" ] || die "refusing to treat \$HOME as a project; cd into a project or use --user"
  fi
  echo "$PROJECT_BASE"
}

base_of() { if [ "$1" = user ]; then echo "$HOME"; else project_base; fi; }
lock_of() { echo "$(base_of "$1")/.claude/catalog.lock.json"; }
settings_of() { echo "$(base_of "$1")/.claude/settings.json"; }

target_scope() { if [ "$OPT_USER" = 1 ]; then echo user; else echo project; fi; }

# Resolve the project base in this shell (not a subshell), so a refusal is
# reported once and PROJECT_BASE is cached for everything after.
init_scope() { if [ "$1" = project ]; then project_base >/dev/null; fi; }

# ----------------------------------------------------------------- json ----

jedit() { # <file> <filter> [jq args...]: edit a JSON file in place, creating it as {}
  local f=$1 filter=$2 tmp
  shift 2
  mkdir -p "$(dirname "$f")"
  [ -s "$f" ] || echo '{}' >"$f"
  tmp=$(mktemp)
  jq "$@" "$filter" "$f" >"$tmp"
  cat "$tmp" >"$f"
  rm -f "$tmp"
}

lock_get() { # <scope> <name> -> lock entry JSON or empty
  local l
  l=$(lock_of "$1")
  [ -f "$l" ] || return 0
  jq -c --arg n "$2" '.items[$n] // empty' "$l"
}

lock_names() { # <scope> -> installed item names
  local l
  l=$(lock_of "$1")
  [ -f "$l" ] || return 0
  jq -r '.items // {} | keys[]' "$l"
}

lock_put() { # <scope> <name> <entry json>
  jedit "$(lock_of "$1")" '.version = 1 | .index = {repo: $r, sha: $s} | .items[$n] = $e' \
    --arg r "$INDEX_ID" --arg s "$INDEX_SHA" --arg n "$2" --argjson e "$3"
}

lock_del() { jedit "$(lock_of "$1")" 'del(.items[$n])' --arg n "$2"; }

# ------------------------------------------------------------- versions ----

path_hash() { # content hash of a file or directory, independent of file modes and order
  if [ -f "$1" ]; then
    shasum -a 256 <"$1" | cut -c1-12
    return
  fi
  (cd "$1" && find . -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) |
    shasum -a 256 | cut -c1-12
}

item_src() { # <name> -> the item's file or directory in the index or upstream
  local src path repo pin dir
  src=$(iget "$1" source)
  path=$(iget "$1" path)
  if [ "$src" = self ]; then
    dir="$INDEX_DIR/$path"
  else
    repo=$(sget "$src" repo)
    pin=$(sget "$src" pinned)
    [ -n "$repo" ] && [ -n "$pin" ] || die "source $src of $1 has no repo/pinned"
    dir="$(fetch_repo "$repo" "$pin")/$path"
  fi
  [ -e "$dir" ] || die "$1: $path not found in source $src"
  echo "$dir"
}

item_version() { # <name> -> the version the index currently wants installed
  local kind src
  kind=$(iget "$1" kind)
  src=$(iget "$1" source)
  case "$kind" in
    skill | hook | rule)
      if [ "$src" = self ]; then path_hash "$(item_src "$1")"; else sget "$src" pinned; fi
      ;;
    tool | mcp) sget "$src" pinned ;;
    plugin) sget "$src" reviewed ;;
  esac
}

subst_version() { local v; v=$(sget "$(iget "$1" source)" pinned); echo "${2//\{version\}/$v}"; }

# -------------------------------------------------------------- install ----

copy_item() { # <scope> <name> <dest>: copy the item's file or directory, guarding local edits
  local scope=$1 name=$2 dest=$3 entry old_hash src
  entry=$(lock_get "$scope" "$name")
  if [ -e "$dest" ]; then
    if [ -z "$entry" ]; then
      [ "$OPT_FORCE" = 1 ] || die "$dest exists and was not installed by the catalog; use --force to replace it"
    else
      old_hash=$(echo "$entry" | jq -r '.hash // empty')
      if [ -n "$old_hash" ] && [ "$(path_hash "$dest")" != "$old_hash" ] && [ "$OPT_FORCE" != 1 ]; then
        confirm "$name has local edits in $dest. Overwrite them?" || die "left $name unchanged"
      fi
    fi
  fi
  src=$(item_src "$name")
  rm -rf "$dest"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  else
    mkdir -p "$dest"
    cp -R "$src/." "$dest"
  fi
}

hook_command() { # <scope> <name> <script>
  if [ "$1" = user ]; then
    echo "~/.claude/hooks/$2/$3"
  else
    echo "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/$2/$3"
  fi
}

settings_add_hook() { # <scope> <event> <matcher> <command>
  jedit "$(settings_of "$1")" '
    .hooks[$e] = ((.hooks[$e] // []) as $groups
      | if any($groups[]?.hooks[]?; .command == $c) then $groups
        else $groups + [({hooks: [{type: "command", command: $c}]}
                         + (if $m == "" then {} else {matcher: $m} end))]
        end)' --arg e "$2" --arg m "$3" --arg c "$4"
}

settings_remove_hook() { # <scope> <event> <command>
  local f
  f=$(settings_of "$1")
  [ -f "$f" ] || return 0
  jedit "$f" '
    if .hooks[$e] then
      .hooks[$e] |= (map(.hooks |= map(select(.command != $c))) | map(select(.hooks | length > 0)))
      | if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end' --arg e "$2" --arg c "$3"
}

ensure_marketplace() { # <name> <owner/repo>
  need claude "the Claude Code CLI"
  if ! claude plugin marketplace list --json | jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null; then
    claude plugin marketplace add "$2"
  fi
}

install_item() { # <scope> <name>
  local scope=$1 name=$2 kind src base cdir version entry dest
  kind=$(iget "$name" kind)
  src=$(iget "$name" source)
  base=$(base_of "$scope")
  cdir="$base/.claude"
  version=$(item_version "$name")

  case "$kind" in
    skill)
      dest="$cdir/skills/$name"
      copy_item "$scope" "$name" "$dest"
      [ -f "$dest/SKILL.md" ] || warn "$name has no SKILL.md"
      entry=$(jq -n --arg k "$kind" --arg s "$src" --arg v "$version" --arg h "$(path_hash "$dest")" \
        --arg f ".claude/skills/$name" '{kind: $k, source: $s, version: $v, hash: $h, files: [$f]}')
      ;;
    rule)
      dest="$cdir/rules/$name.md"
      copy_item "$scope" "$name" "$dest"
      entry=$(jq -n --arg k "$kind" --arg s "$src" --arg v "$version" --arg h "$(path_hash "$dest")" \
        --arg f ".claude/rules/$name.md" '{kind: $k, source: $s, version: $v, hash: $h, files: [$f]}')
      ;;
    hook)
      local event matcher script cmd
      event=$(jq -r --arg n "$name" '.items[$n].hook.event' "$CATALOG")
      matcher=$(jq -r --arg n "$name" '.items[$n].hook.matcher // ""' "$CATALOG")
      script=$(jq -r --arg n "$name" '.items[$n].hook.script' "$CATALOG")
      dest="$cdir/hooks/$name"
      copy_item "$scope" "$name" "$dest"
      chmod +x "$dest/$script"
      cmd=$(hook_command "$scope" "$name" "$script")
      settings_add_hook "$scope" "$event" "$matcher" "$cmd"
      entry=$(jq -n --arg k "$kind" --arg s "$src" --arg v "$version" --arg h "$(path_hash "$dest")" \
        --arg f ".claude/hooks/$name" --arg e "$event" --arg c "$cmd" \
        '{kind: $k, source: $s, version: $v, hash: $h, files: [$f], hook: {event: $e, command: $c}}')
      ;;
    mcp)
      local cfg
      cfg=$(jq -c --arg n "$name" '.items[$n].mcp' "$CATALOG")
      cfg=$(subst_version "$name" "$cfg")
      if [ "$scope" = user ]; then
        need claude "the Claude Code CLI"
        claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
        claude mcp add-json --scope user "$name" "$cfg"
      else
        jedit "$base/.mcp.json" '.mcpServers[$n] = $c' --arg n "$name" --argjson c "$cfg"
      fi
      entry=$(jq -n --arg k "$kind" --arg s "$src" --arg v "$version" '{kind: $k, source: $s, version: $v}')
      ;;
    plugin)
      local mkt mrepo plugin id
      mkt=$(sget "$src" marketplace)
      mrepo=$(sget "$src" marketplaceRepo)
      plugin=$(sget "$src" plugin)
      id="$plugin@$mkt"
      if [ "$scope" = user ]; then
        ensure_marketplace "$mkt" "$mrepo"
        claude plugin install "$id"
      else
        jedit "$(settings_of project)" '
          .extraKnownMarketplaces[$m] = {source: {source: "github", repo: $r}}
          | .enabledPlugins[$id] = true' --arg m "$mkt" --arg r "$mrepo" --arg id "$id"
      fi
      entry=$(jq -n --arg k "$kind" --arg s "$src" --arg v "$version" --arg id "$id" --arg m "$mkt" \
        '{kind: $k, source: $s, version: $v, plugin: $id, marketplace: $m}')
      ;;
    tool)
      local bin cmd
      [ "$scope" = user ] || die "$name is a tool; tools are always user scope"
      bin=$(iget "$name" bin)
      entry=$(lock_get user "$name")
      if command -v "$bin" >/dev/null && [ -z "$entry" ] && [ "$OPT_FORCE" != 1 ]; then
        say "  $bin already on PATH (not installed by the catalog); leaving it"
        version="external"
      else
        cmd=$(subst_version "$name" "$(iget "$name" install)")
        say "  running: $cmd"
        sh -c "$cmd"
      fi
      entry=$(jq -n --arg k "$kind" --arg s "$src" --arg v "$version" --arg b "$bin" \
        '{kind: $k, source: $s, version: $v, bin: $b}')
      ;;
    *) die "$name: unknown kind $kind" ;;
  esac

  lock_put "$scope" "$name" "$entry"
  say "✔ $name ($kind, $scope) @ $(echo "$version" | cut -c1-12)"
}

# Install an item and what it requires. Tools go to user scope, everything
# else to the requested scope. Already-installed items at the wanted version
# are skipped, as are tools that were already on PATH before the catalog.
add_one() { # <scope> <name> [dep]: dep=1 when pulled in by "requires" (--force does not apply)
  local scope=$1 name=$2 r iscope kind entry want
  kind=$(iget "$name" kind)
  iscope=$(iget "$name" scope)

  [ "$kind" = tool ] && scope=user
  if [ "$scope" = project ] && [ "$iscope" = user ] && [ "$OPT_FORCE" != 1 ]; then
    warn "$name is a user-scope item; skipped (install with --user, or --force to put it in this project)"
    return 0
  fi

  for r in $(irequires "$name"); do
    if has_item "$r"; then
      # A dependency that is a user item belongs in ~/.claude, whatever the dependent's scope.
      if [ "$(iget "$r" scope)" = user ]; then add_one user "$r" 1; else add_one "$scope" "$r" 1; fi
    elif ! command -v "$r" >/dev/null; then
      warn "$name needs '$r' on PATH, which is missing"
    fi
  done

  entry=$(lock_get "$scope" "$name")
  want=$(item_version "$name")
  if [ -n "$entry" ] && { [ "$OPT_FORCE" != 1 ] || [ -n "${3:-}" ]; } &&
    { [ "$(echo "$entry" | jq -r .version)" = "$want" ] || [ "$(echo "$entry" | jq -r .version)" = external ]; }; then
    say "• $name already installed ($scope) @ $(echo "$want" | cut -c1-12)"
    return 0
  fi
  install_item "$scope" "$name"
}

# -------------------------------------------------------------- uninstall ---

uninstall_item() { # <scope> <name>
  local scope=$1 name=$2 entry kind base f
  entry=$(lock_get "$scope" "$name")
  [ -n "$entry" ] || die "$name is not installed by the catalog in $scope scope"
  kind=$(echo "$entry" | jq -r .kind)
  base=$(base_of "$scope")

  case "$kind" in
    hook)
      settings_remove_hook "$scope" "$(echo "$entry" | jq -r .hook.event)" "$(echo "$entry" | jq -r .hook.command)"
      ;;
    mcp)
      if [ "$scope" = user ]; then
        claude mcp remove --scope user "$name" || true
      elif [ -f "$base/.mcp.json" ]; then
        jedit "$base/.mcp.json" 'del(.mcpServers[$n])' --arg n "$name"
      fi
      ;;
    plugin)
      if [ "$scope" = user ]; then
        claude plugin uninstall "$(echo "$entry" | jq -r .plugin)" || true
      else
        jedit "$(settings_of project)" '
          del(.enabledPlugins[$id])
          | if any(.enabledPlugins // {} | keys[]; endswith("@" + $m)) then .
            else del(.extraKnownMarketplaces[$m]) end
          | if .enabledPlugins == {} then del(.enabledPlugins) else . end
          | if .extraKnownMarketplaces == {} then del(.extraKnownMarketplaces) else . end' \
          --arg id "$(echo "$entry" | jq -r .plugin)" --arg m "$(echo "$entry" | jq -r .marketplace)"
      fi
      ;;
    tool)
      say "  $(echo "$entry" | jq -r .bin) left installed; uninstall it with its package manager if unwanted"
      ;;
  esac

  for f in $(echo "$entry" | jq -r '.files // [] | .[]'); do
    rm -rf "${base:?}/$f"
  done
  lock_del "$scope" "$name"
  say "✘ removed $name ($kind, $scope)"
}

# -------------------------------------------------------------- commands ----

cmd_setup() {
  need jq "brew install jq"
  need curl
  need git
  need claude "install Claude Code first"
  load_index

  mkdir -p "$BIN_DIR"
  cp "$INDEX_DIR/catalog.sh" "$BIN_DIR/catalog"
  chmod +x "$BIN_DIR/catalog"
  say "✔ installed $BIN_DIR/catalog"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not on PATH; add it to your shell profile" ;; esac

  local names name
  if [ $# -gt 0 ]; then
    names=$(expand_names "$@")
  else
    # Tools are left out: they arrive through the "requires" of what needs them.
    names=$(jq -r '.items | to_entries[] | select(.value.scope == "user" and .value.kind != "tool") | .key' "$CATALOG")
  fi
  OPT_USER=1
  for name in $names; do add_one user "$name"; done
  say "Done. Restart Claude Code to pick up the changes."
}

cmd_list() {
  load_index
  local installed=0 a
  for a in "$@"; do [ "$a" = --installed ] && installed=1; done

  if [ "$installed" = 0 ]; then
    if [ "$OPT_JSON" = 1 ]; then jq '.items' "$CATALOG"; return; fi
    jq -r '.items | to_entries[] | [.key, .value.kind, .value.scope, .value.source, .value.description] | @tsv' "$CATALOG" |
      awk -F'\t' '{ printf "%-42s %-7s %-8s %-22s %s\n", $1, $2, $3, $4, $5 }'
    say ""
    say "Bundles: $(jq -r '.bundles | keys | join(", ")' "$CATALOG")"
    return
  fi

  local scope l
  for scope in project user; do
    l=$(soft_lock_of "$scope")
    [ -n "$l" ] && [ -f "$l" ] || continue
    if [ "$OPT_JSON" = 1 ]; then jq --arg s "$scope" '{scope: $s} + .' "$l"; continue; fi
    say "$scope ($l):"
    jq -r '.items | to_entries[] | [.key, .value.kind, .value.version] | @tsv' "$l" |
      awk -F'\t' '{ printf "  %-42s %-7s %s\n", $1, $2, substr($3, 1, 12) }'
  done
}

cmd_add() {
  [ $# -gt 0 ] || die "usage: catalog add <item|bundle:name> ..."
  need jq "brew install jq"
  load_index
  local scope name
  scope=$(target_scope)
  init_scope "$scope"
  for name in $(expand_names "$@"); do add_one "$scope" "$name"; done
  if [ "$scope" = project ]; then
    say "Commit .claude/ (and .mcp.json if present) so the project carries these items."
  fi
}

cmd_remove() {
  [ $# -gt 0 ] || die "usage: catalog remove <item> ..."
  local scope name
  scope=$(target_scope)
  init_scope "$scope"
  for name in "$@"; do uninstall_item "$scope" "$name"; done
}

# Replace the installed command with the index's catalog.sh. The new file is
# moved into place rather than written over the old one, because bash reads a
# running script as it goes and would trip over its own file changing.
self_update() {
  load_index
  local dest="$BIN_DIR/catalog" tmp
  if [ ! -f "$dest" ]; then
    say "catalog command not installed in $BIN_DIR (run: catalog setup)"
    return 0
  fi
  if cmp -s "$INDEX_DIR/catalog.sh" "$dest"; then
    say "catalog command is up to date"
    return 0
  fi
  if [ "$OPT_DRY" = 1 ]; then
    say "catalog command: a newer version is available"
    return 0
  fi
  tmp=$(mktemp "$BIN_DIR/.catalog.XXXXXX")
  cp "$INDEX_DIR/catalog.sh" "$tmp"
  chmod +x "$tmp"
  mv "$tmp" "$dest"
  say "✔ catalog command updated ($dest)"
}

cmd_self_update() { self_update; }

cmd_update() {
  load_index
  local scope name entry kind have want note changes="" only=" $* "
  scope=$(target_scope)
  init_scope "$scope"
  self_update
  for name in $(lock_names "$scope"); do
    [ $# -eq 0 ] || case "$only" in *" $name "*) ;; *) continue ;; esac
    if ! has_item "$name"; then
      warn "$name is no longer in the catalog (remove it with: catalog remove $name)"
      continue
    fi
    entry=$(lock_get "$scope" "$name")
    kind=$(echo "$entry" | jq -r .kind)
    have=$(echo "$entry" | jq -r .version)
    want=$(item_version "$name")
    [ "$have" = "$want" ] && continue
    if [ "$kind" = plugin ]; then
      # The marketplace decides plugin versions; once Claude Code has the
      # reviewed one installed, just record it.
      if [ "$scope" = user ] && command -v claude >/dev/null &&
        claude plugin list --json | jq -e --arg id "$(echo "$entry" | jq -r .plugin)" --arg v "$want" \
          'any(.[]; .id == $id and .version == $v)' >/dev/null; then
        if [ "$OPT_DRY" = 1 ]; then
          say "  $name: installed plugin is the reviewed $want; will record it"
        else
          lock_put "$scope" "$name" "$(echo "$entry" | jq -c --arg v "$want" '.version = $v')"
          say "  $name: installed plugin is the reviewed $want; recorded"
        fi
      else
        say "  $name: index reviewed $want (was $have); update it with: claude plugin update $(echo "$entry" | jq -r .plugin)"
      fi
      continue
    fi
    if [ "$kind" = tool ] && [ "$have" = external ]; then continue; fi
    note=""
    if [ -n "$(echo "$entry" | jq -r '.hash // empty')" ] &&
      [ "$(path_hash "$(base_of "$scope")/$(echo "$entry" | jq -r '.files[0]')")" != "$(echo "$entry" | jq -r .hash)" ]; then
      note="  ← has local edits, which the update overwrites"
    fi
    say "  $name ($kind): $(echo "$have" | cut -c1-12) → $(echo "$want" | cut -c1-12)$note"
    changes="$changes $name"
  done

  if [ -z "$changes" ]; then say "Everything in $scope scope is up to date."; return; fi
  [ "$OPT_DRY" = 1 ] && return
  confirm "Apply these updates?" || { say "No changes made."; return; }
  for name in $changes; do install_item "$scope" "$name"; done
}

cmd_doctor() {
  load_index
  local scope l name entry kind base f bin problems=0 missing="" r hint
  for scope in user project; do
    l=$(soft_lock_of "$scope")
    [ -n "$l" ] && [ -f "$l" ] || continue
    base=$(base_of "$scope")
    hint=""
    [ "$scope" = user ] && hint=" --user"
    say "$scope ($l):"
    for name in $(lock_names "$scope"); do
      entry=$(lock_get "$scope" "$name")
      kind=$(echo "$entry" | jq -r .kind)
      for f in $(echo "$entry" | jq -r '.files // [] | .[]'); do
        if [ ! -e "$base/$f" ]; then
          say "  ✘ $name: $f is missing (reinstall: catalog add$hint --force $name)"
          problems=$((problems + 1))
        elif [ "$(echo "$entry" | jq -r '.hash // empty')" != "" ] && [ "$(path_hash "$base/$f")" != "$(echo "$entry" | jq -r .hash)" ]; then
          say "  ! $name: locally edited ($f)"
        fi
      done
      if [ "$kind" = tool ]; then
        bin=$(echo "$entry" | jq -r .bin)
        command -v "$bin" >/dev/null || { say "  ✘ $name: $bin not on PATH"; missing="$missing $name"; }
      fi
      if [ "$kind" = plugin ] && [ "$scope" = user ] && command -v claude >/dev/null; then
        claude plugin list --json | jq -e --arg id "$(echo "$entry" | jq -r .plugin)" 'any(.[]; .id == $id)' >/dev/null ||
          { say "  ✘ $name: plugin not installed"; problems=$((problems + 1)); }
      fi
      if has_item "$name"; then
        for r in $(irequires "$name"); do
          if has_item "$r"; then
            bin=$(iget "$r" bin)
            if [ -n "$bin" ] && ! command -v "$bin" >/dev/null; then
              say "  ✘ $name needs $r ($bin), which is not on PATH"
              missing="$missing $r"
            fi
          elif ! command -v "$r" >/dev/null; then
            say "  ✘ $name needs '$r' on PATH"
            problems=$((problems + 1))
          fi
        done
      fi
    done
  done

  missing=$(echo "$missing" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ')
  if [ -n "${missing// /}" ]; then
    if [ "$OPT_DRY" = 1 ]; then
      say "Missing tools:$missing (re-run without --dry-run to install)"
      problems=$((problems + 1))
    elif confirm "Install missing tools:$missing?"; then
      OPT_FORCE=1
      for name in $missing; do install_item user "$name"; done
      OPT_FORCE=0
    else
      problems=$((problems + 1))
    fi
  fi

  if [ "$problems" -eq 0 ]; then say "✔ all installed items look healthy"; else say "$problems problem(s) found"; return 1; fi
}

# ----------------------------------------------------------- maintenance ----

# Version key for a plugin, mirroring what Claude Code reports: the plugin's
# own plugin.json version, else the marketplace entry's version, else the
# pinned sha, else the last commit touching the plugin's directory.
plugin_latest() { # <source>
  local mrepo plugin entry stype repo ref path v
  mrepo=$(sget "$1" marketplaceRepo)
  plugin=$(sget "$1" plugin)
  entry=$(curl -fsSL "https://raw.githubusercontent.com/$mrepo/HEAD/.claude-plugin/marketplace.json" |
    jq -c --arg p "$plugin" '.plugins[] | select(.name == $p)')
  [ -n "$entry" ] || { echo "?"; return; }
  stype=$(echo "$entry" | jq -r 'if (.source | type) == "string" then "relative" else .source.source end')
  case "$stype" in
    relative)
      repo=$mrepo ref=HEAD path=$(echo "$entry" | jq -r '.source | ltrimstr("./")')
      ;;
    github)
      repo=$(echo "$entry" | jq -r .source.repo)
      ref=$(echo "$entry" | jq -r '.source.sha // .source.ref // "HEAD"') path=""
      ;;
    url | git-subdir)
      repo=$(echo "$entry" | jq -r '.source.url | capture("github\\.com[/:](?<r>[^/]+/[^/.]+)").r // empty')
      ref=$(echo "$entry" | jq -r '.source.sha // .source.ref // "HEAD"')
      path=$(echo "$entry" | jq -r '.source.path // ""')
      ;;
    *) repo="" ;;
  esac
  path=${path%/}
  if [ -n "$repo" ]; then
    v=$(curl -fsSL "https://raw.githubusercontent.com/$repo/$ref/${path:+$path/}.claude-plugin/plugin.json" 2>/dev/null |
      jq -r '.version // empty' 2>/dev/null || true)
    [ -n "$v" ] && { echo "$v"; return; }
  fi
  v=$(echo "$entry" | jq -r '.version // .source.sha? // empty')
  [ -n "$v" ] && { echo "$v"; return; }
  if [ -n "$repo" ] && command -v gh >/dev/null; then
    local q="path=$path&per_page=1"
    [ "$ref" = HEAD ] || q="$q&sha=$ref"
    v=$(gh api "repos/$repo/commits?$q" --jq '.[0].sha' 2>/dev/null | cut -c1-12)
    [ -n "$v" ] && { echo "$v"; return; }
  fi
  echo "?"
}

source_latest() { # <source> -> latest upstream version, or empty if unversioned
  local type
  type=$(sget "$1" type)
  case "$type" in
    github) github_head "$(sget "$1" repo)" "$(sget "$1" branch)" ;;
    npm) npm view "$(sget "$1" package)" version 2>/dev/null ;;
    pypi) curl -fsSL "https://pypi.org/pypi/$(sget "$1" package)/json" | jq -r .info.version ;;
    plugin) plugin_latest "$1" ;;
    remote-mcp) echo "" ;;
    *) die "source $1: unknown type $type" ;;
  esac
}

source_field() { if [ "$(sget "$1" type)" = plugin ]; then echo reviewed; else echo pinned; fi; }

cmd_check_updates() {
  load_maint_index
  local s type field cur latest report="[]" row compare files affected ahead status url code
  for s in $(jq -r '.sources | keys[]' "$SOURCES"); do
    type=$(sget "$s" type)
    field=$(source_field "$s")
    cur=$(sget "$s" "$field")
    latest=$(source_latest "$s" || true)
    affected=$(jq -c --arg s "$s" '[.items | to_entries[] | select(.value.source == $s) | .key]' "$CATALOG")
    ahead=null url=""
    if [ "$type" = remote-mcp ]; then
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$(sget "$s" url)" || true)
      if [ "$code" = 000 ]; then status=unreachable; else status=reachable; fi
    elif [ -z "$latest" ] || [ "$latest" = "?" ]; then
      status=unknown
    elif [ "$latest" = "$cur" ]; then
      status=current
    else
      status=update
      if [ "$type" = github ]; then
        url="https://github.com/$(sget "$s" repo)/compare/$cur...$latest"
        if command -v gh >/dev/null &&
          compare=$(gh api "repos/$(sget "$s" repo)/compare/$cur...$latest" 2>/dev/null); then
          ahead=$(echo "$compare" | jq .ahead_by)
          files=$(echo "$compare" | jq -c '[.files[]?.filename]')
          affected=$(jq -c --arg s "$s" --argjson files "$files" '
            [.items | to_entries[] | select(.value.source == $s)
             | select(.value.path as $p | any($files[]; startswith($p + "/") or . == $p)) | .key]' "$CATALOG")
          [ "$affected" = "[]" ] && status=unaffected
        fi
      fi
    fi
    row=$(jq -n --arg s "$s" --arg t "$type" --arg r "$(sget "$s" risk)" --arg f "$field" \
      --arg c "$cur" --arg l "$latest" --arg st "$status" --argjson a "$affected" \
      --argjson ah "$ahead" --arg u "$url" --arg cl "$(sget "$s" changelog)" '
      {source: $s, type: $t, risk: $r, field: $f, current: $c, latest: $l, status: $st,
       commitsAhead: $ah, affectedItems: $a}
      + (if $u == "" then {} else {compareUrl: $u} end)
      + (if $cl == "" then {} else {changelog: $cl} end)')
    report=$(echo "$report" | jq --argjson r "$row" '. + [$r]')
  done

  if [ "$OPT_JSON" = 1 ]; then echo "$report"; return; fi
  echo "$report" | jq -r '.[] | [.source, .status, .risk, (.current[0:12]), (.latest[0:12]), (.affectedItems | join(","))] | @tsv' |
    awk -F'\t' 'BEGIN { printf "%-24s %-12s %-7s %-13s %-13s %s\n", "SOURCE", "STATUS", "RISK", "CURRENT", "LATEST", "AFFECTED" }
                { printf "%-24s %-12s %-7s %-13s %-13s %s\n", $1, $2, $3, $4, $5, $6 }'
}

cmd_bump() {
  [ $# -ge 1 ] || die "usage: catalog bump <source> [version]"
  load_maint_index
  local s=$1 v=${2:-} field
  jq -e --arg s "$s" '.sources | has($s)' "$SOURCES" >/dev/null || die "unknown source: $s"
  field=$(source_field "$s")
  [ -n "$v" ] || v=$(source_latest "$s")
  [ -n "$v" ] && [ "$v" != "?" ] || die "could not determine the latest version of $s"
  jedit "$SOURCES" '.sources[$s][$f] = $v | .sources[$s][$f + "At"] = $d' \
    --arg s "$s" --arg f "$field" --arg v "$v" --arg d "$(date +%Y-%m-%d)"
  say "✔ $s.$field = $v"
}

cmd_readme() {
  load_maint_index
  local readme="$INDEX_DIR/README.md" table tmp
  grep -q '<!-- catalog:start -->' "$readme" || die "README.md has no <!-- catalog:start --> marker"
  table=$(mktemp)
  jq -r --slurpfile src "$SOURCES" '
    "| Item | Kind | Scope | Source | What it does |",
    "|---|---|---|---|---|",
    (.items | to_entries | sort_by(.value.kind, .key)[]
     | .value.source as $s
     | (if $s == "self" then "this repo"
        else ($src[0].sources[$s] | (.repo // .package // .marketplaceRepo // .url // $s)) end) as $from
     | "| `\(.key)` | \(.value.kind) | \(.value.scope) | \($from) | \(.value.description) |"),
    "",
    "| Bundle | What it is for | Items |",
    "|---|---|---|",
    (.bundles | to_entries[] | "| `bundle:\(.key)` | \(.value.description) | \(.value.items | join(", ")) |")
  ' "$CATALOG" >"$table"
  tmp=$(mktemp)
  awk -v table="$table" '
    /<!-- catalog:start -->/ { print; while ((getline line < table) > 0) print line; skip = 1; next }
    /<!-- catalog:end -->/ { skip = 0 }
    !skip' "$readme" >"$tmp"
  cat "$tmp" >"$readme"
  rm -f "$tmp" "$table"
  say "✔ README.md catalog table regenerated"
}

# ------------------------------------------------------------------ main ----

main() {
  local cmd positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --user) OPT_USER=1 ;;
      --force) OPT_FORCE=1 ;;
      --yes | -y) OPT_YES=1 ;;
      --json) OPT_JSON=1 ;;
      --dry-run) OPT_DRY=1 ;;
      --local) shift; LOCAL_INDEX=${1:?--local needs a path} ;;
      --local=*) LOCAL_INDEX=${1#--local=} ;;
      -h | --help) usage; return 0 ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  [ ${#positional[@]} -gt 0 ] || { usage; return 1; }
  set -- "${positional[@]}"
  cmd=$1
  shift
  need jq "brew install jq"

  case "$cmd" in
    setup) cmd_setup "$@" ;;
    list) cmd_list "$@" ;;
    add) cmd_add "$@" ;;
    remove | rm) cmd_remove "$@" ;;
    update) cmd_update "$@" ;;
    self-update) cmd_self_update "$@" ;;
    doctor) cmd_doctor "$@" ;;
    check-updates) cmd_check_updates "$@" ;;
    bump) cmd_bump "$@" ;;
    readme) cmd_readme "$@" ;;
    *) usage; die "unknown command: $cmd" ;;
  esac
}

main "$@"
