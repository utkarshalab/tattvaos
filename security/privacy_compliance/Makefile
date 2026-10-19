# security/privacy_compliance — build & test

MODULE := privacy_compliance
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	privacy_compliance.bin \
	dlp_engine.bin \
	consent.bin \
	classifier.bin \
	reporter.bin \
	test_privacy_compliance.bin

all: $(COMPONENTS)

privacy_compliance.bin: src/privacy_compliance.asm include/privacy.inc
	$(ASM) $(ASMFLAGS) -o privacy_compliance.bin src/privacy_compliance.asm

dlp_engine.bin: src/dlp_engine.asm include/privacy.inc
	$(ASM) $(ASMFLAGS) -o dlp_engine.bin src/dlp_engine.asm

consent.bin: src/consent.asm include/privacy.inc
	$(ASM) $(ASMFLAGS) -o consent.bin src/consent.asm

classifier.bin: src/classifier.asm include/privacy.inc
	$(ASM) $(ASMFLAGS) -o classifier.bin src/classifier.asm

reporter.bin: src/reporter.asm include/privacy.inc
	$(ASM) $(ASMFLAGS) -o reporter.bin src/reporter.asm

test_privacy_compliance.bin: tests/test_privacy_compliance.asm include/privacy.inc
	$(ASM) $(ASMFLAGS) -o test_privacy_compliance.bin tests/test_privacy_compliance.asm

test: all
	@echo "[privacy_compliance] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Privacy Compliance Build Targets:"
	@echo "  all      - Assemble all 5 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"