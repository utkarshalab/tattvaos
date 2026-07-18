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

; Core descriptor tables and per-CPU state
%include "lib/io/core/percpu.asm"
%include "lib/io/core/fd.asm"
%include "lib/io/core/handle.asm"

; Character devices (Serial and Console)
%include "lib/io/char/serial.asm"
%include "lib/io/char/console.asm"

%endif ; LIB_IO_IO_ASM
