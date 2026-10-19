# security/incident_response — build & test

MODULE := incident_response
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	incident_response.bin \
	triage.bin \
	containment.bin \
	eradication.bin \
	recovery.bin \
	playbooks.bin \
	test_incident_response.bin

all: $(COMPONENTS)

incident_response.bin: src/incident_response.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o incident_response.bin src/incident_response.asm

triage.bin: src/triage.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o triage.bin src/triage.asm

containment.bin: src/containment.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o containment.bin src/containment.asm

eradication.bin: src/eradication.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o eradication.bin src/eradication.asm

recovery.bin: src/recovery.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o recovery.bin src/recovery.asm

playbooks.bin: src/playbooks.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o playbooks.bin src/playbooks.asm

test_incident_response.bin: tests/test_incident_response.asm include/ir.inc
	$(ASM) $(ASMFLAGS) -o test_incident_response.bin tests/test_incident_response.asm

test: all
	@echo "[incident_response] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Incident Response Build Targets:"
	@echo "  all      - Assemble all 6 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"