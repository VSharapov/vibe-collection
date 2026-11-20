#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/subsub1.sh"
source "$SCRIPT_DIR/subsub2.sh"

sub1() { cat <<'EOF'
Usage: sub1 <command> [args]

Commands:
  subsub1 <arg>    Echo the arg
  subsub2          Print a message
EOF
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
[[ $# -eq 0 ]] && { sub1; exit 1; }
"$@"
