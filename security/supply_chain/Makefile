# security/supply_chain — build & test

MODULE := supply_chain
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	supply_chain.bin \
	sbom.bin \
	provenance.bin \
	attestation.bin \
	verification.bin \
	test_supply_chain.bin

all: $(COMPONENTS)

supply_chain.bin: src/supply_chain.asm include/supply_chain.inc
	$(ASM) $(ASMFLAGS) -o supply_chain.bin src/supply_chain.asm

sbom.bin: src/sbom.asm include/supply_chain.inc
	$(ASM) $(ASMFLAGS) -o sbom.bin src/sbom.asm

provenance.bin: src/provenance.asm include/supply_chain.inc
	$(ASM) $(ASMFLAGS) -o provenance.bin src/provenance.asm

attestation.bin: src/attestation.asm include/supply_chain.inc
	$(ASM) $(ASMFLAGS) -o attestation.bin src/attestation.asm

verification.bin: src/verification.asm include/supply_chain.inc
	$(ASM) $(ASMFLAGS) -o verification.bin src/verification.asm

test_supply_chain.bin: tests/test_supply_chain.asm include/supply_chain.inc
	$(ASM) $(ASMFLAGS) -o test_supply_chain.bin tests/test_supply_chain.asm

test: all
	@echo "[supply_chain] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Supply Chain Build Targets:"
	@echo "  all      - Assemble all 5 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"