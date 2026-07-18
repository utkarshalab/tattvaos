# =============================================================================
# lib/io/Makefile
# Makefile to verify and build the lib/io subsystem module.
#
# Part of Utkarsha Labs / Tattva OS
# =============================================================================

ASM = nasm
ASMFLAGS = -f elf64 -i ../../

TARGET = io.o
SRC = io.asm

all: $(TARGET)

$(TARGET): $(SRC) io.inc error/codes.asm macro/func.asm macro/guard.asm arch/x86_64/portio.asm char/serial.asm char/console.asm
	$(ASM) $(ASMFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

.PHONY: all clean
