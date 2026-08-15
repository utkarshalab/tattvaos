; =============================================================================
; Tattva OS — lib/ulog/format/json_render.asm
; =============================================================================
; Machine-readable rendering for sinks/file.asm and sinks/net.asm — what an
; ELK/Datadog-style ingestion pipeline actually wants. Writes into a
; caller-provided buffer instead of to serial, since a sink transport is
; what decides where these bytes ultimately go.
;
; Known limitation: keys and static message strings are assumed not to
; contain a literal `"` — true of every call site in this tree today, since
; messages are static string literals, not user-controlled text. String
; *values* are not similarly assumed safe and are not currently escaped
; either; a field carrying untrusted text should go through
; context/redact_pattern.asm before it ever reaches here.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_FORMAT_JSON_RENDER_ASM
%define LIB_ULOG_FORMAT_JSON_RENDER_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"
%include "lib/ulog/context/fields_schema.inc"

section .text

; -----------------------------------------------------------------------------
; json_render_line — Input: RDI = log_record_t*, RSI = dest buffer,
; RDX = capacity (must be sized generously; not precisely accounted per byte)
; Output: RAX = bytes written
; -----------------------------------------------------------------------------
global json_render_line
json_render_line:
    push rbx
    push r12
    push r13

    mov rbx, rdi                     ; record
    mov r12, rsi                      ; cursor
    mov r13, rsi                       ; original start, for the length at the end

    mov rdi, r12
    mov rsi, .lit_open_seq
    call .append_cstr
    mov r12, rax

    mov rdi, r12
    mov rsi, [rbx + log_record_t.seq]
    call .append_udec
    mov r12, rax

    mov rdi, r12
    mov rsi, .lit_level
    call .append_cstr
    mov r12, rax

    movzx eax, byte [rbx + log_record_t.level]
    mov rdi, r12
    mov rsi, rax
    call .append_udec
    mov r12, rax

    mov rdi, r12
    mov rsi, .lit_module
    call .append_cstr
    mov r12, rax

    movzx eax, word [rbx + log_record_t.module_id]
    mov rdi, r12
    mov rsi, rax
    call .append_udec
    mov r12, rax

    mov rdi, r12
    mov rsi, .lit_msg
    call .append_cstr
    mov r12, rax

    mov rdi, r12
    mov rsi, [rbx + log_record_t.msg_ptr]
    call .append_cstr
    mov r12, rax

    mov rdi, r12
    mov rsi, .lit_msg_close
    call .append_cstr
    mov r12, rax

    cmp qword [rbx + log_record_t.fields_ptr], 0
    je .no_fields

    mov rdi, r12
    mov rsi, .lit_fields
    call .append_cstr
    mov r12, rax

    mov rdi, [rbx + log_record_t.fields_ptr]
    call .render_fields_obj
    mov r12, rax

.no_fields:
    mov rdi, r12
    mov rsi, .lit_close
    call .append_cstr
    mov r12, rax

    mov rax, r12
    sub rax, r13                     ; bytes written = final cursor - original start

    pop r13
    pop r12
    pop rbx
    ret

; ---- .render_fields_obj: RDI = fields buffer -> RAX = new cursor ----------
; (cursor comes in via the caller's R12, threaded the same way as above)
.render_fields_obj:
    push rbx
    push r13
    push r14

    mov r13, rdi                     ; fields buffer
    mov r14, r12                     ; cursor

    mov rdi, r14
    mov rsi, .lit_obj_open
    call .append_cstr
    mov r14, rax

    xor rbx, rbx
.f_loop:
    mov rdi, r13
    call fields_decode_count
    cmp rbx, rax
    jae .f_done

    test rbx, rbx
    jz .f_no_comma
    mov rdi, r14
    mov rsi, .lit_comma
    call .append_cstr
    mov r14, rax
.f_no_comma:
    mov rdi, r13
    mov rsi, rbx
    call fields_decode_get           ; RAX = field_entry_t*
    push rax

    mov rdi, r14
    mov rsi, .lit_quote
    call .append_cstr
    mov r14, rax

    pop rax
    push rax
    mov rdi, r14
    mov rsi, [rax + field_entry_t.key_ptr]
    call .append_cstr
    mov r14, rax

    mov rdi, r14
    mov rsi, .lit_quote_colon
    call .append_cstr
    mov r14, rax

    pop rax
    movzx ecx, byte [rax + field_entry_t.val_type]
    cmp ecx, FIELD_TYPE_STR
    je .f_str
    mov rsi, [rax + field_entry_t.val]
    mov rdi, r14
    call .append_udec
    mov r14, rax
    jmp .f_next
.f_str:
    push rax
    mov rdi, r14
    mov rsi, .lit_quote
    call .append_cstr
    mov r14, rax
    pop rax
    mov rdi, r14
    mov rsi, [rax + field_entry_t.val]
    call .append_cstr
    mov r14, rax
    mov rdi, r14
    mov rsi, .lit_quote
    call .append_cstr
    mov r14, rax

.f_next:
    inc rbx
    jmp .f_loop

.f_done:
    mov rdi, r14
    mov rsi, .lit_obj_close
    call .append_cstr
    mov r14, rax

    mov rax, r14
    pop r14
    pop r13
    pop rbx
    ret

; ---- .append_cstr: RDI = dest cursor, RSI = source cstr -> RAX = new cursor
.append_cstr:
    push rsi
    push rdi
.ac_loop:
    mov al, [rsi]
    test al, al
    jz .ac_done
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .ac_loop
.ac_done:
    mov rax, rdi
    pop rdi
    pop rsi
    ret

; ---- .append_udec: RDI = dest cursor, RSI = value(u64) -> RAX = new cursor
.append_udec:
    push rbx
    push rcx
    push rdx
    push r8
    sub rsp, 24

    mov rax, rsi
    lea r8, [rsp + 23]
    test rax, rax
    jnz .au_loop
    dec r8
    mov byte [r8], '0'
    jmp .au_copy

.au_loop:
    test rax, rax
    jz .au_copy
    xor rdx, rdx
    mov rbx, 10
    div rbx
    add dl, '0'
    dec r8
    mov [r8], dl
    jmp .au_loop

.au_copy:
    lea rcx, [rsp + 23]
.au_copy_loop:
    cmp r8, rcx
    jae .au_done
    mov al, [r8]
    mov [rdi], al
    inc rdi
    inc r8
    jmp .au_copy_loop

.au_done:
    add rsp, 24
    mov rax, rdi
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

section .rodata
.lit_open_seq:   db '{"seq":', 0
.lit_level:      db ',"level":', 0
.lit_module:     db ',"module":', 0
.lit_msg:        db ',"msg":"', 0
.lit_msg_close:  db '"', 0
.lit_fields:     db ',"fields":', 0
.lit_close:      db '}', 10, 0
.lit_obj_open:   db '{', 0
.lit_obj_close:  db '}', 0
.lit_comma:      db ',', 0
.lit_quote:      db '"', 0
.lit_quote_colon: db '":', 0

%endif ; LIB_ULOG_FORMAT_JSON_RENDER_ASM
