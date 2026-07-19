; =============================================================================
; lib/io/sched/wait.asm
; Thread wait/block scheduler interface stub.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_SCHED_WAIT_ASM
%define IO_SCHED_WAIT_ASM

%include "lib/io/macro/func.asm"

section .text

; =============================================================================
; sched_wait — Yield/block current task on a wait queue (Phase 1 bring-up stub)
; In : RDI = -> waitq entry to block on
; Out: None
; =============================================================================
IO_FUNC sched_wait
    ; Stub: execute processor pause
    pause
IO_ENDFUNC sched_wait

%endif ; IO_SCHED_WAIT_ASM
