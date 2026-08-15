; =============================================================================
; Tattva OS — lib/ulog/drain/batch.asm
; =============================================================================
; Collects records out of the per-CPU rings into record_pool-backed staging
; slots, up to ULOG_BATCH_MAX_RECORDS. Owns the choice of backpressure
; strategy when the pool runs out mid-collection — configurable per
; deployment via backpressure_set_policy, defaulting to drop-newest (protect
; whatever's already safely staged over whatever's still arriving).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_BATCH_ASM
%define LIB_ULOG_DRAIN_BATCH_ASM

[BITS 64]

%include "lib/ulog/config/defaults.inc"

%define BACKPRESSURE_DROP_OLDEST  0
%define BACKPRESSURE_DROP_NEWEST  1
%define BACKPRESSURE_BLOCK        2

section .bss
alignb 8
global ulog_batch_ptrs
ulog_batch_ptrs: resq ULOG_BATCH_MAX_RECORDS
global ulog_batch_count
ulog_batch_count: resd 1
global ulog_backpressure_policy
ulog_backpressure_policy: resd 1

section .text

; -----------------------------------------------------------------------------
; batch_reset
; -----------------------------------------------------------------------------
global batch_reset
batch_reset:
    mov dword [ulog_batch_count], 0
    mov dword [ulog_backpressure_policy], BACKPRESSURE_DROP_NEWEST
    ret

; -----------------------------------------------------------------------------
; backpressure_set_policy — Input: EDI = BACKPRESSURE_*
; -----------------------------------------------------------------------------
global backpressure_set_policy
backpressure_set_policy:
    mov [ulog_backpressure_policy], edi
    ret

; -----------------------------------------------------------------------------
; batch_collect_from_ring — pop as much as fits from one ring into the batch
; Input:  RDI = ring_t*
; Output: RAX = records added this call
; -----------------------------------------------------------------------------
global batch_collect_from_ring
batch_collect_from_ring:
    push rbx
    push r12
    push r13

    mov rbx, rdi                     ; ring
    xor r13, r13                       ; added this call

.loop:
    mov eax, [ulog_batch_count]
    cmp eax, ULOG_BATCH_MAX_RECORDS
    jae .done

    call record_pool_alloc
    test rax, rax
    jnz .have_slot

    ; pool exhausted — apply the configured strategy
    mov eax, [ulog_backpressure_policy]
    cmp eax, BACKPRESSURE_DROP_OLDEST
    jne .try_alloc_again_check
    call backpressure_apply_drop_oldest
    jmp .after_strategy
.try_alloc_again_check:
    cmp eax, BACKPRESSURE_DROP_NEWEST
    jne .strategy_block
    call backpressure_apply_drop_newest
    jmp .after_strategy
.strategy_block:
    call backpressure_apply_block
.after_strategy:
    test rax, rax
    jz .done                         ; strategy declined to free anything: stop this pass
    call record_pool_alloc
    test rax, rax
    jz .done

.have_slot:
    mov r12, rax                     ; pool slot

    mov rdi, rbx
    mov rsi, r12
    call log_ring_pop
    test rax, rax
    jz .return_slot                  ; ring is empty

    movsxd rax, dword [ulog_batch_count]
    mov [ulog_batch_ptrs + rax * 8], r12
    inc dword [ulog_batch_count]
    inc r13
    jmp .loop

.return_slot:
    mov rdi, r12
    call record_free

.done:
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_DRAIN_BATCH_ASM
