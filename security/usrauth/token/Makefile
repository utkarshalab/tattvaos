# security/usrauth/token — build & test

MODULE := token
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test

COMPONENTS := \
	token.bin \
	caveat.bin \
	revoke.bin \
	token_minter.bin \
	test_token.bin

all: $(COMPONENTS)

token.bin: src/token.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o token.bin src/token.asm

caveat.bin: src/caveat.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o caveat.bin src/caveat.asm

revoke.bin: src/revoke.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o revoke.bin src/revoke.asm

token_minter.bin: src/token_minter.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o token_minter.bin src/token_minter.asm

test_token.bin: tests/test_token.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_token.bin tests/test_token.asm

test: all
	@echo "[usrauth/token] running skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "security/usrauth/token Build Targets:"
	@echo "  all      - Build all token modules"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
