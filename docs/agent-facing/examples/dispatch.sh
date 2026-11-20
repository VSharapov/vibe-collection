#!/usr/bin/env bash
set -Eeuo pipefail

# Single-file dispatch pattern.
# All functions exposed via "$@". Test any directly.

greet() { echo "Hello, ${1:-world}"; }

cl() { count-lines-in-file "$@"; }
count-lines-in-file() { wc -l < "$1"; }

both() {
  greet "$1"
  echo "Your file has $(cl "$2") lines"
}

usage() {
  >&2 cat <<'EOF'
Usage: dispatch.sh <command> [args...]

Commands:
  greet [name]         Say hello
  cl <file>            a.k.a. count-lines-in-file <file>
  both <name> <file>   Greet and count
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
