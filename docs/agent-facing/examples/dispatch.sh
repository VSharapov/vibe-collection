#!/usr/bin/env bash
set -Eeuo pipefail

# Single-file dispatch pattern.
# All functions exposed via "$@". Test any directly, plumbing included.

_cl() { _count-lines-in-file "$@"; }
_count-lines-in-file() { wc -l < "$1"; }

greet() { echo "Hello, ${1:-world}"; }

both() {
  greet "$1"
  echo "Your file has $(_cl "$2") lines"
}

usage() {
  >&2 cat <<'EOF'
Usage: dispatch.sh <command> [args...]

Commands:
  greet [name]         Say hello
  both <name> <file>   Greet and count
  usage --verbose      Also list plumbing
EOF
  [[ ${1:-} == --verbose ]] || return 0
  >&2 cat <<'EOF'

Plumbing:
  _cl <file>           a.k.a. _count-lines-in-file <file>
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
