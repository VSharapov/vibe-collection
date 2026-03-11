PREFIX ?= /usr/local/bin

PATCHES := $(sort $(wildcard draft*.patch))

namedotcom-dns.sh: $(PATCHES)
	> $@
	for p in $(PATCHES); do patch $@ < $$p; done
	chmod +x $@

install: namedotcom-dns.sh
	install -m 755 namedotcom-dns.sh $(PREFIX)/namedotcom-dns

clean:
	rm -f namedotcom-dns.sh

.PHONY: clean install
