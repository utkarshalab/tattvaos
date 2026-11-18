; ============================================================================
; Settings — canvas.conf
; ============================================================================
; DEV-12. The server's settings file, /conf/apps/canvas/canvas.conf, read
; against canvas_schema (core/config) at start:
;
;   [log]      level = error | warn | info | debug | trace      (info)
;   [input]    repeat_delay = 100 to 2000, ms before a held key repeats
;                                                                (500)
;              repeat_rate = 0 to 100 a second, 0 not at all     (30)
;   [session]  lock_after = 0 to 86400 s without input, 0 never  (300)
;   [display]  high_contrast = true | false                      (false)
;   [power]    lid_close = sleep | lock, the lid closed with no
;              other screen on                                   (sleep)
;
; Lines not taken are logged (how many, the first and why); the rest are
; applied, so one mistake costs only its line. Without the file the server
; keeps its own defaults, the same. A user's own settings, under
; /user/<name>/conf/canvas/, wait for the login to say who they are.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/config.inc"
%include "inc/log.inc"
%include "inc/struct_offsets.inc"

extern config_parse
extern fmt_uint
extern ut_fs_read
extern input_set_repeat
extern greeter_set_idle
extern server_set_high_contrast
extern server_set_lid_sleep

%define SETTINGS_FILE_MAX   65536

; the settings: one qword a key
struc CanvasSettings
    .log_level:     resq 1              ; 0 error .. 4 trace
    .repeat_delay:  resq 1              ; ms
    .repeat_rate:   resq 1              ; a second
    .lock_after:    resq 1              ; s
    .high_contrast: resq 1
    .lid_close:     resq 1              ; 0 sleep, 1 lock
endstruc

section .text

; ---------------------------------------------------------------------------
; settings_parse
;   canvas.conf's text into settings
;   IN:  rdi = text, rsi = its length, rdx = CanvasSettings*,
;        rcx = ConfigResult*
;   OUT: rax = config_parse's
; ---------------------------------------------------------------------------
global settings_parse
settings_parse:
    mov r8, rcx
    mov rcx, rdx
    lea rdx, [rel canvas_schema]
    jmp config_parse

; ---------------------------------------------------------------------------
; settings_apply
;   Settings into the server
;   IN:  rdi = server*, rsi = CanvasSettings*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global settings_apply
settings_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov edi, LOG_CAT_ALL
    mov rsi, [r12 + CanvasSettings.log_level]
    inc esi                             ; LOG_ERROR is 1
    call log_set_level
    mov rax, [r12 + CanvasSettings.repeat_delay]
    imul rsi, rax, 1000000
    xor edx, edx                        ; a rate of 0: no repeat
    mov rcx, [r12 + CanvasSettings.repeat_rate]
    test rcx, rcx
    jz .repeat
    mov rax, 1000000000
    xor edx, edx
    div rcx
    mov rdx, rax
.repeat:
    mov rdi, rbx
    call input_set_repeat               ; -ENODEV with no seat yet: kept
    mov rdi, [rbx + Server.greeter]
    test rdi, rdi
    jz .no_greeter
    mov rax, [r12 + CanvasSettings.lock_after]
    imul rsi, rax, 1000000000
    call greeter_set_idle
.no_greeter:
    mov rdi, rbx
    mov rsi, [r12 + CanvasSettings.high_contrast]
    call server_set_high_contrast
    mov rdi, rbx
    xor esi, esi                        ; lid_close 0 sleep: 1
    cmp qword [r12 + CanvasSettings.lid_close], 0
    sete sil
    call server_set_lid_sleep
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; settings_load
;   canvas.conf read, its mistakes logged, applied; nothing without it
;   IN:  rdi = server*
;   OUT: rax = 0 read, negative: not there (or unreadable), nothing changed
; ---------------------------------------------------------------------------
global settings_load
settings_load:
    PROLOGUE_SAVE rbx, r12
    sub rsp, ConfigResult_size
    mov rbx, rdi
    lea rdi, [rel settings_path]
    lea rsi, [rel settings_text]
    mov edx, SETTINGS_FILE_MAX
    call ut_fs_read
    test rax, rax
    js .out
    mov r12, rax
    lea rdi, [rel settings_text]
    mov rsi, r12
    lea rdx, [rel settings_read]
    mov rcx, rsp
    call settings_parse
    test rax, rax
    jz .apply
    mov rdi, rsp
    call log_mistakes
.apply:
    mov rdi, rbx
    lea rsi, [rel settings_read]
    call settings_apply
    xor eax, eax
.out:
    add rsp, ConfigResult_size
    EPILOGUE_RESTORE rbx, r12

; rdi = ConfigResult*: "canvas.conf: line N, <why>; lines not taken: M"
log_mistakes:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    lea r12, [rel message]
    lea rsi, [rel s_line]
    mov ecx, s_line_len
    mov rdi, r12
    rep movsb
    mov r13, rdi
    mov rdi, r13
    mov esi, [rbx + ConfigResult.line]
    mov edx, 10
    xor ecx, ecx
    mov r8d, ' '
    call fmt_uint
    add r13, rax
    mov eax, [rbx + ConfigResult.reason]  ; its reason's words
    dec eax
    cmp eax, CONFIG_E_TWICE - 1
    jbe .reason
    xor eax, eax
.reason:
    lea rcx, [rel reasons]
    mov rsi, [rcx + rax * 8]
    lea rcx, [rel reason_lengths]
    movzx ecx, byte [rcx + rax]
    mov rdi, r13
    rep movsb
    mov r13, rdi
    lea rsi, [rel s_count]
    mov ecx, s_count_len
    rep movsb
    mov r13, rdi
    mov esi, [rbx + ConfigResult.errors]
    mov edx, 10
    xor ecx, ecx
    mov r8d, ' '
    call fmt_uint
    add r13, rax
    mov rdx, r13
    sub rdx, r12
    mov edi, LOG_CAT_SERVER
    mov rsi, r12
    call log_warn
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
settings_path:  db "/conf/apps/canvas/canvas.conf", 0
s_line:         db "canvas.conf: line "
s_line_len      equ $ - s_line
s_count:        db "; lines not taken: "
s_count_len     equ $ - s_count
%macro REASON 2
r_%1:   db %2
r_%1_len equ $ - r_%1
%endmacro
REASON syntax,  ", not a header, key = value or comment"
REASON section, ", no such section"
REASON key,     ", no such key"
REASON value,   ", not a value of its kind"
REASON range,   ", a number out of range"
REASON long,    ", too long"
REASON twice,   ", a key given again"
align 8
reasons:        dq r_syntax, r_section, r_key, r_value, r_range, r_long, r_twice
reason_lengths: db r_syntax_len, r_section_len, r_key_len, r_value_len
                db r_range_len, r_long_len, r_twice_len

log_levels:     db "error", 0, "warn", 0, "info", 0, "debug", 0, "trace", 0, 0
lid_choices:    db "sleep", 0, "lock", 0, 0

align 8
global canvas_schema
canvas_schema:
    dq 6
    CONFIG_KEY "log", "level", CONFIG_ENUM, CanvasSettings.log_level, log_levels, 0, 2
    CONFIG_KEY "input", "repeat_delay", CONFIG_INT, CanvasSettings.repeat_delay, 100, 2000, 500
    CONFIG_KEY "input", "repeat_rate", CONFIG_INT, CanvasSettings.repeat_rate, 0, 100, 30
    CONFIG_KEY "session", "lock_after", CONFIG_INT, CanvasSettings.lock_after, 0, 86400, 300
    CONFIG_KEY "display", "high_contrast", CONFIG_BOOL, CanvasSettings.high_contrast, 0, 0, 0
    CONFIG_KEY "power", "lid_close", CONFIG_ENUM, CanvasSettings.lid_close, lid_choices, 0, 0

section .bss
alignb 16
settings_read:  resb CanvasSettings_size
message:        resb 160
settings_text:  resb SETTINGS_FILE_MAX

section .data
global settings_version
settings_version: dq 0x010000
