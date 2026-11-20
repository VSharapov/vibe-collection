#!/usr/bin/env bash

subsub2() { echo "subsub2: hello from the leaf"; }

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
"$@"
