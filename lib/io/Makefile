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

$(TARGET): $(SRC) io.inc error/codes.asm error/strerror.asm \
            const/apic.asm const/uart.asm const/pci.asm const/virtio.asm \
            macro/func.asm macro/guard.asm arch/x86_64/portio.asm arch/x86_64/barrier.asm arch/x86_64/cache.asm \
            boot/handoff.asm acpi/acpi.asm acpi/mcfg.asm acpi/madt.asm acpi/fadt.asm \
            core/init.asm core/percpu.asm core/fd.asm core/handle.asm core/iovec.asm core/bounce.asm core/buffer.asm core/fixed_buf.asm core/align.asm \
            char/serial.asm char/console.asm \
            intr/idt.asm intr/isr.asm intr/exception.asm intr/pic.asm intr/lapic.asm intr/ioapic.asm intr/spurious.asm intr/vector.asm \
            pci/config.asm pci/config_ecam.asm pci/match.asm pci/bar.asm pci/caps.asm pci/enum.asm \
            dma/alloc.asm dma/map.asm dma/sg.asm dma/sync.asm dma/barrier.asm \
            block/bdev.asm block/ata_pio.asm block/virtio_blk.asm block/gpt.asm block/merge.asm block/readahead.asm \
            async/submit.asm async/complete.asm async/request.asm async/timeout.asm async/batch.asm \
            sched/wake.asm sched/wait.asm sched/waitq.asm sched/poll.asm
	$(ASM) $(ASMFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

.PHONY: all clean
