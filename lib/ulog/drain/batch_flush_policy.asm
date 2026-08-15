; =============================================================================
; Tattva OS — lib/ulog/drain/batch_flush_policy.asm
; =============================================================================
; When to stop collecting and hand the batch to dispatch.asm: N records OR
; T nanoseconds since the batch started, whichever comes first — the same
; two-condition flush every real batching system uses, so a quiet system
; still ships its one log line promptly instead of waiting for a full batch
; that may never come.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_BATCH_FLUSH_POLICY_ASM
%define LIB_ULOG_DRAIN_BATCH_FLUSH_POLICY_ASM

[BITS 64]

%include "lib/ulog/config/defaults.inc"

section .bss
alignb 8
global ulog_batch_start_ns
ulog_batch_start_ns: resq 1

section .text

; -----------------------------------------------------------------------------
; batch_flush_policy_start — mark "batch collection began now"
; -----------------------------------------------------------------------------
global batch_flush_policy_start
batch_flush_policy_start:
    push rax
    call mono_get_nanos
    mov [ulog_batch_start_ns], rax
    pop rax
    ret

; -----------------------------------------------------------------------------
; batch_flush_policy_should_flush — Output: RAX = 1 if the batch should flush
; -----------------------------------------------------------------------------
global batch_flush_policy_should_flush
batch_flush_policy_should_flush:
    push rdx

    mov eax, [ulog_batch_count]
    cmp eax, ULOG_BATCH_MAX_RECORDS
    jae .yes

    test eax, eax
    jz .no                           ; nothing collected yet — nothing to flush

    call mono_get_nanos
    sub rax, [ulog_batch_start_ns]
    cmp rax, ULOG_BATCH_MAX_NANOS
    jae .yes

.no:
    xor eax, eax
    jmp .done

.yes:
    mov eax, 1

.done:
    pop rdx
    ret

%endif ; LIB_ULOG_DRAIN_BATCH_FLUSH_POLICY_ASM
