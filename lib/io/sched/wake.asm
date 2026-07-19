; =============================================================================
; lib/io/sched/wake.asm
; Thread wake up scheduler interface stub.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_SCHED_WAKE_ASM
%define IO_SCHED_WAKE_ASM

%include "lib/io/macro/func.asm"

section .text

; =============================================================================
; sched_wakeup — Wake up a blocked task/thread (Phase 1 bring-up stub)
; In : RDI = -> waitq entry / task structure to wake up
; Out: None
; =============================================================================
IO_FUNC sched_wakeup
    ; Stub: returns immediately (polling handles completions during early bring-up)
IO_ENDFUNC sched_wakeup

%endif ; IO_SCHED_WAKE_ASM
