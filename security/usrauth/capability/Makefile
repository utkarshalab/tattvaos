# security/usrauth/capability — build & test

MODULE := capability
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	cap.bin \
	restrict.bin \
	test_cap.bin

all: $(COMPONENTS)

cap.bin: src/cap.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o cap.bin src/cap.asm

restrict.bin: src/restrict.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o restrict.bin src/restrict.asm

test_cap.bin: tests/test_cap.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_cap.bin tests/test_cap.asm

test: all
	@echo "[usrauth/capability] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/capability Build Targets:"
	@echo "  all      - Build all capability modules"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
