# Agent Workflow: Iterative Shell Script Development

Terse reference for reproducing this development pattern with an AI coding agent.

## 1. Gather context

Look at the environment. `ls` the relevant paths. Understand what's there before writing anything.

## 2. PLAN.md

Write a plan doc with:
- **User story** — example invocations showing the full happy path, copy-pasteable
- **Function table** — split into plumbing (small composable) and porcelain (orchestration)
- **Details** — how each operation works
- **Open questions**

Tell the user to edit inline, you re-read and incorporate. Repeat until user satisfied with plan.

## 3. The dispatch pattern

All functions are exposed via `"$@"`. Internal functions are first-class — design them so they might be independently useful.

```bash
#!/usr/bin/env bash
set -euo pipefail

some-plumbing() { ... }
another-plumbing() { ... }
big-porcelain() { some-plumbing | another-plumbing; }
usage() { >&2 cat <<'EOF' ... EOF }

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
```

Porcelain functions compose plumbing: `big-operation(){ small1; small2; small3; }`. stdout for data, stderr for progress.

Preferably just use stdin and stdout, but temporary files might be necessary for multiple outputs.

## 4. Drafts and patches

```
touch script.sh        # empty target
# write draft1.sh
diff -u script.sh draft1.sh > draft1.patch
patch script.sh < draft1.patch

# subsequent drafts
cp draftN-1.sh draftN.sh  # start from previous
# edit draftN.sh
diff -u draftN-1.sh draftN.sh > draftN.patch
cp draftN.sh script.sh
```

Reconstruct anytime:
```bash
make
```

Draft `.sh` files are disposable — patches are the source of truth.

## 5. Testing

### Without sudo

Test plumbing functions yourself directly:
```
./script.sh usage
./script.sh find-big-file /media/...
./script.sh random-offset 1024 128
```

### With sudo

Don't invoke sudo repeatedly from the agent. Instead:

1. Write `test-draftN.sh` — a batch test script that:
   - Calls `sudo true` once at the top
   - Runs all tests sequentially
   - Uses `run-test` / `expect-output-contains` / `expect-exit` helpers
   - Writes captured output to `test-draftN.stdout` / `test-draftN.stderr`
   - `rm -f` any `/tmp/` files before redirecting (sticky bit + `fs.protected_regular`)
2. Tell the user: "Run this: `sudo ./test-draftN.sh > /tmp/fdd.stdout 2>/tmp/fdd.stderr`"
3. Await response
4. Read `/tmp/fdd.stdout` and `/tmp/fdd.stderr`, diagnose failures, iterate

## 6. REPORT.md per draft

Each draft gets a `draftN.REPORT.md`:
- Changes from previous draft
- Test results table
- Bugs found and fixed
- **Improvement ideas as checkboxes**: `- [ ] Idea text`

User checks boxes (`[x]`), possibly adds notes. Agent re-reads, implements checked items in next draft.

## 7. Interaction loop

```
Agent: writes PLAN.md, opens in editor
User:  edits PLAN.md, says "done"
Agent: reads PLAN.md, writes draft1.sh + patch, tests, writes draft1.REPORT.md
User:  checks [x] boxes in REPORT, may add notes below items, says "checked"
Agent: reads REPORT, implements [x] items in draft2.sh + patch + draft2.REPORT.md
...repeat...
User:  "draft N time" for another round, or "ship it"
```

## 8. Config convention

Hardcoded values → env vars with defaults:
```bash
FDD_BENCH_ROUNDS="${FDD_BENCH_ROUNDS:-8}"
FDD_BENCH_CHUNK_MIB="${FDD_BENCH_CHUNK_MIB:-128}"
```

For any arbitrary limit, use `THING="${THING:-sensible_default}"` so the user can override without editing the script.

## 9. Cleanup

Delete draft `.sh` files and test invokers (reproducible from patches). Keep:
- `script.sh` (the final product)
- `*.patch` (the history)
- `*.REPORT.md` (the decision log)
- `PLAN.md`, `README.md`, `WORKFLOW.md`, `Makefile`

## 10. Makefile

```makefile
PREFIX ?= /usr/local/bin

PATCHES := $(sort $(wildcard draft*.patch))

script.sh: $(PATCHES)
	> $@
	for p in $(PATCHES); do patch $@ < $$p; done
	chmod +x $@

install: script.sh
	install -m 755 script.sh $(PREFIX)/script

clean:
	rm -f script.sh

.PHONY: clean install
```

