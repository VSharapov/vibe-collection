# Dispatch Pattern

Expose all functions via `"$@"`. Internal functions are first-class.

## Naming

- Plumbing starts with `_`; porcelain doesn't. The name says which layer you're calling.
- Function names are self-explanatory at the definition. If a long name is called often, prepend a one-line shortname wrapper on the line above it.

## Usage

`usage` lists porcelain only. `usage --verbose` also lists plumbing and env vars: plumbing is first-class, so it's documented, just not up front. Wrappers show both names: `_short <args>   a.k.a. _long-clear-name <args>`.

## Single-file (simple tools)

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

_small-composable-unit() { echo "one"; }
_u2() { _another-unit-with-a-long-name "$@"; }
_another-unit-with-a-long-name() { echo "two"; }
porcelain() { _small-composable-unit; _u2; }

usage() {
  >&2 cat <<'EOF'
Usage: cmd <command> [args...]
  porcelain          does the thing
  usage --verbose    also list plumbing
EOF
  [[ ${1:-} == --verbose ]] || return 0
  >&2 cat <<'EOF'

Plumbing:
  _small-composable-unit
  _u2                a.k.a. _another-unit-with-a-long-name
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
```

Test any function directly: `./script.sh _small-composable-unit`

## Multi-file (deep command trees)

When you have `cmd subcmd subsubcmd`, split into files.

**The pattern** (each sourceable file):

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/child.sh"                      # 1. load children (if any)

myfunc() { ... }                                   # 2. define functions

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0   # 3. bail if sourced

[[ $# -eq 0 ]] && { usage; exit 1; }              # 4. usage if no args
"$@"                                               # 5. dispatch
```

**Example structure:**

```
cmd.sh              # entry: sources sub1, sub2
├── sub1.sh         # branch: sources subsub1, subsub2
│   ├── subsub1.sh  # leaf
│   └── subsub2.sh  # leaf
└── sub2.sh         # leaf
```

**Invocations:**

```bash
./cmd.sh version          # top-level function
./cmd.sh sub1             # shows sub1 usage
./cmd.sh subsub1 hello    # calls leaf with arg
./sub1.sh subsub1 hello   # direct invocation works too
```

See: [examples/multi-file/](./examples/multi-file/)

## Why this works

- Sourcing loads function definitions only (guard bails before dispatch)
- `"$@"` dispatches to any function in the tree
- Each file independently runnable and testable
- No case statements, no dispatch wrappers

## When it gets complex

See [SCALING.md](./SCALING.md) for:
- Incorporating existing standalone tools
- When to use subprocess calls vs sourcing
