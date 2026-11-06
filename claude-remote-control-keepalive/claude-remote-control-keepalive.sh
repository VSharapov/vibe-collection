#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

RC_KEEPALIVE_SCHEDULE="${RC_KEEPALIVE_SCHEDULE:-*/5 * * * *}"
RC_KEEPALIVE_LOG="${RC_KEEPALIVE_LOG:-$HOME/.local/state/claude-remote-control-keepalive.log}"
RC_KEEPALIVE_LOCK="${RC_KEEPALIVE_LOCK:-/tmp/claude-remote-control-keepalive.$UID.lock}"
RC_KEEPALIVE_WAIT="${RC_KEEPALIVE_WAIT:-20}"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
SELF="$(realpath "$0")"

_say() { >&2 echo "$(date +%FT%T) $*"; }

_is-claude() {
  local a0
  { IFS= read -r -d '' a0 <"$1/cmdline"; } 2>/dev/null || return 1
  [[ ${a0##*/} == claude ]]
}

_proc-config-dirs() {
  local p
  for p in /proc/[0-9]*; do
    _is-claude "$p" || continue
    { tr '\0' '\n' <"$p/environ" | grep -m1 '^CLAUDE_CONFIG_DIR=' | cut -d= -f2-; } 2>/dev/null || echo "$HOME/.claude"
  done
}

_config-dirs() {
  local d
  { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; echo "$HOME/.claude"; _proc-config-dirs; } | xargs -rd '\n' realpath -m | sort -u |
    while read -r d; do [[ -d $d/sessions ]] || continue; echo "$d"; done
}

_field() { jq -r ".$2 // empty" "$1"; }

_alive() {
  local stat
  stat=$(cat "/proc/$(_field "$1" pid)/stat" 2>/dev/null) || return 1
  set -- "$(_field "$1" procStart)" ${stat##*) }
  [[ $1 == "${21}" ]]
}

_session-files() {
  local d f
  for d in $(_config-dirs); do
    for f in "$d"/sessions/*.json; do _alive "$f" || continue; echo "$f"; done
  done
}

_matches() {
  local f=$1 t cwd
  shift
  [[ $# -gt 0 ]] || return 0
  cwd=$(realpath -m "$(_field "$f" cwd)")
  for t in "$@"; do
    if [[ $t == */* ]]; then
      t=$(realpath -m "$t")
      [[ $cwd == "$t" || $cwd == "$t"/* ]] && return 0
    else
      jq -e --arg t "$t" '[.sessionId, .jobId, .name] | index($t)' "$f" >/dev/null && return 0
    fi
  done
  return 1
}

_targets() {
  local f
  _session-files | while read -r f; do _matches "$f" "$@" || continue; echo "$f"; done
}

_rc-on() { jq -e '.bridgeSessionId' "$1" >/dev/null 2>&1; }

_label() { jq -r '.name // .jobId // .sessionId' "$1"; }

_pane() {
  local pane
  pane=$(_field "$1" tmux)
  [[ -n $pane ]] && tmux display -p -t "${pane##*.}" '#{pane_id}' 2>/dev/null
}

_prompt-line() {
  tmux capture-pane -e -p -t "$1" | awk '
    { p = $0; gsub(/\033\[[0-9;]*m/, "", p); sub(/^[ \t]+/, "", p) }
    p ~ /^❯/ && prev ~ /^─/ { hit = $0 }
    { prev = p }
    END { if (hit == "") exit 1; print hit }'
}

_has-draft() {
  local rest
  rest=$(_prompt-line "$1")
  rest=${rest#*❯}
  [[ -n $(sed 's/\x1b\[[0-9;]*m//g; s/\xc2\xa0//g; s/[[:space:]]//g' <<<"$rest") && $rest != *$'\e[2m'* ]]
}

_wait-prompt() {
  local i
  for i in $(seq "$RC_KEEPALIVE_WAIT"); do _prompt-line "$1" >/dev/null && return; sleep 1; done
  return 1
}

_consent() { tmux capture-pane -p -t "$1" | grep -q 'Enable Remote Control' && tmux send-keys -t "$1" Enter; }

_type-rc() {
  local pane=$1 f=$2 i
  _wait-prompt "$pane" || { echo "no prompt"; return 1; }
  ! _has-draft "$pane" || { echo "draft"; return 1; }
  tmux send-keys -t "$pane" -l /remote-control
  sleep 1
  tmux send-keys -t "$pane" Enter
  for i in $(seq "$RC_KEEPALIVE_WAIT"); do
    sleep 1
    _rc-on "$f" && { echo "on"; return; }
    _consent "$pane" || true
  done
  echo "failed"
  return 1
}

_via-attach() {
  local f=$1 s="rc-keepalive-$$" r=0
  tmux new-session -d -s "$s" -x 200 -y 50 \
    "CLAUDE_CONFIG_DIR=$(dirname "$(dirname "$f")") $CLAUDE_BIN attach $(_field "$f" jobId)"
  _type-rc "$s:" "$f" || r=$?
  tmux kill-session -t "$s" 2>/dev/null || true
  return $r
}

_turn-on() {
  local f=$1 pane
  [[ $(_field "$f" status) != busy ]] || { echo "busy"; return 1; }
  if pane=$(_pane "$f"); then _type-rc "$pane" "$f"
  elif [[ $(_field "$f" kind) == bg ]]; then _via-attach "$f"
  else echo "unreachable"; return 1
  fi
}

_via() {
  local pane
  if pane=$(_pane "$1"); then echo "$pane"
  elif [[ $(_field "$1" kind) == bg ]]; then echo attach
  else echo -
  fi
}

_describe() {
  local rc=off
  ! _rc-on "$1" || rc=on
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(_label "$1")" "$(_field "$1" jobId)" "$(_field "$1" status)" "$rc" "$(_via "$1")" "$(_field "$1" cwd)"
}

_cron-line() {
  local t args=()
  for t in "$@"; do [[ $t == */* ]] && t=$(realpath -m "$t"); args+=("$(printf '%q' "$t")"); done
  echo "$RC_KEEPALIVE_SCHEDULE $SELF tick ${args[*]} >/dev/null 2>>$RC_KEEPALIVE_LOG"
}

_crontab-without-us() { crontab -l 2>/dev/null | grep -vF "$SELF tick" || true; }

_lock() { exec 9>"$RC_KEEPALIVE_LOCK"; flock -n 9; }

tick() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  _lock || exit 0
  local f r
  for f in $(_targets "$@"); do
    _rc-on "$f" && continue
    r=$(_turn-on "$f") || true
    _say "$(_label "$f") $r"
  done
}

status() {
  local f
  for f in $(_targets "$@"); do _describe "$f"; done
}

enable() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  mkdir -p "$(dirname "$RC_KEEPALIVE_LOG")"
  { _crontab-without-us; _cron-line "$@"; } | crontab -
  >&2 echo "enabled: $(_cron-line "$@")"
}

disable() {
  _crontab-without-us | crontab -
  >&2 echo "disabled"
}

usage() {
  >&2 cat <<EOF
Keep Claude Code Remote Control on for chosen sessions, from cron.
A target is a sessionId, jobId or session name, or a dir (anything with a /) matching cwd and below.

Usage: ${0##*/} <command> [args...]
  enable <target>...   add or replace this script's crontab line
  disable              remove it
  tick <target>...     what cron runs: type /remote-control into targets whose RC is off
  status [target...]   live sessions (all if no target): name, job, status, rc, via, cwd
  usage --verbose      also list plumbing and env vars

Examples:
  ${0##*/} status
  ${0##*/} enable my-session <job-id> \$HOME/src/project
  ${0##*/} disable
EOF
  [[ $# -eq 1 && $1 == --verbose ]] || return 0
  >&2 cat <<EOF

Plumbing:
  _config-dirs             \$CLAUDE_CONFIG_DIR, ~/.claude, and each running claude's, if they have sessions/
  _session-files           registry files of live sessions (pid and procStart match)
  _targets [target...]     _session-files filtered by target
  _rc-on <file>            exit 0 if the session has a bridgeSessionId
  _turn-on <file>          type /remote-control into its tmux pane, or via claude attach for bg
  _pane <file>             its tmux pane id, if any
  _prompt-line <pane>      the raw ❯ input line under the ─ rule
  _has-draft <pane>        exit 0 if the input line holds non-dimmed text
  _describe <file>         one status line
  _cron-line <target>...   the crontab line enable would write

Env:
  RC_KEEPALIVE_SCHEDULE=$RC_KEEPALIVE_SCHEDULE
  RC_KEEPALIVE_LOG=$RC_KEEPALIVE_LOG
  RC_KEEPALIVE_LOCK=$RC_KEEPALIVE_LOCK
  RC_KEEPALIVE_WAIT=$RC_KEEPALIVE_WAIT
  CLAUDE_BIN=$CLAUDE_BIN
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
