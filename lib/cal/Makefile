# =============================================================================
# lib/cal/Makefile
# Makefile for Calendar Library in Tattva OS
# =============================================================================

ASM = nasm
ASMFLAGS = -f elf64 -i ../../

TARGET = cal.o
SRC = cal.asm

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC) cal.inc gregorian.asm unix.asm iso8601.asm
	$(ASM) $(ASMFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
