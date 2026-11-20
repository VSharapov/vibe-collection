# Drafts and Patches

Patches are the source of truth. Draft `.sh` files are disposable.

## Workflow

```bash
# First draft
touch script.sh
# write draft1.sh
diff -u script.sh draft1.sh > draft1.patch
patch script.sh < draft1.patch

# Subsequent drafts
cp script.sh draftN.sh
# edit draftN.sh
diff -u script.sh draftN.sh > draftN.patch
patch script.sh < draftN.patch
```

## Reconstruct anytime

```bash
make
```

## Makefile

```makefile
PATCHES := $(sort $(wildcard draft*.patch))

script.sh: $(PATCHES)
	> $@
	for p in $(PATCHES); do patch $@ < $$p; done
	chmod +x $@

clean:
	rm -f script.sh
```

## What to keep

- `script.sh` — final product
- `*.patch` — history (source of truth)
- `*.REPORT.md` — decision log
- `PLAN.md`, `README.md`, `Makefile`

## What to delete

- `draft*.sh` — reproducible from patches
- `test-draft*.sh` — test invokers
