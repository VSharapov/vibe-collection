# Reports

Each draft gets `draftN.REPORT.md`.

## Contents

- Changes from previous draft
- Test results (table or list)
- Bugs found and fixed
- **Improvement ideas as checkboxes**

## Checkbox convention

```markdown
## Ideas for next draft

- [ ] Add retry logic for flaky network calls
- [ ] Support reading from stdin
- [x] User checked this one
      Agent: user added a note here, implement accordingly
```

## Loop

```
Agent: writes draftN.REPORT.md with [ ] checkboxes
User:  checks [x] items, may add notes below
       says "checked" or "next draft"
Agent: reads REPORT, implements [x] items in draft(N+1)
```

See also: [PLANNING.md](./PLANNING.md) for pre-draft iteration.
