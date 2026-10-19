# security/usrauth/subject — build & test

MODULE := subject
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	table.bin \
	transition.bin \
	subject_registry.bin \
	test_subject.bin

all: $(COMPONENTS)

table.bin: src/table.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o table.bin src/table.asm

transition.bin: src/transition.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o transition.bin src/transition.asm

subject_registry.bin: src/subject_registry.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o subject_registry.bin src/subject_registry.asm

test_subject.bin: tests/test_subject.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_subject.bin tests/test_subject.asm

test: all
	@echo "[usrauth/subject] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/subject Build Targets:"
	@echo "  all      - Build all subject modules"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
