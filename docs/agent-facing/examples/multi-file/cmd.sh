#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/sub1.sh"
source "$SCRIPT_DIR/sub2.sh"

usage() { cat <<'EOF'
Usage: cmd <command> [args]

Commands:
  version             Print version
  sub1                Has subcommands: subsub1, subsub2
  sub2 <arg>          Leaf command, echoes arg
EOF
}

version() { echo "cmd v0.1.0"; }

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
