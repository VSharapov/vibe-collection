# Agent-Facing Docs

Terse references for AI coding agents developing shell scripts.

## Core Patterns

- [PLANNING.md](./PLANNING.md) — write a plan, get user feedback, iterate
- [DISPATCH.md](./DISPATCH.md) — expose functions via `"$@"`, split files when deep
- [SCALING.md](./SCALING.md) — incorporating existing tools, subprocess vs source
- [DRAFTS.md](./DRAFTS.md) — patches as source of truth, reproducible builds
- [TESTING.md](./TESTING.md) — test plumbing directly, batch sudo calls
- [REPORTS.md](./REPORTS.md) — checkbox-driven iteration per draft

## Philosophy

- [TERSE.md](./TERSE.md) — lean scripts, `set -Eeuo pipefail`, no hand-holding

## Examples

- [examples/dispatch.sh](./examples/dispatch.sh) — single-file dispatch with internal functions
- [examples/multi-file/cmd.sh](./examples/multi-file/cmd.sh) — split dispatch for deep command trees

## Tools

- [pick.sh](./pick.sh) — select docs to feed an agent (`tree | fzf -m`)
