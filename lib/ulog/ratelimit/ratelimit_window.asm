; =============================================================================
; Tattva OS — lib/ulog/ratelimit/ratelimit_window.asm
; =============================================================================
; Fixed-window bookkeeping per bucket. Stores enough of the original
; (module_id, msg_ptr) to detect a bucket collision — two different call
; sites hashing to the same bucket — and treats a collision as "start a
; fresh window for the new signature" rather than corrupting the older
; signature's count.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RATELIMIT_RATELIMIT_WINDOW_ASM
%define LIB_ULOG_RATELIMIT_RATELIMIT_WINDOW_ASM

[BITS 64]

%include "lib/ulog/ratelimit/ratelimit_hash.asm"
%include "lib/ulog/config/defaults.inc"

struc ratelimit_bucket_t
    .window_start_ns   resq 1
    .count              resq 1
    .sig_module          resq 1
    .sig_msg               resq 1
endstruc

section .bss
alignb 8
global ulog_ratelimit_buckets
ulog_ratelimit_buckets: resb (ratelimit_bucket_t_size * RATELIMIT_BUCKETS)

section .text

; -----------------------------------------------------------------------------
; ratelimit_window_check — admit or suppress, updating window state
; Input:  RDI = module_id, RSI = msg_ptr, RDX = now_ns
; Output: RAX = 1 admit, 0 suppress
; -----------------------------------------------------------------------------
global ratelimit_window_check
ratelimit_window_check:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi                     ; module_id
    mov r13, rsi                      ; msg_ptr
    mov r14, rdx                       ; now_ns

    call ratelimit_hash               ; RDI/RSI already hold module_id/msg_ptr
    mov rbx, ratelimit_bucket_t_size
    imul rbx, rax
    add rbx, ulog_ratelimit_buckets  ; RBX = &bucket

    cmp [rbx + ratelimit_bucket_t.sig_module], r12
    jne .fresh
    cmp [rbx + ratelimit_bucket_t.sig_msg], r13
    jne .fresh

    mov rax, r14
    sub rax, [rbx + ratelimit_bucket_t.window_start_ns]
    cmp rax, ULOG_RATELIMIT_WINDOW_NANOS
    jae .fresh

    mov rax, [rbx + ratelimit_bucket_t.count]
    cmp rax, ULOG_RATELIMIT_MAX_PER_WINDOW
    jae .suppress

    inc qword [rbx + ratelimit_bucket_t.count]
    mov rax, 1
    jmp .done

.fresh:
    mov [rbx + ratelimit_bucket_t.sig_module], r12
    mov [rbx + ratelimit_bucket_t.sig_msg], r13
    mov [rbx + ratelimit_bucket_t.window_start_ns], r14
    mov qword [rbx + ratelimit_bucket_t.count], 1
    mov rax, 1
    jmp .done

.suppress:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_RATELIMIT_RATELIMIT_WINDOW_ASM
