# security/ips — build & test

MODULE := ips
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	ips.bin \
	inspector.bin \
	enforcer.bin \
	policy.bin \
	bypass.bin \
	rate_limiter.bin \
	connection_tracker.bin \
	quarantine.bin \
	blocklist.bin \
	siem.bin \
	stats.bin \
	geoip.bin \
	app_control.bin \
	tls_inspector.bin \
	dns_filter.bin \
	file_analysis.bin \
	url_filter.bin \
	bot_detector.bin \
	ddos_protector.bin \
	threat_feed.bin \
	waf_engine.bin \
	packet_capture.bin \
	ha_cluster.bin \
	api_protection.bin \
	ml_anomaly.bin \
	deep_packet_inspector.bin \
	protocol_normalizer.bin \
	stream_reassembler.bin \
	payload_inspector.bin \
	connection_terminator.bin \
	packet_injector.bin \
	traffic_shaper.bin \
	load_balancer_integration.bin \
	ssl_termination.bin \
	quarantine_manager.bin \
	honeypot_redirector.bin \
	slowloris_mitigator.bin \
	syn_flood_mitigator.bin \
	udp_flood_mitigator.bin \
	http_flood_mitigator.bin \
	dns_amplification_mitigator.bin \
	ntp_amplification_mitigator.bin \
	memcached_amplification_mitigator.bin \
	test_ips.bin

all: $(COMPONENTS)

ips.bin: src/ips.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o ips.bin src/ips.asm

inspector.bin: src/inspector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o inspector.bin src/inspector.asm

enforcer.bin: src/enforcer.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o enforcer.bin src/enforcer.asm

policy.bin: src/policy.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o policy.bin src/policy.asm

bypass.bin: src/bypass.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o bypass.bin src/bypass.asm

rate_limiter.bin: src/rate_limiter.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o rate_limiter.bin src/rate_limiter.asm

connection_tracker.bin: src/connection_tracker.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o connection_tracker.bin src/connection_tracker.asm

quarantine.bin: src/quarantine.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o quarantine.bin src/quarantine.asm

blocklist.bin: src/blocklist.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o blocklist.bin src/blocklist.asm

siem.bin: src/siem.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o siem.bin src/siem.asm

stats.bin: src/stats.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o stats.bin src/stats.asm

geoip.bin: src/geoip.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o geoip.bin src/geoip.asm

app_control.bin: src/app_control.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o app_control.bin src/app_control.asm

tls_inspector.bin: src/tls_inspector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o tls_inspector.bin src/tls_inspector.asm

dns_filter.bin: src/dns_filter.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o dns_filter.bin src/dns_filter.asm

file_analysis.bin: src/file_analysis.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o file_analysis.bin src/file_analysis.asm

url_filter.bin: src/url_filter.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o url_filter.bin src/url_filter.asm

bot_detector.bin: src/bot_detector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o bot_detector.bin src/bot_detector.asm

ddos_protector.bin: src/ddos_protector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o ddos_protector.bin src/ddos_protector.asm

threat_feed.bin: src/threat_feed.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o threat_feed.bin src/threat_feed.asm

waf_engine.bin: src/waf_engine.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o waf_engine.bin src/waf_engine.asm

packet_capture.bin: src/packet_capture.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o packet_capture.bin src/packet_capture.asm

ha_cluster.bin: src/ha_cluster.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o ha_cluster.bin src/ha_cluster.asm

api_protection.bin: src/api_protection.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o api_protection.bin src/api_protection.asm

ml_anomaly.bin: src/ml_anomaly.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o ml_anomaly.bin src/ml_anomaly.asm

deep_packet_inspector.bin: src/deep_packet_inspector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o deep_packet_inspector.bin src/deep_packet_inspector.asm

protocol_normalizer.bin: src/protocol_normalizer.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o protocol_normalizer.bin src/protocol_normalizer.asm

stream_reassembler.bin: src/stream_reassembler.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o stream_reassembler.bin src/stream_reassembler.asm

payload_inspector.bin: src/payload_inspector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o payload_inspector.bin src/payload_inspector.asm

connection_terminator.bin: src/connection_terminator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o connection_terminator.bin src/connection_terminator.asm

packet_injector.bin: src/packet_injector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o packet_injector.bin src/packet_injector.asm

traffic_shaper.bin: src/traffic_shaper.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o traffic_shaper.bin src/traffic_shaper.asm

load_balancer_integration.bin: src/load_balancer_integration.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o load_balancer_integration.bin src/load_balancer_integration.asm

ssl_termination.bin: src/ssl_termination.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o ssl_termination.bin src/ssl_termination.asm

quarantine_manager.bin: src/quarantine_manager.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o quarantine_manager.bin src/quarantine_manager.asm

honeypot_redirector.bin: src/honeypot_redirector.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o honeypot_redirector.bin src/honeypot_redirector.asm

slowloris_mitigator.bin: src/slowloris_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o slowloris_mitigator.bin src/slowloris_mitigator.asm

syn_flood_mitigator.bin: src/syn_flood_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o syn_flood_mitigator.bin src/syn_flood_mitigator.asm

udp_flood_mitigator.bin: src/udp_flood_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o udp_flood_mitigator.bin src/udp_flood_mitigator.asm

http_flood_mitigator.bin: src/http_flood_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o http_flood_mitigator.bin src/http_flood_mitigator.asm

dns_amplification_mitigator.bin: src/dns_amplification_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o dns_amplification_mitigator.bin src/dns_amplification_mitigator.asm

ntp_amplification_mitigator.bin: src/ntp_amplification_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o ntp_amplification_mitigator.bin src/ntp_amplification_mitigator.asm

memcached_amplification_mitigator.bin: src/memcached_amplification_mitigator.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o memcached_amplification_mitigator.bin src/memcached_amplification_mitigator.asm

test_ips.bin: tests/test_ips.asm include/ips.inc
	$(ASM) $(ASMFLAGS) -o test_ips.bin tests/test_ips.asm

test: all
	@echo "[ips] running premium enterprise test suite"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Intrusion Prevention System Build Targets:"
	@echo "  all      - Assemble all 42 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"
