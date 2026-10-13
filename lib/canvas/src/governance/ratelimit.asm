; ============================================================================
; Rate Limit — Token-Bucket Message and Byte Rate Limiting
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define RateLimit_size    64

section .text

struc RateLimit
    .max_msg_sec:    resq 1
    .msg_tokens:     resq 1
    .msg_last:       resq 1
    .max_bytes_sec:  resq 1
    .byte_tokens:    resq 1
    .byte_last:      resq 1
    .throttled:      resb 1
    .violations:     resd 1
    .client:         resq 1
endstruc

; ---------------------------------------------------------------------------
; ratelimit_init
; ---------------------------------------------------------------------------
global ratelimit_init
ratelimit_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov qword [rbx + Server.ratelimits], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; ratelimit_create
; ---------------------------------------------------------------------------
global ratelimit_create
ratelimit_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    mov rdi, [rbx + Server.arena]
    mov rsi, RateLimit_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rax, [r13 + TrustProfile.rate_msg_sec]
    mov [rbx + RateLimit.max_msg_sec], rax
    mov [rbx + RateLimit.msg_tokens], rax
    mov rax, [r13 + TrustProfile.rate_bytes_sec]
    mov [rbx + RateLimit.max_bytes_sec], rax
    mov [rbx + RateLimit.byte_tokens], rax
    call tv_time_now_ns
    mov [rbx + RateLimit.msg_last], rax
    mov [rbx + RateLimit.byte_last], rax
    mov byte [rbx + RateLimit.throttled], 0
    mov dword [rbx + RateLimit.violations], 0
    mov qword [rbx + RateLimit.client], r12
    mov qword [r12 + Client.ratelimit], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; ratelimit_refill
; ---------------------------------------------------------------------------
ratelimit_refill:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    call tv_time_now_ns
    mov rcx, rax
    ; msg bucket
    mov rax, [rbx + RateLimit.max_msg_sec]
    test rax, rax
    jz .bytes
    mov rdx, rcx
    sub rdx, [rbx + RateLimit.msg_last]
    cmp rdx, 1000000000
    jb .bytes
    ; one second or more elapsed: full refill
    mov [rbx + RateLimit.msg_tokens], rax
    mov [rbx + RateLimit.msg_last], rcx
.bytes:
    mov rax, [rbx + RateLimit.max_bytes_sec]
    test rax, rax
    jz .done
    mov rdx, rcx
    sub rdx, [rbx + RateLimit.byte_last]
    cmp rdx, 1000000000
    jb .done
    mov [rbx + RateLimit.byte_tokens], rax
    mov [rbx + RateLimit.byte_last], rcx
.done:
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; ratelimit_check_msg
;   IN: rdi = ratelimit*, rsi = byte_count
; ---------------------------------------------------------------------------
global ratelimit_check_msg
ratelimit_check_msg:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    call ratelimit_refill
    ; 0 max = unlimited
    cmp qword [rbx + RateLimit.max_msg_sec], 0
    je .check_bytes
    cmp qword [rbx + RateLimit.msg_tokens], 0
    jbe .exceeded
    dec qword [rbx + RateLimit.msg_tokens]
.check_bytes:
    cmp qword [rbx + RateLimit.max_bytes_sec], 0
    je .ok
    mov rax, [rbx + RateLimit.byte_tokens]
    cmp rax, r12
    jb .exceeded
    sub [rbx + RateLimit.byte_tokens], r12
.ok:
    mov byte [rbx + RateLimit.throttled], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.exceeded:
    inc dword [rbx + RateLimit.violations]
    mov byte [rbx + RateLimit.throttled], 1
    mov rax, -EQUOTA_RATE
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; ratelimit_is_throttled
; ---------------------------------------------------------------------------
global ratelimit_is_throttled
ratelimit_is_throttled:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + RateLimit.throttled]
    leave
    ret

; ---------------------------------------------------------------------------
; ratelimit_reset
; ---------------------------------------------------------------------------
global ratelimit_reset
ratelimit_reset:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + RateLimit.max_msg_sec]
    mov [rbx + RateLimit.msg_tokens], rax
    mov rax, [rbx + RateLimit.max_bytes_sec]
    mov [rbx + RateLimit.byte_tokens], rax
    mov byte [rbx + RateLimit.throttled], 0
    call tv_time_now_ns
    mov [rbx + RateLimit.msg_last], rax
    mov [rbx + RateLimit.byte_last], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global ratelimit_version
ratelimit_version: dq 0x010000
