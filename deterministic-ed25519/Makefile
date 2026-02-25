PREFIX ?= /usr/local/bin

PATCHES := $(sort $(wildcard draft*.patch))

seedkey.sh: $(PATCHES)
	> $@
	for p in $(PATCHES); do patch $@ < $$p; done
	chmod +x $@

install: seedkey.sh
	install -m 755 seedkey.sh $(PREFIX)/seedkey

clean:
	rm -f seedkey.sh

.PHONY: clean install
