# =============================================================================
# lib/time/Makefile
# Makefile for Time Library in Utkarsha OS
# =============================================================================

ASM = nasm
ASMFLAGS = -f elf64 -i ../../

TARGET = time.o
SRC = time.asm

# time.asm calls into tsc, mono and rtc. The kernel includes all four as one
# unit (kernel/entry.asm); pre-include them here in the same order so the
# standalone object resolves the same symbols.
PREINCLUDE = -p lib/time/tsc.asm -p lib/time/mono.asm -p lib/time/rtc.asm

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC) time.inc tsc.asm rtc.asm mono.asm delay.asm
	$(ASM) $(ASMFLAGS) $(PREINCLUDE) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
