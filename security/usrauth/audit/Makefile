# security/usrauth/audit — build & test

MODULE := audit
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	decision_log.bin \
	audit_recorder.bin \
	audit_sealer.bin \
	test_audit.bin

all: $(COMPONENTS)

waf_decision_log.bin: src/audit_decision_log.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o waf_decision_log.bin src/audit_decision_log.asm

waf_audit_recorder.bin: src/audit_recorder.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o waf_audit_recorder.bin src/audit_recorder.asm

waf_audit_sealer.bin: src/audit_sealer.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o waf_audit_sealer.bin src/audit_sealer.asm

test_audit.bin: tests/test_audit.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_audit.bin tests/test_audit.asm

test: all
	@echo "[usrauth/audit] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/audit Build Targets:"
	@echo "  all      - Build all audit components"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
