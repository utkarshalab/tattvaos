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

$(TARGET): $(SRC) io.inc error/codes.asm macro/func.asm macro/guard.asm arch/x86_64/portio.asm core/percpu.asm core/fd.asm core/handle.asm intr/idt.asm intr/isr.asm intr/exception.asm intr/pic.asm intr/lapic.asm intr/ioapic.asm intr/spurious.asm intr/vector.asm pci/config.asm pci/match.asm pci/bar.asm pci/caps.asm pci/enum.asm dma/alloc.asm dma/map.asm dma/sg.asm dma/sync.asm dma/barrier.asm char/serial.asm char/console.asm
	$(ASM) $(ASMFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

.PHONY: all clean
