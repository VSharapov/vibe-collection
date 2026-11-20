#!/usr/bin/env bash

subsub1() { echo "subsub1: $1"; }

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
[[ $# -eq 0 ]] && { echo "Usage: subsub1 <arg>" >&2; exit 1; }
"$@"
