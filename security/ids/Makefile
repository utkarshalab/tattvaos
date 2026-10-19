# security/ids — build & test

MODULE := ids
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	ids.bin \
	sensor.bin \
	reassembler.bin \
	analyzer.bin \
	rules.bin \
	detector.bin \
	alert.bin \
	correlator.bin \
	siem.bin \
	stats.bin \
	anomaly_detector.bin \
	flow_analyzer.bin \
	packet_inspector.bin \
	signature_compiler.bin \
	anomaly_baseline.bin \
	encrypted_traffic_analyzer.bin \
	scada_protocol_detector.bin \
	dns_tunnel_detector.bin \
	lateral_movement_detector.bin \
	data_exfiltration_detector.bin \
	credential_stuffing_detector.bin \
	brute_force_detector.bin \
	port_scan_detector.bin \
	os_fingerprinter.bin \
	application_identifier.bin \
	ssl_tls_analyzer.bin \
	file_carver.bin \
	test_ids.bin

all: $(COMPONENTS)

ids.bin: src/ids.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o ids.bin src/ids.asm

sensor.bin: src/sensor.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o sensor.bin src/sensor.asm

reassembler.bin: src/reassembler.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o reassembler.bin src/reassembler.asm

analyzer.bin: src/analyzer.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o analyzer.bin src/analyzer.asm

rules.bin: src/rules.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o rules.bin src/rules.asm

detector.bin: src/detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o detector.bin src/detector.asm

alert.bin: src/alert.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o alert.bin src/alert.asm

correlator.bin: src/correlator.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o correlator.bin src/correlator.asm

siem.bin: src/siem.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o siem.bin src/siem.asm

stats.bin: src/stats.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o stats.bin src/stats.asm

anomaly_detector.bin: src/anomaly_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o anomaly_detector.bin src/anomaly_detector.asm

flow_analyzer.bin: src/flow_analyzer.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o flow_analyzer.bin src/flow_analyzer.asm

packet_inspector.bin: src/packet_inspector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o packet_inspector.bin src/packet_inspector.asm

signature_compiler.bin: src/signature_compiler.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o signature_compiler.bin src/signature_compiler.asm

anomaly_baseline.bin: src/anomaly_baseline.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o anomaly_baseline.bin src/anomaly_baseline.asm

encrypted_traffic_analyzer.bin: src/encrypted_traffic_analyzer.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o encrypted_traffic_analyzer.bin src/encrypted_traffic_analyzer.asm

scada_protocol_detector.bin: src/scada_protocol_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o scada_protocol_detector.bin src/scada_protocol_detector.asm

dns_tunnel_detector.bin: src/dns_tunnel_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o dns_tunnel_detector.bin src/dns_tunnel_detector.asm

lateral_movement_detector.bin: src/lateral_movement_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o lateral_movement_detector.bin src/lateral_movement_detector.asm

data_exfiltration_detector.bin: src/data_exfiltration_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o data_exfiltration_detector.bin src/data_exfiltration_detector.asm

credential_stuffing_detector.bin: src/credential_stuffing_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o credential_stuffing_detector.bin src/credential_stuffing_detector.asm

brute_force_detector.bin: src/brute_force_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o brute_force_detector.bin src/brute_force_detector.asm

port_scan_detector.bin: src/port_scan_detector.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o port_scan_detector.bin src/port_scan_detector.asm

os_fingerprinter.bin: src/os_fingerprinter.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o os_fingerprinter.bin src/os_fingerprinter.asm

application_identifier.bin: src/application_identifier.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o application_identifier.bin src/application_identifier.asm

ssl_tls_analyzer.bin: src/ssl_tls_analyzer.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o ssl_tls_analyzer.bin src/ssl_tls_analyzer.asm

file_carver.bin: src/file_carver.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o file_carver.bin src/file_carver.asm

test_ids.bin: tests/test_ids.asm include/ids.inc
	$(ASM) $(ASMFLAGS) -o test_ids.bin tests/test_ids.asm

test: all
	@echo "[ids] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Intrusion Detection System Build Targets:"
	@echo "  all      - Assemble all 27 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"
