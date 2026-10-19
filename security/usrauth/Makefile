# security/usrauth — build & test

MODULE := usrauth
ASM    := nasm
ASMFLAGS := -f bin

.PHONY: all clean test subdirs

SUBDIRS := audit capability identity mandatory policy subject token tests

all: usrauth.bin

usrauth.bin: src/usrauth.asm include/usrauth.inc
	$(ASM) $(ASMFLAGS) -o usrauth.bin src/usrauth.asm

test: usrauth.bin
	@echo "[usrauth] running skeleton tests"
	@./tests/run.sh

subdirs:
	@for d in $(SUBDIRS); do $(MAKE) -C $$d test || exit 1; done

clean:
	rm -f usrauth.bin
