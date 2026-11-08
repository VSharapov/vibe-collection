#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

RC_KEEPALIVE_SCHEDULE="${RC_KEEPALIVE_SCHEDULE:-*/5 * * * *}"
RC_KEEPALIVE_LOG="${RC_KEEPALIVE_LOG:-$HOME/.local/state/claude-remote-control-keepalive.log}"
RC_KEEPALIVE_LOCK="${RC_KEEPALIVE_LOCK:-/tmp/claude-remote-control-keepalive.$UID.lock}"
RC_KEEPALIVE_WAIT="${RC_KEEPALIVE_WAIT:-20}"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
SELF="$(realpath "$0")"

_proc-is-claude() {
  local a0
  { IFS= read -r -d '' a0 <"$1/cmdline"; } 2>/dev/null || return 1
  [[ ${a0##*/} == claude ]]
}

_proc-config-dirs() { _config-dirs-of-all-claude-pids "$@"; }
_config-dirs-of-all-claude-pids() {
  local pid
  for pid in /proc/[0-9]*; do
    _proc-is-claude "$pid" || continue
    { tr '\0' '\n' <"$pid/environ" | grep -m1 '^CLAUDE_CONFIG_DIR=' | cut -d= -f2-; } 2>/dev/null || echo "$HOME/.claude"
  done
}

_config-dirs() { _list-claude-config-dirs "$@"; }
_list-claude-config-dirs() {
  local d
  { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; echo "$HOME/.claude"; _proc-config-dirs; } | xargs -rd '\n' realpath -m | sort -u |
    while read -r d; do [[ -d $d/sessions ]] || continue; echo "$d"; done
}

_field() { _value-of-key-in-json-file "$@"; }
_value-of-key-in-json-file() { jq -r ".$2 // empty" "$1"; }

_session-still-running() {
  local stat
  stat=$(cat "/proc/$(_field "$1" pid)/stat" 2>/dev/null) || return 1
  set -- "$(_field "$1" procStart)" ${stat##*) }
  [[ $1 == "${21}" ]]
}

_list-session-files-from-config-dirs() {
  local d f
  for d in $(_config-dirs); do
    for f in "$d"/sessions/*.json; do _session-still-running "$f" || continue; echo "$f"; done
  done
}

_session-matches-any-target() {
  local f=$1 t cwd
  shift
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

_list-session-files-matching-targets() {
  local f
  _list-session-files-from-config-dirs | while read -r f; do _session-matches-any-target "$f" "$@" || continue; echo "$f"; done
}

_rc-on() { _remote-control-is-on "$@"; }
_remote-control-is-on() { jq -e '.bridgeSessionId' "$1" >/dev/null 2>&1; }

_session-display-name() { jq -r '.name // .jobId // .sessionId' "$1"; }

_tmux-pane-of-session() {
  local pane
  pane=$(_field "$1" tmux)
  [[ -n $pane ]] && tmux display -p -t "${pane##*.}" '#{pane_id}' 2>/dev/null
}

_input-line-in-pane() {
  tmux capture-pane -e -p -t "$1" | awk '
    { p = $0; gsub(/\033\[[0-9;]*m/, "", p); sub(/^[ \t]+/, "", p) }
    p ~ /^❯/ && prev ~ /^─/ { hit = $0 }
    { prev = p }
    END { if (hit == "") exit 1; print hit }'
}

_pane-has-unsent-draft() {
  local rest
  rest=$(_input-line-in-pane "$1")
  rest=${rest#*❯}
  [[ -n $(sed 's/\x1b\[[0-9;]*m//g; s/\xc2\xa0//g; s/[[:space:]]//g' <<<"$rest") && $rest != *$'\e[2m'* ]]
}

_wait-for-input-line-in-pane() {
  local i
  for i in $(seq "$RC_KEEPALIVE_WAIT"); do _input-line-in-pane "$1" >/dev/null && return; sleep 1; done
  return 1
}

_accept-remote-control-dialog() { tmux capture-pane -p -t "$1" | grep -q 'Enable Remote Control' && tmux send-keys -t "$1" Enter; }

_type-remote-control-and-confirm() {
  local pane=$1 f=$2 i
  _wait-for-input-line-in-pane "$pane" || { echo "no prompt"; return 1; }
  ! _pane-has-unsent-draft "$pane" || { echo "draft"; return 1; }
  tmux send-keys -t "$pane" -l /remote-control
  sleep 1
  tmux send-keys -t "$pane" Enter
  for i in $(seq "$RC_KEEPALIVE_WAIT"); do
    sleep 1
    _rc-on "$f" && { echo "on"; return; }
    _accept-remote-control-dialog "$pane" || true
  done
  echo "failed"
  return 1
}

_turn-on-via-claude-attach() {
  local f=$1 s="rc-keepalive-$$" r=0
  tmux new-session -d -s "$s" -x 200 -y 50 \
    "CLAUDE_CONFIG_DIR=$(dirname "$(dirname "$f")") $CLAUDE_BIN attach $(_field "$f" jobId)"
  _type-remote-control-and-confirm "$s:" "$f" || r=$?
  tmux kill-session -t "$s" 2>/dev/null || true
  return $r
}

_turn-on-remote-control() {
  local f=$1 pane
  [[ $(_field "$f" status) != busy ]] || { echo "busy"; return 1; }
  if pane=$(_tmux-pane-of-session "$f"); then _type-remote-control-and-confirm "$pane" "$f"
  elif [[ $(_field "$f" kind) == bg ]]; then _turn-on-via-claude-attach "$f"
  else echo "unreachable"; return 1
  fi
}

_how-session-is-reachable() {
  local pane
  if pane=$(_tmux-pane-of-session "$1"); then echo "$pane"
  elif [[ $(_field "$1" kind) == bg ]]; then echo attach
  else echo -
  fi
}

_print-session-status-row() {
  local rc=off
  ! _rc-on "$1" || rc=on
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(_session-display-name "$1")" "$(_field "$1" jobId)" "$(_field "$1" status)" "$rc" "$(_how-session-is-reachable "$1")" "$(_field "$1" cwd)"
}

_crontab-line-for-targets() {
  local t args=()
  for t in "$@"; do [[ $t == */* ]] && t=$(realpath -m "$t"); args+=("$(printf '%q' "$t")"); done
  echo "$RC_KEEPALIVE_SCHEDULE $SELF tick ${args[*]} >/dev/null 2>>$RC_KEEPALIVE_LOG"
}

_crontab-without-us() { crontab -l 2>/dev/null | grep -vF "$SELF tick" || true; }

_take-single-run-lock() { exec 9>"$RC_KEEPALIVE_LOCK"; flock -n 9; }

tick() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  _take-single-run-lock || exit 0
  local f r
  for f in $(_list-session-files-matching-targets "$@"); do
    _rc-on "$f" && continue
    r=$(_turn-on-remote-control "$f") || true
    >&2 echo "$(date +%FT%T) $(_session-display-name "$f") $r"
  done
}

status() {
  local f files
  if [[ $# -gt 0 ]]; then files=$(_list-session-files-matching-targets "$@"); else files=$(_list-session-files-from-config-dirs); fi
  for f in $files; do _print-session-status-row "$f"; done
}

enable() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  mkdir -p "$(dirname "$RC_KEEPALIVE_LOG")"
  { _crontab-without-us; _crontab-line-for-targets "$@"; } | crontab -
  >&2 echo "enabled: $(_crontab-line-for-targets "$@")"
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
  _list-claude-config-dirs                          \$CLAUDE_CONFIG_DIR, ~/.claude, and each running claude's, if they have sessions/
  _list-session-files-from-config-dirs              registry files of live sessions (pid and procStart match)
  _list-session-files-matching-targets <target>...  live session files filtered by target
  _remote-control-is-on <file>                      exit 0 if the session has a bridgeSessionId
  _turn-on-remote-control <file>                    type /remote-control into its tmux pane, or via claude attach for bg
  _tmux-pane-of-session <file>                      its tmux pane id, if any
  _input-line-in-pane <pane>                        the raw ❯ input line under the ─ rule
  _pane-has-unsent-draft <pane>                     exit 0 if the input line holds non-dimmed text
  _print-session-status-row <file>                  one status line
  _crontab-line-for-targets <target>...             the crontab line enable would write

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
