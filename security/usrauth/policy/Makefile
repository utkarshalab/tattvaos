# security/usrauth/policy — build & test

MODULE := policy
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	attribute.bin \
	consent.bin \
	relation.bin \
	ttl.bin \
	policy_engine.bin \
	test_policy.bin

all: $(COMPONENTS)

attribute.bin: src/attribute.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o attribute.bin src/attribute.asm

consent.bin: src/consent.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o consent.bin src/consent.asm

relation.bin: src/relation.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o relation.bin src/relation.asm

ttl.bin: src/ttl.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o ttl.bin src/ttl.asm

policy_engine.bin: src/policy_engine.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o policy_engine.bin src/policy_engine.asm

test_policy.bin: tests/test_policy.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_policy.bin tests/test_policy.asm

test: all
	@echo "[usrauth/policy] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/policy Build Targets:"
	@echo "  all      - Build all policy modules"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
