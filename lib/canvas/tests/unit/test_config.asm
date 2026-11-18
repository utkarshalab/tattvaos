; ============================================================================
; Unit Test — Settings Files (core/config, server/settings: DEV-12)
; ============================================================================
; test_config_suite -> eax = failed cases. A schema of every kind of key
; (strings, integers with a range, booleans, choices; keys before any
; section and the same name in two): its defaults; a file of comments, CR
; LF and LF, spacing, quoting and escapes, inline comments; each reason a
; line is not taken, with its line, and the others still taken; integers'
; and strings' edges; canvas.conf's schema, and settings_apply on a server.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/config.inc"
%include "inc/struct_offsets.inc"

extern config_parse
extern config_defaults
extern settings_parse
extern settings_apply
extern log_set_sink
extern log_debug

; the test schema's settings
%define T_NAME      0                   ; 8 bytes: 7 and the NUL
%define T_COUNT     8
%define T_FLAG      16
%define T_MODE      24
%define T_BCOUNT    32
%define T_TEXT      40                  ; 16 bytes
%define T_SIZE      56

section .text

global test_config_suite
global test_config_main
test_config_suite:
test_config_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tc_defaults
    CASE tc_good
    CASE tc_mistakes
    CASE tc_reasons
    CASE tc_canvas
    CASE tc_apply
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

; PARSE text: into t_out against t_schema, the result in t_result
%macro PARSE 1
    lea rdi, [rel %1]
    mov esi, %1_len
    lea rdx, [rel t_schema]
    lea rcx, [rel t_out]
    lea r8, [rel t_result]
    call config_parse
%endmacro
%macro IS 2                             ; a qword setting
    cmp qword [rel t_out + %1], %2
    jne .fail
%endmacro
%macro TEXT_IS 2                        ; a string setting, a label
    lea rdi, [rel t_out + %1]
    lea rsi, [rel %2]
    call same_text
    jne .fail
%endmacro
%macro RESULT 3                         ; errors, first line, reason
    cmp dword [rel t_result + ConfigResult.errors], %1
    jne .fail
    cmp dword [rel t_result + ConfigResult.line], %2
    jne .fail
    cmp dword [rel t_result + ConfigResult.reason], %3
    jne .fail
%endmacro

; no text: every default, nothing wrong
tc_defaults:
    sub rsp, 8
    lea rdi, [rel t_out]                ; scribbled first
    mov al, 0x5A
    mov ecx, T_SIZE
    rep stosb
    PARSE f_empty
    test rax, rax
    jnz .fail
    RESULT 0, 0, 0
    TEXT_IS T_NAME, s_def
    IS T_COUNT, 7
    IS T_FLAG, 1
    IS T_MODE, 1
    IS T_BCOUNT, 0
    TEXT_IS T_TEXT, s_empty
    PASS

; comments, CR LF, spacing, a quoted string with escapes and comment marks,
; an inline comment, keys before any header, [ b ]'s count apart from the
; first
tc_good:
    sub rsp, 8
    PARSE f_good
    test rax, rax
    jnz .fail
    RESULT 0, 0, 0
    TEXT_IS T_NAME, s_abc
    IS T_COUNT, -5
    IS T_FLAG, 0
    IS T_MODE, 0
    IS T_BCOUNT, 10
    TEXT_IS T_TEXT, s_escaped
    PASS

; every kind of line not taken, counted, the first's line and reason; the
; keys under a section that does not exist passed over without a word; a
; key whose line was not taken given again is taken; the others hold
tc_mistakes:
    sub rsp, 8
    PARSE f_mistakes
    cmp rax, -EINVAL
    jne .fail
    RESULT 10, 1, CONFIG_E_RANGE
    IS T_COUNT, 7
    TEXT_IS T_NAME, s_def
    IS T_FLAG, 1
    IS T_MODE, 1
    IS T_BCOUNT, 0
    PASS

; a line or two each: taken (and count then) or its reason and line
tc_reasons:
    push rbx
    push r12
    sub rsp, 8
    lea r12, [rel reason_cases]
.case:
    mov rdi, [r12]
    test rdi, rdi
    jz .pass
    mov esi, [r12 + 8]
    lea rdx, [rel t_schema]
    lea rcx, [rel t_out]
    lea r8, [rel t_result]
    call config_parse
    mov eax, [r12 + 12]                 ; 0: taken
    test eax, eax
    jnz .refused
    cmp dword [rel t_result + ConfigResult.errors], 0
    jne .fail
    mov rax, [r12 + 16]                 ; and T_COUNT is
    cmp [rel t_out + T_COUNT], rax
    jne .fail
    jmp .next
.refused:
    cmp dword [rel t_result + ConfigResult.errors], 1
    jne .fail
    mov rcx, [r12 + 16]                 ; on its line
    cmp [rel t_result + ConfigResult.line], ecx
    jne .fail
    cmp [rel t_result + ConfigResult.reason], eax
    jne .fail
.next:
    add r12, 24
    jmp .case
.pass:
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; canvas.conf: every key, then nothing: the documented defaults
tc_canvas:
    sub rsp, 24
    lea rdi, [rel f_canvas]
    mov esi, f_canvas_len
    lea rdx, [rel c_out]
    mov rcx, rsp
    call settings_parse
    test rax, rax
    jnz .fail
    cmp qword [rel c_out + 0], 3        ; level debug
    jne .fail
    cmp qword [rel c_out + 8], 250      ; repeat_delay
    jne .fail
    cmp qword [rel c_out + 16], 0       ; repeat_rate: none
    jne .fail
    cmp qword [rel c_out + 24], 0       ; lock_after: never
    jne .fail
    cmp qword [rel c_out + 32], 1       ; high_contrast
    jne .fail
    cmp qword [rel c_out + 40], 1       ; lid_close lock
    jne .fail
    lea rdi, [rel f_empty]
    xor esi, esi
    lea rdx, [rel c_out]
    mov rcx, rsp
    call settings_parse
    test rax, rax
    jnz .fail
    cmp qword [rel c_out + 0], 2        ; info
    jne .fail
    cmp qword [rel c_out + 8], 500
    jne .fail
    cmp qword [rel c_out + 16], 30
    jne .fail
    cmp qword [rel c_out + 24], 300
    jne .fail
    cmp qword [rel c_out + 32], 0
    jne .fail
    cmp qword [rel c_out + 40], 0
    jne .fail
    xor eax, eax
    add rsp, 24
    ret
.fail:
    mov eax, 1
    add rsp, 24
    ret

; settings_apply on a server with nothing yet (no seat, greeter or
; outputs): high contrast on, the lid locking only, debug messages logged;
; then off, sleeping, and debug ones not (info)
tc_apply:
    sub rsp, 24
    lea rdi, [rel f_canvas]
    mov esi, f_canvas_len
    lea rdx, [rel c_out]
    mov rcx, rsp
    call settings_parse
    lea rdi, [rel fake_server]
    lea rsi, [rel c_out]
    call settings_apply
    cmp qword [rel fake_server + Server.high_contrast], 1
    jne .fail
    cmp qword [rel fake_server + Server.lid_awake], 1
    jne .fail
    call debug_logged
    cmp qword [rel sunk], 1
    jne .fail
    lea rdi, [rel f_empty]
    xor esi, esi
    lea rdx, [rel c_out]
    mov rcx, rsp
    call settings_parse
    lea rdi, [rel fake_server]
    lea rsi, [rel c_out]
    call settings_apply
    cmp qword [rel fake_server + Server.high_contrast], 0
    jne .fail
    cmp qword [rel fake_server + Server.lid_awake], 0
    jne .fail
    call debug_logged
    cmp qword [rel sunk], 0
    jne .fail
    xor eax, eax
    add rsp, 24
    ret
.fail:
    mov eax, 1
    add rsp, 24
    ret

; a debug message through a counting sink -> [sunk] = 1 it was logged
debug_logged:
    sub rsp, 8
    mov qword [rel sunk], 0
    lea rdi, [rel sink]
    call log_set_sink
    xor edi, edi
    lea rsi, [rel s_def]
    mov edx, 3
    call log_debug
    xor edi, edi                        ; the usual writer again
    call log_set_sink
    add rsp, 8
    ret
sink:
    inc qword [rel sunk]
    xor eax, eax
    ret

; rdi, rsi = NUL-terminated -> ZF set the same
same_text:
    mov al, [rdi]
    cmp al, [rsi]
    jne .out
    test al, al
    jz .out
    inc rdi
    inc rsi
    jmp same_text
.out:
    ret

section .rodata
modes:      db "fast", 0, "slow", 0, "off", 0, 0
s_def:      db "def", 0
s_empty:    db 0
s_abc:      db "abc", 0
s_escaped:  db 'x"y\z#;', 9, 0

align 8
t_schema:
    dq 6
    CONFIG_KEY "", "name", CONFIG_STRING, T_NAME, 8, 0, s_def
    CONFIG_KEY "", "count", CONFIG_INT, T_COUNT, -5, 100, 7
    CONFIG_KEY "a", "flag", CONFIG_BOOL, T_FLAG, 0, 0, 1
    CONFIG_KEY "a", "mode", CONFIG_ENUM, T_MODE, modes, 0, 1
    CONFIG_KEY "b", "count", CONFIG_INT, T_BCOUNT, 0, 10, 0
    CONFIG_KEY "b", "text", CONFIG_STRING, T_TEXT, 16, 0, s_empty

f_empty:
f_empty_len equ 0

f_good:
    db "# a comment", 13, 10
    db "; another", 10
    db 10
    db "name = abc   # inline", 13, 10
    db "count=-5", 10
    db "[a]", 10
    db 9, "  flag = off", 13, 10
    db "mode=fast", 10
    db "[ b ]   ; spaced", 10
    db "count = 10", 10
    db 'text = "x\"y\\z#;\t"  # quoted', 10
f_good_len equ $ - f_good

f_mistakes:
    db "count = 101", 10                ; 1 range
    db "name = toolong8", 10            ; 2 too long
    db "bogus = 1", 10                  ; 3 no such key
    db "[zzz]", 10                      ; 4 no such section
    db "count = 3", 10                  ;   passed over with it
    db "[a]", 10
    db "flag = maybe", 10               ; 7 not a value
    db "flag = yes", 10                 ;   taken: 7 was not
    db "flag = no", 10                  ; 9 given again
    db "mode = = fast", 10              ; 10 not a choice
    db "just words", 10                 ; 11 syntax
    db "[b", 10                         ; 12 syntax: [a] still
    db "count = 4", 10                  ; 13 no such key in a
f_mistakes_len equ $ - f_mistakes

%macro REASON_CASE 3                    ; text, reason (0 taken), count then
    dq %%text                           ; (taken) or the line (not)
    dd %%end - %%text, %2
    dq %3
[section .rodata.cases]
%%text: db %1
%%end:
__SECT__
%endmacro
align 8
reason_cases:
    REASON_CASE "count = +100", 0, 100
    REASON_CASE "count = -5", 0, -5
    REASON_CASE "count=0007", 0, 7
    REASON_CASE "count = -6", CONFIG_E_RANGE, 1
    REASON_CASE "count = 99999999999999999999", CONFIG_E_RANGE, 1
    REASON_CASE "count = 1x", CONFIG_E_VALUE, 1
    REASON_CASE "count = -", CONFIG_E_VALUE, 1
    REASON_CASE "count =", CONFIG_E_VALUE, 1
    REASON_CASE 'count = "5"', CONFIG_E_VALUE, 1
    REASON_CASE "count", CONFIG_E_SYNTAX, 1
    REASON_CASE "= 5", CONFIG_E_SYNTAX, 1
    REASON_CASE {"count = 1", 0, "2"}, CONFIG_E_SYNTAX, 1
    REASON_CASE 'name = "abc', CONFIG_E_SYNTAX, 1
    REASON_CASE 'name = "abc" x', CONFIG_E_SYNTAX, 1
    REASON_CASE 'name = "a\q"', CONFIG_E_VALUE, 1
    REASON_CASE 'name = "1234567"', 0, 7
    REASON_CASE 'name = "12345678"', CONFIG_E_LONG, 1
    REASON_CASE "name = 12345678", CONFIG_E_LONG, 1
    REASON_CASE "[]", CONFIG_E_SYNTAX, 1
    REASON_CASE "[a] x", CONFIG_E_SYNTAX, 1
    REASON_CASE {"[a]", 10, "flag = 2"}, CONFIG_E_VALUE, 2
    REASON_CASE {"[a]", 10, "mode = Fast"}, CONFIG_E_VALUE, 2
    REASON_CASE {"[a]", 10, "mode = slow"}, 0, 7
    dq 0

f_canvas:
    db "[log]", 10, "level = debug", 10
    db "[input]", 10, "repeat_delay = 250", 10, "repeat_rate = 0", 10
    db "[session]", 10, "lock_after = 0", 10
    db "[display]", 10, "high_contrast = on", 10
    db "[power]", 10, "lid_close = lock", 10
f_canvas_len equ $ - f_canvas

section .bss
alignb 16
t_out:          resb T_SIZE
t_result:       resb ConfigResult_size
c_out:          resq 8
fake_server:    resb Server_size
sunk:           resq 1
