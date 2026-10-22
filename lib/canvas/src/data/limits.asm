; ============================================================================
; Limits — Data Transfer Size and Rate Limits
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define LIMITS_DEFAULT_CLIPBOARD    (1024 * 1024)      ; 1MB
%define LIMITS_DEFAULT_SELECTION    (1024 * 1024)      ; 1MB
%define LIMITS_DEFAULT_DND          (10 * 1024 * 1024) ; 10MB
%define LIMITS_DEFAULT_OFFER_MIMES  16
%define LIMITS_RATE_MSG_PER_SEC     1000
%define LIMITS_RATE_BYTES_PER_SEC   (10 * 1024 * 1024) ; 10MB/s
%define Limits_SIZE    56
%define ClientLimits_SIZE    48

section .text

; Limits struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ---------------------------------------------------------------------------
; limits_init
; ---------------------------------------------------------------------------
global limits_init
limits_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Limits.clipboard_max], LIMITS_DEFAULT_CLIPBOARD
    mov qword [rbx + Limits.selection_max], LIMITS_DEFAULT_SELECTION
    mov qword [rbx + Limits.dnd_max], LIMITS_DEFAULT_DND
    mov dword [rbx + Limits.offer_mimes_max], LIMITS_DEFAULT_OFFER_MIMES
    mov qword [rbx + Limits.rate_msg_per_sec], LIMITS_RATE_MSG_PER_SEC
    mov qword [rbx + Limits.rate_bytes_per_sec], LIMITS_RATE_BYTES_PER_SEC
    mov qword [rbx + Limits.per_client_limits], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; limits_check_clipboard
;   Check clipboard size against limit
; ---------------------------------------------------------------------------
global limits_check_clipboard
limits_check_clipboard:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Limits.clipboard_max]
    cmp r12, rax
    ja .exceeded
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.exceeded:
    mov rax, -(ECLIP_SIZE)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; limits_check_selection
; ---------------------------------------------------------------------------
global limits_check_selection
limits_check_selection:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Limits.selection_max]
    cmp r12, rax
    ja .exceeded
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.exceeded:
    mov rax, -(ECLIP_SIZE)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; limits_check_dnd
; ---------------------------------------------------------------------------
global limits_check_dnd
limits_check_dnd:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Limits.dnd_max]
    cmp r12, rax
    ja .exceeded
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.exceeded:
    mov rax, -(ECLIP_SIZE)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; limits_check_offer_mimes
; ---------------------------------------------------------------------------
global limits_check_offer_mimes
limits_check_offer_mimes:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Limits.offer_mimes_max]
    cmp esi, eax
    ja .exceeded
    xor rax, rax
    leave
    ret

.exceeded:
    mov rax, -(ECLIP_MIME)
    leave
    ret

; ---------------------------------------------------------------------------
; limits_client_init
;   Initialize per-client limits
; ---------------------------------------------------------------------------
global limits_client_init
limits_client_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, ClientLimits_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rax + ClientLimits.clipboard_bytes], 0
    mov qword [rax + ClientLimits.selection_bytes], 0
    mov qword [rax + ClientLimits.dnd_bytes], 0
    mov qword [rax + ClientLimits.messages_sent], 0
    mov qword [rax + ClientLimits.bytes_sent], 0
    call tv_time_now_ns
    mov [rax + ClientLimits.last_reset], rax

    mov qword [rbx + Limits.per_client_limits], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; limits_client_check_rate
;   Check client rate limits
; ---------------------------------------------------------------------------
global limits_client_check_rate
limits_client_check_rate:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Limits.rate_msg_per_sec]
    cmp qword [r12 + ClientLimits.messages_sent], rax
    ja .rate_exceeded

    mov rax, [rbx + Limits.rate_bytes_per_sec]
    cmp qword [r12 + ClientLimits.bytes_sent], rax
    ja .rate_exceeded

    ; Check if reset needed
    mov rax, [r12 + ClientLimits.last_reset]
    call tv_time_now_ns
    sub rax, [r12 + ClientLimits.last_reset]
    cmp rax, 1000000000  ; 1 second
    jb .ok

    ; Reset counters
    mov qword [r12 + ClientLimits.messages_sent], 0
    mov qword [r12 + ClientLimits.bytes_sent], 0
    call tv_time_now_ns
    mov [r12 + ClientLimits.last_reset], rax

.ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.rate_exceeded:
    mov rax, -(EQUOTA_RATE)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; limits_client_account
;   Account for client operation
; ---------------------------------------------------------------------------
global limits_client_account
limits_client_account:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Increment message count
    inc qword [r12 + ClientLimits.messages_sent]

    ; Add bytes
    add qword [r12 + ClientLimits.bytes_sent], r13

    ; Check limits
    call limits_client_check_rate

    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global limits_version
limits_version: dq 0x010000
