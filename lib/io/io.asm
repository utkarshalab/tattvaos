; =============================================================================
; lib/io/io.asm
; Top-level include entry wrapper for Tattva OS I/O Subsystem (lib/io).
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef LIB_IO_IO_ASM
%define LIB_IO_IO_ASM

[BITS 64]

; Shared structures and constants
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; Subsystem macros
%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

; Architectural abstraction (x86_64)
%include "lib/io/arch/x86_64/portio.asm"

; Bootloader interface
%include "lib/io/boot/handoff.asm"

; ACPI Table walk and scanners
%include "lib/io/acpi/acpi.asm"
%include "lib/io/acpi/mcfg.asm"
%include "lib/io/acpi/madt.asm"
%include "lib/io/acpi/fadt.asm"

; Core descriptor tables and per-CPU state
%include "lib/io/core/init.asm"
%include "lib/io/core/percpu.asm"
%include "lib/io/core/fd.asm"
%include "lib/io/core/handle.asm"
%include "lib/io/core/iovec.asm"
%include "lib/io/core/bounce.asm"

; Character devices (Serial and Console)
%include "lib/io/char/serial.asm"
%include "lib/io/char/console.asm"

; Subsystem Errors Conversion
%include "lib/io/error/strerror.asm"

; Interrupt infrastructure
%include "lib/io/intr/idt.asm"
%include "lib/io/intr/isr.asm"
%include "lib/io/intr/exception.asm"
%include "lib/io/intr/pic.asm"
%include "lib/io/intr/lapic.asm"
%include "lib/io/intr/ioapic.asm"
%include "lib/io/intr/spurious.asm"
%include "lib/io/intr/vector.asm"

; PCI/PCIe bus configuration
%include "lib/io/pci/config.asm"
%include "lib/io/pci/config_ecam.asm"
%include "lib/io/pci/match.asm"
%include "lib/io/pci/bar.asm"
%include "lib/io/pci/caps.asm"
%include "lib/io/pci/enum.asm"

; Direct Memory Access (DMA)
%include "lib/io/dma/alloc.asm"
%include "lib/io/dma/map.asm"
%include "lib/io/dma/sg.asm"
%include "lib/io/dma/sync.asm"
%include "lib/io/dma/barrier.asm"

; Block devices
%include "lib/io/block/bdev.asm"
%include "lib/io/block/ata_pio.asm"
%include "lib/io/block/virtio_blk.asm"
%include "lib/io/block/gpt.asm"

; Async execution rings and request management
%include "lib/io/async/submit.asm"
%include "lib/io/async/complete.asm"
%include "lib/io/async/request.asm"
%include "lib/io/async/timeout.asm"

; Scheduler interfacing
%include "lib/io/sched/wake.asm"
%include "lib/io/sched/wait.asm"
%include "lib/io/sched/waitq.asm"
%include "lib/io/sched/poll.asm"

%endif ; LIB_IO_IO_ASM
