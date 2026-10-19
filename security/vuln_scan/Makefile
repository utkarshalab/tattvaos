# security/vuln_scan — build & test

MODULE := vuln_scan
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	vuln_scan.bin \
	scanner.bin \
	assessor.bin \
	database.bin \
	reporter.bin \
	test_vuln_scan.bin

all: $(COMPONENTS)

vuln_scan.bin: src/vuln_scan.asm include/vuln_scan.inc
	$(ASM) $(ASMFLAGS) -o vuln_scan.bin src/vuln_scan.asm

scanner.bin: src/scanner.asm include/vuln_scan.inc
	$(ASM) $(ASMFLAGS) -o scanner.bin src/scanner.asm

assessor.bin: src/assessor.asm include/vuln_scan.inc
	$(ASM) $(ASMFLAGS) -o assessor.bin src/assessor.asm

database.bin: src/database.asm include/vuln_scan.inc
	$(ASM) $(ASMFLAGS) -o database.bin src/database.asm

reporter.bin: src/reporter.asm include/vuln_scan.inc
	$(ASM) $(ASMFLAGS) -o reporter.bin src/reporter.asm

test_vuln_scan.bin: tests/test_vuln_scan.asm include/vuln_scan.inc
	$(ASM) $(ASMFLAGS) -o test_vuln_scan.bin tests/test_vuln_scan.asm

test: all
	@echo "[vuln_scan] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Vulnerability Scan Build Targets:"
	@echo "  all      - Assemble all 5 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"