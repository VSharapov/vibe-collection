#!/usr/bin/env bash
set -euo pipefail

CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
CHATS_DIR="$CURSOR_DIR/chats"
PROJECTS_DIR="$CURSOR_DIR/projects"

# --- plumbing ---

get-name() {
  local uuid="$1"
  local db
  db="$(echo "$CHATS_DIR"/*/"$uuid"/store.db)"
  [[ -f "$db" ]] || { echo "(unknown)"; return; }
  sqlite3 "$db" "SELECT value FROM meta WHERE key='0'" | xxd -r -p | jq -r .name
}

get-transcript-path() {
  local uuid="$1"
  for f in "$PROJECTS_DIR"/*/agent-transcripts/"$uuid".txt; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
}

# grep transcripts, emit matching UUIDs (one per line)
# all args are passed through to rg (e.g. -i for case-insensitive)
search() {
  rg -l "$@" "$PROJECTS_DIR"/*/agent-transcripts/*.txt 2>/dev/null \
    | xargs -I{} basename {} .txt \
    | sort -u
}

# read UUIDs from stdin, emit uuid<TAB>name
annotate() {
  while IFS= read -r uuid; do
    local name
    name=$(get-name "$uuid" 2>/dev/null) || name="(unknown)"
    printf '%s\t%s\n' "$uuid" "$name"
  done
}

# fzf preview helper: name header + grep hits from transcript
# usage: preview <uuid> [rg flags] [pattern]
preview() {
  local uuid="$1"; shift
  echo "=== $(get-name "$uuid") ==="
  echo ""
  local tp
  tp=$(get-transcript-path "$uuid")
  if [[ -n "${tp:-}" ]]; then
    if [[ $# -gt 0 ]]; then
      rg --color=always -C2 "$@" "$tp" | head -80
    else
      head -80 "$tp"
    fi
  else
    echo "(no transcript file found)"
  fi
}

# --- porcelain ---

# search + fzf picker → prints transcript path of selected session
# all args are passed through to rg via search (last arg used as preview pattern)
search-fzf() {
  local rg_args=()
  for arg in "$@"; do rg_args+=("$(printf '%q' "$arg")"); done
  search "$@" \
    | annotate \
    | fzf --delimiter=$'\t' \
          --with-nth=2 \
          --preview "$0 preview {1} ${rg_args[*]}" \
          --preview-window=right:70% \
    | cut -d$'\t' -f1 \
    | while IFS= read -r uuid; do get-transcript-path "$uuid"; done
}

usage() {
  >&2 cat <<'EOF'
cursor-search — full-text search over Cursor agent transcripts

Usage: cursor-search <command> [args...]

Plumbing:
  get-name <uuid>              short name for a session
  get-transcript-path <uuid>   path to the .txt transcript
  search [rg flags] <pattern>   grep transcripts, list matching UUIDs
  annotate                     stdin UUIDs → uuid<TAB>name
  preview <uuid> [pattern]     name + transcript excerpt (for fzf)

Porcelain:
  search-fzf <pattern>         search → fzf picker → transcript path

Examples:
  cursor-search search "nvme"
  cursor-search search -i "nvme"
  cursor-search search "nvme" | cursor-search annotate
  cursor-search search-fzf "router"
  less "$(cursor-search search-fzf "sudo")"
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
