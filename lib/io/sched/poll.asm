; =============================================================================
; lib/io/sched/poll.asm
; Thread yielding scheduler interface stub.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_SCHED_POLL_ASM
%define IO_SCHED_POLL_ASM

%include "lib/io/macro/func.asm"

section .text

; =============================================================================
; sched_yield — Yield execution time to scheduler (Phase 1 bring-up stub)
; In : None
; Out: None
; =============================================================================
IO_FUNC sched_yield
    ; Stub: processor execution yield hint
    pause
IO_ENDFUNC sched_yield

%endif ; IO_SCHED_POLL_ASM
