; =============================================================================
; Tattva OS — lib/ulog/record/record_pool.asm
; =============================================================================
; Stable staging memory for in-flight batches. drain/batch.asm copies records
; out of a per-CPU ring (which the producer may overwrite the instant its
; tail advances) into a pool slot that stays valid for as long as a sink
; write is in flight. Touched only by the drain fiber — one owner, so the
; freelist stack below needs no CAS despite backing a "shared" resource.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_POOL_ASM
%define LIB_ULOG_RECORD_RECORD_POOL_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .bss
alignb 8
global ulog_pool
ulog_pool: resb ulog_pool_t_size

section .text

; -----------------------------------------------------------------------------
; record_pool_init — allocate backing storage and fill the freelist
; Input:  none
; Output: RAX = 1 ok, 0 on allocation failure
; -----------------------------------------------------------------------------
global record_pool_init
record_pool_init:
    push rbx
    push rcx

    mov rdi, LOG_RECORD_SIZE * ULOG_POOL_RECORDS
    call heap_alloc
    test rax, rax
    jz .fail
    mov [ulog_pool + ulog_pool_t.slots], rax

    mov rdi, 8 * ULOG_POOL_RECORDS
    call heap_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov [ulog_pool + ulog_pool_t.free_stack], rax

    xor rcx, rcx
.fill_loop:
    cmp rcx, ULOG_POOL_RECORDS
    jae .fill_done
    mov [rbx + rcx * 8], rcx
    inc rcx
    jmp .fill_loop

.fill_done:
    mov qword [ulog_pool + ulog_pool_t.free_top], ULOG_POOL_RECORDS - 1
    mov qword [ulog_pool + ulog_pool_t.exhausted_count], 0
    mov rax, 1
    jmp .done

.fail:
    xor rax, rax

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; record_pool_alloc — pop a free slot
; Input:  none
; Output: RAX = log_record_t* (0 if the pool is exhausted)
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global record_pool_alloc
record_pool_alloc:
    push rbx

    mov rcx, [ulog_pool + ulog_pool_t.free_top]
    cmp rcx, 0
    jl .exhausted                    ; signed compare: -1 means empty

    mov rdx, [ulog_pool + ulog_pool_t.free_stack]
    mov rbx, [rdx + rcx * 8]         ; RBX = slot index
    dec qword [ulog_pool + ulog_pool_t.free_top]

    mov rax, LOG_RECORD_SIZE
    imul rax, rbx
    add rax, [ulog_pool + ulog_pool_t.slots]
    jmp .done

.exhausted:
    inc qword [ulog_pool + ulog_pool_t.exhausted_count]
    xor rax, rax

.done:
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RECORD_POOL_ASM
