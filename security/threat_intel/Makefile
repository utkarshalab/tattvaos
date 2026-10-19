# security/threat_intel — build & test

MODULE := threat_intel
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	threat_intel.bin \
	store.bin \
	ingestor.bin \
	exporter.bin \
	correlator.bin \
	test_threat_intel.bin

all: $(COMPONENTS)

threat_intel.bin: src/threat_intel.asm include/threat_intel.inc
	$(ASM) $(ASMFLAGS) -o threat_intel.bin src/threat_intel.asm

store.bin: src/store.asm include/threat_intel.inc
	$(ASM) $(ASMFLAGS) -o store.bin src/store.asm

ingestor.bin: src/ingestor.asm include/threat_intel.inc
	$(ASM) $(ASMFLAGS) -o ingestor.bin src/ingestor.asm

exporter.bin: src/exporter.asm include/threat_intel.inc
	$(ASM) $(ASMFLAGS) -o exporter.bin src/exporter.asm

correlator.bin: src/correlator.asm include/threat_intel.inc
	$(ASM) $(ASMFLAGS) -o correlator.bin src/correlator.asm

test_threat_intel.bin: tests/test_threat_intel.asm include/threat_intel.inc
	$(ASM) $(ASMFLAGS) -o test_threat_intel.bin tests/test_threat_intel.asm

test: all
	@echo "[threat_intel] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Threat Intelligence Build Targets:"
	@echo "  all      - Assemble all 5 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"