#!/usr/bin/env bash

sub2() { echo "sub2: $1"; }

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
[[ $# -eq 0 ]] && { echo "Usage: sub2 <arg>" >&2; exit 1; }
"$@"
