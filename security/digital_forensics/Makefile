# security/digital_forensics — build & test

MODULE := digital_forensics
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	dfir.bin \
	acquirer.bin \
	analyzer.bin \
	custody.bin \
	reporter.bin \
	test_dfir.bin

all: $(COMPONENTS)

dfir.bin: src/dfir.asm include/dfir.inc
	$(ASM) $(ASMFLAGS) -o dfir.bin src/dfir.asm

acquirer.bin: src/acquirer.asm include/dfir.inc
	$(ASM) $(ASMFLAGS) -o acquirer.bin src/acquirer.asm

analyzer.bin: src/analyzer.asm include/dfir.inc
	$(ASM) $(ASMFLAGS) -o analyzer.bin src/analyzer.asm

custody.bin: src/custody.asm include/dfir.inc
	$(ASM) $(ASMFLAGS) -o custody.bin src/custody.asm

reporter.bin: src/reporter.asm include/dfir.inc
	$(ASM) $(ASMFLAGS) -o reporter.bin src/reporter.asm

test_dfir.bin: tests/test_dfir.asm include/dfir.inc
	$(ASM) $(ASMFLAGS) -o test_dfir.bin tests/test_dfir.asm

test: all
	@echo "[digital_forensics] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Digital Forensics Build Targets:"
	@echo "  all      - Assemble all 5 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"