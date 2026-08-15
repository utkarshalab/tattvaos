; =============================================================================
; Tattva OS — lib/ulog/drain/backpressure_drop_oldest.asm
; =============================================================================
; One of three named overflow strategies for when record_pool.asm is
; exhausted mid-collection. This one sacrifices history for recency: free
; the oldest record still waiting in the current batch to make room for
; fresher data coming off the rings.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_BACKPRESSURE_DROP_OLDEST_ASM
%define LIB_ULOG_DRAIN_BACKPRESSURE_DROP_OLDEST_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; backpressure_apply_drop_oldest — Output: RAX = 1 if a slot was freed (the
; caller should retry record_pool_alloc), 0 if there was nothing to drop
; -----------------------------------------------------------------------------
global backpressure_apply_drop_oldest
backpressure_apply_drop_oldest:
    push rbx
    push rcx
    push rdx

    mov eax, [ulog_batch_count]
    test eax, eax
    jz .none

    mov rdi, [ulog_batch_ptrs]       ; oldest = index 0
    push rax
    call record_free
    pop rax

    ; shift the remaining pointers down by one
    dec eax
    xor ecx, ecx
.shift:
    cmp ecx, eax
    jae .shift_done
    mov rbx, [ulog_batch_ptrs + rcx * 8 + 8]
    mov [ulog_batch_ptrs + rcx * 8], rbx
    inc ecx
    jmp .shift

.shift_done:
    mov [ulog_batch_count], eax
    mov rax, 1
    jmp .done

.none:
    xor rax, rax

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

%endif ; LIB_ULOG_DRAIN_BACKPRESSURE_DROP_OLDEST_ASM
