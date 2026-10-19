# security/zero_trust — build & test

MODULE := zero_trust
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	policy_engine.bin \
	policy_administrator.bin \
	enforcement_point.bin \
	continuous_auth.bin \
	session_manager.bin \
	micro_segmentation.bin \
	posture_checker.bin \
	zero_trust.bin \
	test_zero_trust.bin

all: $(COMPONENTS)

policy_engine.bin: src/policy_engine.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o policy_engine.bin src/policy_engine.asm

policy_administrator.bin: src/policy_administrator.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o policy_administrator.bin src/policy_administrator.asm

enforcement_point.bin: src/enforcement_point.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o enforcement_point.bin src/enforcement_point.asm

continuous_auth.bin: src/continuous_auth.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o continuous_auth.bin src/continuous_auth.asm

session_manager.bin: src/session_manager.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o session_manager.bin src/session_manager.asm

micro_segmentation.bin: src/micro_segmentation.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o micro_segmentation.bin src/micro_segmentation.asm

posture_checker.bin: src/posture_checker.asm include/zero_trust.inc
	$(ASM) $(ASMFLAGS) -o posture_checker.bin src/posture_checker.asm

zero_trust.bin: src/zero_trust.asm include/zero_trust.inc ../usrauth/include/usrauth.inc
	$(ASM) $(ASMFLAGS) -o zero_trust.bin src/zero_trust.asm

test_zero_trust.bin: tests/test_zero_trust.asm include/zero_trust.inc ../usrauth/include/usrauth.inc
	$(ASM) $(ASMFLAGS) -o test_zero_trust.bin tests/test_zero_trust.asm

test: all
	@echo "[zero_trust] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Zero Trust Module Build Targets:"
	@echo "  all      - Assemble all 8 components"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"
