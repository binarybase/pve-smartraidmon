PACKAGE = pve-smartraidmon
VERSION = 1.0.0

DESTDIR =
PREFIX  = /usr

PERL_MODDIR   = $(PREFIX)/share/perl5
JS_DIR        = $(PREFIX)/share/pve-manager/js
LIBEXEC_DIR   = $(PREFIX)/libexec/pve-smartraidmon
SHARE_DIR     = $(PREFIX)/share/pve-smartraidmon

.PHONY: all install clean deb

all:
	@echo "Nothing to build. Run 'make install' or 'make deb'."

install:
	# Perl API module
	install -d $(DESTDIR)$(PERL_MODDIR)/PVE/API2
	install -m 0644 src/PVE/API2/SmartRaidMon.pm \
		$(DESTDIR)$(PERL_MODDIR)/PVE/API2/SmartRaidMon.pm

	# smartctl wrapper script
	install -d $(DESTDIR)$(LIBEXEC_DIR)
	install -m 0755 src/bin/smart-raid-scan \
		$(DESTDIR)$(LIBEXEC_DIR)/smart-raid-scan

	# JavaScript GUI
	install -d $(DESTDIR)$(JS_DIR)
	install -m 0644 src/www/SmartRaidMon.js \
		$(DESTDIR)$(JS_DIR)/SmartRaidMon.js

	# API hook
	install -d $(DESTDIR)$(SHARE_DIR)
	install -m 0644 src/pve-api-hook.pl \
		$(DESTDIR)$(SHARE_DIR)/pve-api-hook.pl

clean:
	rm -rf debian/pve-smartraidmon debian/*.debhelper* debian/*.substvars \
		debian/files debian/*.log

deb:
	dpkg-buildpackage -us -uc -b
