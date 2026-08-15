; =============================================================================
; Tattva OS — lib/ulog/format/text_render.asm
; =============================================================================
; Human-readable rendering — what sinks/serial.asm writes, and what a future
; live-tail tool under tools/coretools/ would call too. Separate from
; json_render.asm on purpose: binary storage, machine-readable rendering, and
; human-readable rendering are three different concerns that happen to share
; a source record.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_FORMAT_TEXT_RENDER_ASM
%define LIB_ULOG_FORMAT_TEXT_RENDER_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"
%include "lib/ulog/context/fields_schema.inc"

section .text

; -----------------------------------------------------------------------------
; text_render_level_prefix — Input: RDI = level. Output: none, writes via uart.
; -----------------------------------------------------------------------------
global text_render_level_prefix
text_render_level_prefix:
    push rsi

    cmp edi, LVL_TRACE
    je .t
    cmp edi, LVL_DEBUG
    je .d
    cmp edi, LVL_INFO
    je .i
    cmp edi, LVL_WARN
    je .w
    cmp edi, LVL_ERROR
    je .e
    cmp edi, LVL_FATAL
    je .f
    mov rsi, trp_unknown
    jmp .out
.t: mov rsi, trp_trace
    jmp .out
.d: mov rsi, trp_debug
    jmp .out
.i: mov rsi, trp_info
    jmp .out
.w: mov rsi, trp_warn
    jmp .out
.e: mov rsi, trp_error
    jmp .out
.f: mov rsi, trp_fatal
.out:
    call uart_print_str
    pop rsi
    ret

; -----------------------------------------------------------------------------
; text_render_line — Input: RDI = log_record_t*. Output: none, writes a full
; line (prefix, timestamp, module, message, fields) via uart, CRLF-terminated.
; -----------------------------------------------------------------------------
global text_render_line
text_render_line:
    push rbx
    mov rbx, rdi

    movzx edi, byte [rbx + log_record_t.level]
    call text_render_level_prefix

    mov rdi, [rbx + log_record_t.ts_ns]
    call timestamp_fmt_write
    mov al, ' '
    call uart_putc

    movzx eax, word [rbx + log_record_t.module_id]
    call uart_print_hex32
    mov al, ' '
    call uart_putc

    mov rsi, [rbx + log_record_t.msg_ptr]
    call uart_print_str

    cmp qword [rbx + log_record_t.fields_ptr], 0
    je .no_fields
    mov al, ' '
    call uart_putc
    mov rdi, [rbx + log_record_t.fields_ptr]
    call .render_fields

.no_fields:
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc

    pop rbx
    ret

; ---- .render_fields: RDI = fields buffer -----------------------------------
.render_fields:
    push rbx
    push r12
    push r13

    mov r12, rdi
    xor r13, r13

.field_loop:
    mov rdi, r12
    call fields_decode_count
    cmp r13, rax
    jae .fields_done

    mov rdi, r12
    mov rsi, r13
    call fields_decode_get
    mov rbx, rax

    mov rsi, [rbx + field_entry_t.key_ptr]
    call uart_print_str
    mov al, '='
    call uart_putc

    movzx eax, byte [rbx + field_entry_t.val_type]
    cmp eax, FIELD_TYPE_STR
    je .val_str
    cmp eax, FIELD_TYPE_HEX
    je .val_hex
    mov eax, [rbx + field_entry_t.val]
    call uart_print_dec
    jmp .val_done
.val_str:
    mov rsi, [rbx + field_entry_t.val]
    call uart_print_str
    jmp .val_done
.val_hex:
    mov eax, [rbx + field_entry_t.val]
    call uart_print_hex32
.val_done:
    mov al, ' '
    call uart_putc

    inc r13
    jmp .field_loop

.fields_done:
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
trp_trace:   db "[TRACE] ", 0
trp_debug:   db "[DEBUG] ", 0
trp_info:    db "[INFO]  ", 0
trp_warn:    db "[WARN]  ", 0
trp_error:   db "[ERROR] ", 0
trp_fatal:   db "[FATAL] ", 0
trp_unknown: db "[?????] ", 0

%endif ; LIB_ULOG_FORMAT_TEXT_RENDER_ASM
