#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
pwd
tree -F | fzf -m --layout=reverse --header="Use Tab to select files"
