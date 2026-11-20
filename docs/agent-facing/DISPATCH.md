# Dispatch Pattern

Expose all functions via `"$@"`. Internal functions are first-class.

Function names are self-explanatory at the definition. If a long name is called often, prepend a one-line shortname wrapper; usage shows both.

## Single-file (simple tools)

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

plumbing1() { echo "small composable unit"; }
plumbing2() { echo "another small unit"; }
porcelain() { plumbing1; plumbing2; }

usage() { cat <<'EOF'
Usage: cmd <command> [args...]
Commands: plumbing1, plumbing2, porcelain
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
```

Test any function directly: `./script.sh plumbing1`

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
- No case statements, no wrapper functions

## When it gets complex

See [SCALING.md](./SCALING.md) for:
- Incorporating existing standalone tools
- When to use subprocess calls vs sourcing
