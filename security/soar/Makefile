# security/soar — build & test

MODULE := soar
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	soar.bin \
	core_engine.bin \
	playbook_engine.bin \
	alert_ingestor.bin \
	action_engine.bin \
	playbook_compiler.bin \
	case_manager.bin \
	automation_engine.bin \
	integration_engine.bin \
	scheduler.bin \
	metrics_engine.bin \
	threat_intel_integration.bin \
	vulnerability_integration.bin \
	asset_inventory.bin \
	risk_scoring_engine.bin \
	notification_engine.bin \
	evidence_collector.bin \
	remediation_engine.bin \
	compliance_reporter.bin \
	forensic_integrator.bin \
	malware_analyzer.bin \
	user_behavior_analytics.bin \
	decoy_manager.bin \
	threat_hunting_integration.bin \
	incident_timeline_builder.bin \
	playbook_tester.bin \
	asset_criticality_scorer.bin \
	test_soar.bin

all: $(COMPONENTS)

soar.bin: src/soar.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o soar.bin src/soar.asm

core_engine.bin: src/core_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o core_engine.bin src/core_engine.asm

playbook_engine.bin: src/playbook_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o playbook_engine.bin src/playbook_engine.asm

alert_ingestor.bin: src/alert_ingestor.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o alert_ingestor.bin src/alert_ingestor.asm

action_engine.bin: src/action_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o action_engine.bin src/action_engine.asm

playbook_compiler.bin: src/playbook_compiler.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o playbook_compiler.bin src/playbook_compiler.asm

case_manager.bin: src/case_manager.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o case_manager.bin src/case_manager.asm

automation_engine.bin: src/automation_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o automation_engine.bin src/automation_engine.asm

integration_engine.bin: src/integration_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o integration_engine.bin src/integration_engine.asm

scheduler.bin: src/scheduler.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o scheduler.bin src/scheduler.asm

metrics_engine.bin: src/metrics_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o metrics_engine.bin src/metrics_engine.asm

threat_intel_integration.bin: src/threat_intel_integration.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o threat_intel_integration.bin src/threat_intel_integration.asm

vulnerability_integration.bin: src/vulnerability_integration.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o vulnerability_integration.bin src/vulnerability_integration.asm

asset_inventory.bin: src/asset_inventory.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o asset_inventory.bin src/asset_inventory.asm

risk_scoring_engine.bin: src/risk_scoring_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o risk_scoring_engine.bin src/risk_scoring_engine.asm

notification_engine.bin: src/notification_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o notification_engine.bin src/notification_engine.asm

evidence_collector.bin: src/evidence_collector.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o evidence_collector.bin src/evidence_collector.asm

remediation_engine.bin: src/remediation_engine.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o remediation_engine.bin src/remediation_engine.asm

compliance_reporter.bin: src/compliance_reporter.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o compliance_reporter.bin src/compliance_reporter.asm

forensic_integrator.bin: src/forensic_integrator.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o forensic_integrator.bin src/forensic_integrator.asm

malware_analyzer.bin: src/malware_analyzer.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o malware_analyzer.bin src/malware_analyzer.asm

user_behavior_analytics.bin: src/user_behavior_analytics.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o user_behavior_analytics.bin src/user_behavior_analytics.asm

decoy_manager.bin: src/decoy_manager.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o decoy_manager.bin src/decoy_manager.asm

threat_hunting_integration.bin: src/threat_hunting_integration.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o threat_hunting_integration.bin src/threat_hunting_integration.asm

incident_timeline_builder.bin: src/incident_timeline_builder.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o incident_timeline_builder.bin src/incident_timeline_builder.asm

playbook_tester.bin: src/playbook_tester.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o playbook_tester.bin src/playbook_tester.asm

asset_criticality_scorer.bin: src/asset_criticality_scorer.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o asset_criticality_scorer.bin src/asset_criticality_scorer.asm

test_soar.bin: tests/test_soar.asm include/soar.inc
	$(ASM) $(ASMFLAGS) -o test_soar.bin tests/test_soar.asm

test: all
	@echo "[soar] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Security Orchestration, Automation & Response Build Targets:"
	@echo "  all      - Assemble all 27 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"
