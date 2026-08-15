; =============================================================================
; Tattva OS — lib/ulog/level/level_parse.asm
; =============================================================================
; Parses a level from a boot argument or config string (config/boot_args.asm
; calls this). Accepts the short names, not full words — boot command lines
; are not the place for verbosity.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_LEVEL_LEVEL_PARSE_ASM
%define LIB_ULOG_LEVEL_LEVEL_PARSE_ASM

[BITS 64]

%include "lib/ulog/level/level_defs.inc"

section .text

; -----------------------------------------------------------------------------
; level_parse — "trace"/"debug"/"info"/"warn"/"error"/"fatal"/"off" -> level
; Input:  RDI = pointer to a lowercase, null-terminated token
; Output: RAX = level (LVL_DEFAULT if unrecognized)
; Clobbers: RAX, RCX, RDX, RSI
; -----------------------------------------------------------------------------
global level_parse
level_parse:
    push rbx
    mov rbx, rdi                     ; RBX = token pointer, preserved across .try

    mov rsi, .tok_trace
    mov edx, LVL_TRACE
    call .try
    test eax, eax
    jnz .found

    mov rsi, .tok_debug
    mov edx, LVL_DEBUG
    call .try
    test eax, eax
    jnz .found

    mov rsi, .tok_info
    mov edx, LVL_INFO
    call .try
    test eax, eax
    jnz .found

    mov rsi, .tok_warn
    mov edx, LVL_WARN
    call .try
    test eax, eax
    jnz .found

    mov rsi, .tok_error
    mov edx, LVL_ERROR
    call .try
    test eax, eax
    jnz .found

    mov rsi, .tok_fatal
    mov edx, LVL_FATAL
    call .try
    test eax, eax
    jnz .found

    mov rsi, .tok_off
    mov edx, LVL_OFF
    call .try
    test eax, eax
    jnz .found

    mov eax, LVL_DEFAULT
    jmp .ret

.found:
    mov eax, edx

.ret:
    pop rbx
    ret

; ---- .try: RBX = candidate token, RSI = literal to compare against ----------
; Output: EAX = 1 if equal, 0 otherwise. RDX (the level value) untouched.
.try:
    push rcx
    push rdi
    mov rdi, rbx
.cmp_loop:
    mov cl, [rdi]
    cmp cl, [rsi]
    jne .no
    test cl, cl
    jz .yes
    inc rdi
    inc rsi
    jmp .cmp_loop
.yes:
    mov eax, 1
    jmp .try_done
.no:
    xor eax, eax
.try_done:
    pop rdi
    pop rcx
    ret

section .rodata
.tok_trace: db "trace", 0
.tok_debug: db "debug", 0
.tok_info:  db "info", 0
.tok_warn:  db "warn", 0
.tok_error: db "error", 0
.tok_fatal: db "fatal", 0
.tok_off:   db "off", 0

%endif ; LIB_ULOG_LEVEL_LEVEL_PARSE_ASM
