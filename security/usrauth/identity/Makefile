# security/usrauth/identity — build & test

MODULE := identity
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	password.bin \
	webauthn.bin \
	svid.bin \
	attest.bin \
	test_identity.bin

all: $(COMPONENTS)

password.bin: src/password.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o password.bin src/password.asm

webauthn.bin: src/webauthn.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o webauthn.bin src/webauthn.asm

svid.bin: src/svid.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o svid.bin src/svid.asm

attest.bin: src/attest.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o attest.bin src/attest.asm

test_identity.bin: tests/test_identity.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_identity.bin tests/test_identity.asm

test: all
	@echo "[usrauth/identity] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/identity Build Targets:"
	@echo "  all      - Build all identity modules"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
