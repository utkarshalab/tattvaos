# security/usrauth/mandatory — build & test

MODULE := mandatory
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	integrity.bin \
	mls.bin \
	te.bin \
	label_manager.bin \
	test_mandatory.bin

all: $(COMPONENTS)

integrity.bin: src/integrity.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o integrity.bin src/integrity.asm

mls.bin: src/mls.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o mls.bin src/mls.asm

te.bin: src/te.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o te.bin src/te.asm

label_manager.bin: src/label_manager.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o label_manager.bin src/label_manager.asm

test_mandatory.bin: tests/test_mandatory.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_mandatory.bin tests/test_mandatory.asm

test: all
	@echo "[usrauth/mandatory] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/mandatory Build Targets:"
	@echo "  all      - Build all mandatory modules"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
