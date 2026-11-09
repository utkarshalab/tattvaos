; ============================================================================
; Log — Levels, Categories, Rate Limits (OBS-01)
; ============================================================================
; One line a message: "[level] category: message". Each category has its
; own level (LOG_INFO at start: errors, warnings and information pass,
; debug does not) and its own rate limit: a bucket of LOG_BURST messages,
; one more back every LOG_REFILL_NS. A message past the limit is dropped
; and counted; the next one let through first says how many were. So a
; client that floods errors costs the log LOG_BURST lines and a count.
;
; Lines go to ut_log_write unless log_set_sink names another writer;
; log_set_clock gives another clock (tests).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/ut.inc"
%define LOG_IMPL
%include "inc/log.inc"

default rel

%define LOG_CATEGORIES  10
%define LOG_BURST       20
%define LOG_REFILL_NS   50000000        ; one back every 50 ms: 20 a second
%define LOG_LINE        256

section .text

; ---------------------------------------------------------------------------
; log_init
;   Every category at LOG_INFO with a full bucket; ut_log_write and the
;   monotonic clock (done by the first message if not called)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global log_init
log_init:
    push rbx
    lea rax, [rel ut_log_write]
    mov [rel sink], rax
    lea rax, [rel ut_time_now_ns]
    mov [rel clock], rax
    call [rel clock]
    xor ecx, ecx
.category:
    lea rdx, [rel levels]
    mov byte [rdx + rcx], LOG_INFO
    lea rdx, [rel tokens]
    mov dword [rdx + rcx * 4], LOG_BURST
    lea rdx, [rel dropped]
    mov dword [rdx + rcx * 4], 0
    lea rdx, [rel refilled]
    mov [rdx + rcx * 8], rax
    inc ecx
    cmp ecx, LOG_CATEGORIES
    jb .category
    mov dword [rel ready], 1
    xor eax, eax
    pop rbx
    ret

; ---------------------------------------------------------------------------
; log_set_level
;   IN:  edi = category (LOG_CAT_*), or -1 for all; esi = the most detailed
;        level that passes (LOG_ERROR to LOG_DEBUG; 0: none)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global log_set_level
log_set_level:
    push rdi
    push rsi
    sub rsp, 8
    call ensure
    add rsp, 8
    pop rsi
    pop rdi
    lea rdx, [rel levels]
    cmp edi, -1
    je .all
    cmp edi, LOG_CATEGORIES
    jae .out
    mov [rdx + rdi], sil
    jmp .out
.all:
    xor ecx, ecx
.each:
    mov [rdx + rcx], sil
    inc ecx
    cmp ecx, LOG_CATEGORIES
    jb .each
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; log_set_sink / log_set_clock
;   IN:  rdi = a writer (rdi = bytes, rsi = length), or a clock (-> rax ns);
;        0 for ut_log_write / ut_time_now_ns
; ---------------------------------------------------------------------------
global log_set_sink
log_set_sink:
    push rdi
    call ensure
    pop rdi
    test rdi, rdi
    jnz .set
    lea rdi, [rel ut_log_write]
.set:
    mov [rel sink], rdi
    xor eax, eax
    ret

global log_set_clock
log_set_clock:
    push rdi
    call ensure
    pop rdi
    test rdi, rdi
    jnz .set
    lea rdi, [rel ut_time_now_ns]
.set:
    mov [rel clock], rdi
    sub rsp, 8                          ; every bucket counted from the new
    call rdi                            ; clock's now
    add rsp, 8
    lea rdx, [rel refilled]
    xor ecx, ecx
.bucket:
    mov [rdx + rcx * 8], rax
    inc ecx
    cmp ecx, LOG_CATEGORIES
    jb .bucket
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; log_write
;   One message
;   IN:  edi = level (LOG_ERROR to LOG_DEBUG), esi = category (another:
;        LOG_CAT_CORE), rdx = message bytes, ecx = their length
;   OUT: rax = 1 written, 0 below the category's level, 2 dropped by the
;        rate limit
; ---------------------------------------------------------------------------
global log_write
log_write:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    call ensure
    cmp r12d, LOG_CATEGORIES
    jb .category
    xor r12d, r12d
.category:
    lea rax, [rel levels]
    movzx eax, byte [rax + r12]
    xor r15d, r15d                      ; 0: filtered
    cmp ebx, eax
    ja .out
    call [rel clock]                    ; the bucket, refilled for the time
    lea rcx, [rel refilled]             ; gone by
    mov rdx, rax
    sub rdx, [rcx + r12 * 8]
    jb .counted                         ; the clock went back: as it was
    mov rax, rdx
    xor edx, edx
    mov r8d, LOG_REFILL_NS
    div r8
    test rax, rax
    jz .counted
    mov r9, rax
    imul r9, r8
    add [rcx + r12 * 8], r9
    lea rcx, [rel tokens]
    cmp rax, LOG_BURST
    jb .add
    mov eax, LOG_BURST
.add:
    add eax, [rcx + r12 * 4]
    cmp eax, LOG_BURST
    jbe .filled
    mov eax, LOG_BURST
.filled:
    mov [rcx + r12 * 4], eax
.counted:
    lea rcx, [rel tokens]
    mov r15d, 2                         ; 2: dropped
    cmp dword [rcx + r12 * 4], 0
    jne .allowed
    lea rcx, [rel dropped]
    inc dword [rcx + r12 * 4]
    jmp .out
.allowed:
    dec dword [rcx + r12 * 4]
    lea rcx, [rel dropped]
    mov eax, [rcx + r12 * 4]
    test eax, eax
    jz .line
    mov dword [rcx + r12 * 4], 0        ; first, how many were lost
    mov edi, eax
    mov esi, r12d
    call dropped_line
.line:
    mov edi, ebx
    mov esi, r12d
    mov rdx, r13
    mov ecx, r14d
    call emit
    mov r15d, 1
.out:
    mov eax, r15d
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; log_error, log_warn, log_info, log_debug: edi = category, rsi = message,
; edx = length -> as log_write
%macro AT_LEVEL 2
global %1
%1:
    mov ecx, edx
    mov rdx, rsi
    mov esi, edi
    mov edi, %2
    jmp log_write
%endmacro
AT_LEVEL log_error, LOG_ERROR
AT_LEVEL log_warn, LOG_WARN
AT_LEVEL log_info, LOG_INFO
AT_LEVEL log_debug, LOG_DEBUG

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; log_init, once
ensure:
    cmp dword [rel ready], 0
    jne .done
    sub rsp, 8
    call log_init
    add rsp, 8
.done:
    ret

; "[level] category: message\n" to the sink, the message cut to fit.
; edi = level (LOG_ERROR to LOG_DEBUG), esi = category, rdx = message,
; ecx = length
emit:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov ebx, esi
    mov r12, rdx
    mov r13d, ecx
    lea r14, [rel line]
    mov byte [r14], '['
    inc r14
    lea eax, [rdi - 1]
    cmp eax, 3
    jbe .level
    mov eax, 3
.level:
    lea rcx, [rel level_names]
    mov rsi, [rcx + rax * 8]
    call put_string
    mov byte [r14], ']'
    mov byte [r14 + 1], ' '
    add r14, 2
    lea rcx, [rel category_names]
    mov rsi, [rcx + rbx * 8]
    call put_string
    mov byte [r14], ':'
    mov byte [r14 + 1], ' '
    add r14, 2
    lea rcx, [rel line + LOG_LINE - 1]  ; the message, what fits before the
    sub rcx, r14                        ; newline
    mov eax, r13d
    cmp rax, rcx
    cmova rax, rcx
    mov rcx, rax
    mov rsi, r12
    mov rdi, r14
    rep movsb
    mov byte [rdi], 10
    lea rsi, [rdi + 1]
    lea rdi, [rel line]
    sub rsi, rdi
    call [rel sink]
    EPILOGUE_RESTORE rbx, r12, r13, r14

; rsi = a NUL-terminated string -> copied to r14, r14 past it
put_string:
    mov al, [rsi]
    test al, al
    jz .done
    mov [r14], al
    inc rsi
    inc r14
    jmp put_string
.done:
    ret

; "[warn] category: N messages dropped". edi = N, esi = category
dropped_line:
    push rbx
    push r12
    sub rsp, 56                         ; the text; 16-byte aligned
    mov r12d, esi
    lea rbx, [rsp + 24]                 ; the digits, backwards
    mov eax, edi
    mov ecx, 10
.digit:
    xor edx, edx
    div ecx
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test eax, eax
    jnz .digit
    lea rsi, [rel str_dropped]          ; then the words
    lea rdi, [rsp + 24]
    mov ecx, str_dropped_len
    rep movsb
    mov edi, LOG_WARN
    mov esi, r12d
    mov rdx, rbx
    lea rcx, [rsp + 24 + str_dropped_len]
    sub rcx, rbx
    call emit
    add rsp, 56
    pop r12
    pop rbx
    ret

section .rodata
align 8
level_names:    dq str_error, str_warn, str_info, str_debug
category_names: dq cat_core, cat_server, cat_client, cat_input, cat_output
                dq cat_render, cat_shell, cat_session, cat_security, cat_data
str_error:      db "error", 0
str_warn:       db "warn", 0
str_info:       db "info", 0
str_debug:      db "debug", 0
cat_core:       db "core", 0
cat_server:     db "server", 0
cat_client:     db "client", 0
cat_input:      db "input", 0
cat_output:     db "output", 0
cat_render:     db "render", 0
cat_shell:      db "shell", 0
cat_session:    db "session", 0
cat_security:   db "security", 0
cat_data:       db "data", 0
str_dropped:    db " messages dropped"
str_dropped_len: equ $ - str_dropped

section .bss
alignb 8
sink:           resq 1                  ; the writer: rdi bytes, rsi length
clock:          resq 1                  ; -> rax monotonic ns
refilled:       resq LOG_CATEGORIES     ; when each bucket was last topped up
tokens:         resd LOG_CATEGORIES     ; messages each may still write now
dropped:        resd LOG_CATEGORIES     ; and has dropped since its last line
ready:          resd 1
levels:         resb LOG_CATEGORIES     ; each one's most detailed level
alignb 16
line:           resb LOG_LINE

section .data
global log_version
log_version: dq 0x020000
