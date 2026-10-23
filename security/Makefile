# security/ — Utkarsha OS Enterprise Security Stack — Root Build

# Top-level Makefile that builds and tests every security module.
# Usage:
#   make               # build all modules
#   make test          # run all module test suites
#   make clean         # clean all build artifacts
#   make <module>      # build a single module
#   make test-<module> # test a single module

MODULES := \
	digital_forensics \
	ids \
	incident_response \
	ips \
	malwarescan \
	privacy_compliance \
	soar \
	supply_chain \
	threat_intel \
	usrauth \
	vuln_scan \
	waf \
	zero_trust

.PHONY: all test clean subdirs $(MODULES) test-%

all: subdirs

subdirs:
	@for m in $(MODULES); do \
		echo "[security] building $$m..."; \
		$(MAKE) -C $$m all || exit 1; \
	done

test: subdirs
	@for m in $(MODULES); do \
		echo "[security] testing $$m..."; \
		$(MAKE) -C $$m test || exit 1; \
	done

# Per-module targets: make digital_forensics, make test-digital_forensics, etc.
$(MODULES):
	$(MAKE) -C $@ all

test-%:
	$(MAKE) -C $* test

clean:
	@for m in $(MODULES); do \
		echo "[security] cleaning $$m..."; \
		$(MAKE) -C $$m clean 2>/dev/null || true; \
	done
	rm -rf bin/* build/*

help:
	@echo "Utkarsha OS Security Stack — Root Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all            Build all modules"
	@echo "  test           Run all module test suites"
	@echo "  clean          Clean all build artifacts"
	@echo "  help           Show this help"
	@echo ""
	@echo "Modules: $(MODULES)"
	@echo ""
	@echo "Per-module: make <module> | make test-<module> | make clean (in module dir)"
