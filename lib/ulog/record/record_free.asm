; =============================================================================
; Tattva OS — lib/ulog/record/record_free.asm
; =============================================================================
; Returns a record_pool_alloc'd slot after every sink in drain/dispatch.asm's
; fan-out has finished with it (or given up — dispatch_retry.asm still frees
; on final failure; a leaked slot is worse than a lost log line).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_FREE_ASM
%define LIB_ULOG_RECORD_RECORD_FREE_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .text

; -----------------------------------------------------------------------------
; record_free — return a log_record_t* to the pool freelist
; Input:  RDI = log_record_t* (must have come from record_pool_alloc)
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
global record_free
record_free:
    push rax
    push rcx
    push rdx
    push rdi

    mov rax, [ulog_pool + ulog_pool_t.slots]
    sub rdi, rax
    mov rax, rdi
    xor rdx, rdx
    mov rcx, LOG_RECORD_SIZE
    div rcx                          ; RAX = slot index

    inc qword [ulog_pool + ulog_pool_t.free_top]
    mov rdx, [ulog_pool + ulog_pool_t.free_top]
    mov rcx, [ulog_pool + ulog_pool_t.free_stack]
    mov [rcx + rdx * 8], rax

    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

%endif ; LIB_ULOG_RECORD_RECORD_FREE_ASM
