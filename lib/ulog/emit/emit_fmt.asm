; =============================================================================
; Tattva OS — lib/ulog/emit/emit_fmt.asm
; =============================================================================
; The single-field convenience path. Tattva's structured logger takes a
; static message plus key/value fields, not a printf format string — that's
; deliberate (a `%d`-interpolated message is unqueryable text; a message plus
; a field is greppable and, once obs/utrace exists, indexable). The
; overwhelming common case is "one value attached to one message," so this
; exists to make that case a single call instead of the full
; emit_varargs.asm BEGIN/ADD/EMIT/END ceremony.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_EMIT_EMIT_FMT_ASM
%define LIB_ULOG_EMIT_EMIT_FMT_ASM

[BITS 64]

%include "lib/ulog/context/fields_schema.inc"

section .text

; -----------------------------------------------------------------------------
; emit_kv1 — log one message with exactly one attached field
; Input:  RDI = level, RSI = module_id, RDX = msg_ptr, RCX = key_ptr,
;         R8B = val_type (FIELD_TYPE_*), R9 = val (int64, or a pointer for
;         FIELD_TYPE_STR)
; Output: none
; -----------------------------------------------------------------------------
global emit_kv1
emit_kv1:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                     ; level
    mov r12, rsi                      ; module_id
    mov r13, rdx                        ; msg_ptr
    mov r14, rcx                          ; key_ptr
    mov r15, r9                             ; val
                                      ; r8b (val_type) is untouched by
                                      ; fields_encode_init below, so it's
                                      ; still valid when we need it

    sub rsp, (fields_blob_hdr_t_size + FIELD_ENTRY_SIZE)
    mov rdi, rsp
    call fields_encode_init

    mov rdi, rsp
    mov rsi, r14
    mov dl, r8b
    mov rcx, r15
    call fields_encode_add

    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rsp
    mov r8, 1
    call emit_async

    add rsp, (fields_blob_hdr_t_size + FIELD_ENTRY_SIZE)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_EMIT_EMIT_FMT_ASM
