# Scaling Up

What to do when a tool grows complex or you want to unify existing tools.

## Incorporating existing tools

You have a standalone `oldtool.sh` that works fine. You want to roll it into a new `multitool.sh` without modifying `oldtool.sh`.

**Problem**: Can't source it — it ends with `"$@"` (no guard), so sourcing runs dispatch with wrong args.

**Solution**: Subprocess call.

```bash
# multitool.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

oldtool() { "$SCRIPT_DIR/oldtool/oldtool.sh" "$@"; }
newthing() { echo "new functionality"; }

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
```

Structure:
```
multitool.sh
├── oldtool/
│   └── oldtool.sh    # unchanged, standalone
└── newthing.sh       # new, uses dispatch pattern
```

Usage:
```bash
./multitool.sh oldtool subcommand arg    # calls oldtool.sh
./multitool.sh newthing                  # native function
```

## Generic dispatcher for multiple tools

If you have several standalone tools:

```bash
manage() {
  local tool="$1"; shift
  local script="$SCRIPT_DIR/$tool/$tool.sh"
  [[ -x "$script" ]] || { echo "Unknown: $tool" >&2; return 1; }
  "$script" "$@"
}
```

Structure:
```
multitool.sh
├── toolA/toolA.sh
├── toolB/toolB.sh
└── toolC/toolC.sh
```

Usage:
```bash
./multitool.sh manage toolA subcommand
./multitool.sh manage toolB other-cmd
```

Add tools by dropping folders — no code changes to `multitool.sh`.

## When to source vs subprocess

| Approach | Use when |
|----------|----------|
| **Source** | Tools designed together, shared helpers, single process |
| **Subprocess** | Adopting existing tools, isolation needed, different env vars |

Subprocess is cleaner for "umbrella" CLIs over independent tools.
Source is better for tightly integrated functionality sharing plumbing.

## Migration path

1. Start with single-file dispatch
2. Split into multi-file when functions exceed ~50 lines or you have 3+ subcommand levels
3. Wrap existing tools via subprocess when unifying
4. Extract shared plumbing into a `lib.sh` that everyone sources
