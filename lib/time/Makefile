# =============================================================================
# lib/time/Makefile
# Makefile for Time Library in Tattva OS
# =============================================================================

ASM = nasm
ASMFLAGS = -f elf64 -i ../../

TARGET = time.o
SRC = time.asm

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC) time.inc tsc.asm rtc.asm mono.asm delay.asm
	$(ASM) $(ASMFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
