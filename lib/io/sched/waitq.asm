; =============================================================================
; lib/io/sched/waitq.asm
; Wait queue initialization scheduler interface stub.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_SCHED_WAITQ_ASM
%define IO_SCHED_WAITQ_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

section .text

; =============================================================================
; sched_waitq_init — Initialize a wait queue list structure (Phase 1 bring-up stub)
; In : RDI = -> waitq structure to initialize
; Out: None
; =============================================================================
IO_FUNC sched_waitq_init
    guard_null rdi
    
    ; Stub: simple zero initialization of list pointers
    mov     qword [rdi], 0
    mov     qword [rdi + 8], 0
IO_ENDFUNC sched_waitq_init

%endif ; IO_SCHED_WAITQ_ASM
