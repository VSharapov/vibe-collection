PREFIX ?= /usr/local/bin

PATCHES := $(sort $(wildcard draft*.patch))

fdd-bench.sh: $(PATCHES)
	> $@
	for p in $(PATCHES); do patch $@ < $$p; done
	chmod +x $@

install: fdd-bench.sh
	install -m 755 fdd-bench.sh $(PREFIX)/fdd-bench

clean:
	rm -f fdd-bench.sh

.PHONY: clean install
