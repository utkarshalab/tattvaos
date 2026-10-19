# security/waf — build & test

MODULE := waf
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test help

COMPONENTS := \
	waf.bin \
	core.bin \
	rule.bin \
	http.bin \
	sqli.bin \
	xss.bin \
	csrf.bin \
	fim.bin \
	cmd.bin \
	deser.bin \
	api.bin \
	rate.bin \
	bot.bin \
	session.bin \
	geoip.bin \
	rulec.bin \
	siem.bin \
	stats.bin \
	test_waf.bin

all: $(COMPONENTS)

waf.bin: src/waf.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o waf.bin src/waf.asm

core.bin: src/waf_core.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o core.bin src/waf_core.asm

rule.bin: src/waf_rule.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o rule.bin src/waf_rule.asm

http.bin: src/waf_http.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o http.bin src/waf_http.asm

sqli.bin: src/waf_sqli.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o sqli.bin src/waf_sqli.asm

xss.bin: src/waf_xss.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o xss.bin src/waf_xss.asm

csrf.bin: src/waf_csrf.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o csrf.bin src/waf_csrf.asm

fim.bin: src/waf_fim.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o fim.bin src/waf_fim.asm

cmd.bin: src/waf_cmd.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o cmd.bin src/waf_cmd.asm

deser.bin: src/waf_deser.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o deser.bin src/waf_deser.asm

api.bin: src/waf_api.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o api.bin src/waf_api.asm

rate.bin: src/waf_rate.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o rate.bin src/waf_rate.asm

bot.bin: src/waf_bot.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o bot.bin src/waf_bot.asm

session.bin: src/waf_session.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o session.bin src/waf_session.asm

geoip.bin: src/waf_geoip.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o geoip.bin src/waf_geoip.asm

rulec.bin: src/waf_rulec.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o rulec.bin src/waf_rulec.asm

siem.bin: src/waf_siem.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o siem.bin src/waf_siem.asm

stats.bin: src/waf_stats.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o stats.bin src/waf_stats.asm

test_waf.bin: tests/test_waf.asm include/waf.inc
	$(ASM) $(ASMFLAGS) -o test_waf.bin tests/test_waf.asm

test: all
	@echo "[waf] running premium skeleton tests"
	@./tests/run.sh

clean:
	rm -f $(COMPONENTS)

help:
	@echo "Web Application Firewall Build Targets:"
	@echo "  all      - Assemble all 18 components + test binary"
	@echo "  test     - Build and run skeleton tests"
	@echo "  clean    - Remove all .bin files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Components: $(COMPONENTS)"
