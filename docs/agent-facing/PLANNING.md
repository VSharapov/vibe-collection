# Planning

Before writing code, write `PLAN.md`.

## Contents

1. **User story** — example invocations, copy-pasteable, showing the happy path
2. **Function table** — plumbing (small, composable) vs porcelain (orchestration)
3. **Details** — how each operation works
4. **Open questions** — unknowns to resolve

## Loop

```
Agent: writes PLAN.md
User:  edits inline, says "done"
Agent: re-reads, incorporates changes
       repeat until plan is solid
```

Don't start coding until the plan is approved.

See also: [REPORTS.md](./REPORTS.md) for post-draft iteration.
