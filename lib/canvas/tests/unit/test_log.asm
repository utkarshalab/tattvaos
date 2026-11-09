; ============================================================================
; Unit Test — The Log (src/core/log.asm, OBS-01)
; ============================================================================
; test_log_suite -> eax = failed cases (each case returns 0 / 1).
; Lines go to a sink here that keeps the last one and counts them; the clock
; is a variable the cases move.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/log.inc"

section .text

global test_log_suite
test_log_suite:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tl_format
    CASE tl_levels
    CASE tl_rate
    CASE tl_cut
    CASE tl_category
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; the log as at start, its lines to capture, its clock fake_now
fresh:
    sub rsp, 8
    call log_init
    lea rdi, [rel capture]
    call log_set_sink
    lea rdi, [rel fake_clock]
    call log_set_clock
    mov qword [rel fake_now], 1000000000
    mov qword [rel lines], 0
    mov qword [rel last_len], 0
    add rsp, 8
    ret

; the sink: rdi = bytes, rsi = length -> kept as the last line, counted
capture:
    inc qword [rel lines]
    mov [rel last_len], rsi
    mov rcx, rsi
    cmp rcx, 512
    jbe .copy
    mov ecx, 512
.copy:
    mov rsi, rdi
    lea rdi, [rel last_line]
    rep movsb
    ret

fake_clock:
    mov rax, [rel fake_now]
    ret

; the last line is the %2 bytes at %1
%macro LAST_IS 2
    cmp qword [rel last_len], %2
    jne .fail
    lea rsi, [rel %1]
    lea rdi, [rel last_line]
    mov ecx, %2
    repe cmpsb
    jne .fail
%endmacro

; One line a message, "[level] category: message"; debug filtered at start
tl_format:
    sub rsp, 8
    mov edi, LOG_CAT_CLIENT
    lea rsi, [rel hello]
    mov edx, 5
    call log_info
    cmp eax, 1
    jne .fail
    LAST_IS expect_info, expect_info_len
    mov edi, LOG_CAT_CLIENT
    lea rsi, [rel hello]
    mov edx, 5
    call log_debug
    test eax, eax
    jnz .fail                           ; filtered
    cmp qword [rel lines], 1
    jne .fail
    PASS

; Each category its own level: input at errors only drops a warning that
; the shell writes; all at debug lets debug through
tl_levels:
    sub rsp, 8
    mov edi, LOG_CAT_INPUT
    mov esi, LOG_ERROR
    call log_set_level
    mov edi, LOG_CAT_INPUT
    lea rsi, [rel hello]
    mov edx, 5
    call log_warn
    test eax, eax
    jnz .fail
    mov edi, LOG_CAT_SHELL
    lea rsi, [rel hello]
    mov edx, 5
    call log_warn
    cmp eax, 1
    jne .fail
    mov edi, LOG_CAT_ALL
    mov esi, LOG_DEBUG
    call log_set_level
    mov edi, LOG_CAT_INPUT
    lea rsi, [rel hello]
    mov edx, 5
    call log_debug
    cmp eax, 1
    jne .fail
    LAST_IS expect_debug, expect_debug_len
    PASS

; 30 errors at once: 20 written, 10 dropped; a second later the next says
; first how many were lost
tl_rate:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx                        ; written
    xor r12d, r12d
.flood:
    mov edi, LOG_CAT_RENDER
    lea rsi, [rel hello]
    mov edx, 5
    call log_error
    cmp eax, 1
    jne .not_written
    inc ebx
.not_written:
    inc r12d
    cmp r12d, 30
    jb .flood
    cmp ebx, 20
    jne .bad
    cmp qword [rel lines], 20
    jne .bad
    add qword [rel fake_now], 1000000000
    mov edi, LOG_CAT_RENDER
    lea rsi, [rel note]
    mov edx, 4
    call log_error
    cmp eax, 1
    jne .bad
    cmp qword [rel lines], 22           ; the count, then the message
    jne .bad
    mov edi, LOG_CAT_RENDER             ; and the count came first: the
    lea rsi, [rel hello]                ; bucket still has room, so check
    mov edx, 5                          ; the last line is this message
    call log_error
    cmp qword [rel lines], 23
    jne .bad
    xor eax, eax
    jmp .out
.bad:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; A message too long for a line is cut, the line still ending in a newline
tl_cut:
    sub rsp, 8
    mov edi, LOG_CAT_DATA
    lea rsi, [rel long_text]
    mov edx, 400
    call log_info
    cmp qword [rel last_len], 256
    jne .fail
    cmp byte [rel last_line + 255], 10
    jne .fail
    PASS

; A category past the last is written as core's
tl_category:
    sub rsp, 8
    mov edi, 99
    lea rsi, [rel hello]
    mov edx, 5
    call log_warn
    cmp eax, 1
    jne .fail
    LAST_IS expect_core, expect_core_len
    PASS

section .rodata
hello:          db "hello"
note:           db "note"
expect_info:    db "[info] client: hello", 10
expect_info_len: equ $ - expect_info
expect_debug:   db "[debug] input: hello", 10
expect_debug_len: equ $ - expect_debug
expect_core:    db "[warn] core: hello", 10
expect_core_len: equ $ - expect_core
long_text:      times 400 db 'x'

section .bss
alignb 8
fake_now:       resq 1
lines:          resq 1
last_len:       resq 1
last_line:      resb 512
