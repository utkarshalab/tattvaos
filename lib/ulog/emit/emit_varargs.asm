; =============================================================================
; Tattva OS — lib/ulog/emit/emit_varargs.asm
; =============================================================================
; The register-packing convention for more than one field, since NASM has no
; real varargs. Four macros used as a scoped sequence:
;
;   LOG_FIELDS_BEGIN
;   LOG_FIELD_INT key_fiber_id, rax
;   LOG_FIELD_STR key_reason, msg_corrupt_journal
;   LOG_FIELDS_EMIT LVL_ERROR, MOD_STORAGE_UXFS, msg_replay_failed
;   LOG_FIELDS_END
;
; R11 is the convention's dedicated scratch register for the blob's base
; address across the sequence — chosen because nothing else in emit/ or
; record/ treats R11 as meaningful, so BEGIN/ADD/EMIT/END can share it without
; colliding with any function's real argument registers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_EMIT_EMIT_VARARGS_ASM
%define LIB_ULOG_EMIT_EMIT_VARARGS_ASM

%include "lib/ulog/context/fields_schema.inc"

%define LOG_FIELDS_BLOB_BYTES  (fields_blob_hdr_t_size + FIELDS_MAX_ENTRIES * FIELD_ENTRY_SIZE)

; -----------------------------------------------------------------------------
%macro LOG_FIELDS_BEGIN 0
    sub rsp, LOG_FIELDS_BLOB_BYTES
    mov r11, rsp
    push rdi
    mov rdi, r11
    call fields_encode_init
    pop rdi
%endmacro

; -----------------------------------------------------------------------------
%macro LOG_FIELD_INT 2                 ; key_ptr, int64 value
    push rdi
    push rsi
    push rdx
    push rcx
    mov rdi, r11
    mov rsi, %1
    mov dl, FIELD_TYPE_INT
    mov rcx, %2
    call fields_encode_add
    pop rcx
    pop rdx
    pop rsi
    pop rdi
%endmacro

; -----------------------------------------------------------------------------
%macro LOG_FIELD_STR 2                 ; key_ptr, string value ptr
    push rdi
    push rsi
    push rdx
    push rcx
    mov rdi, r11
    mov rsi, %1
    mov dl, FIELD_TYPE_STR
    mov rcx, %2
    call fields_encode_add
    pop rcx
    pop rdx
    pop rsi
    pop rdi
%endmacro

; -----------------------------------------------------------------------------
%macro LOG_FIELD_HEX 2                 ; key_ptr, uint64 value, rendered as hex
    push rdi
    push rsi
    push rdx
    push rcx
    mov rdi, r11
    mov rsi, %1
    mov dl, FIELD_TYPE_HEX
    mov rcx, %2
    call fields_encode_add
    pop rcx
    pop rdx
    pop rsi
    pop rdi
%endmacro

; -----------------------------------------------------------------------------
%macro LOG_FIELDS_EMIT 3               ; level, module_id, msg_ptr
    mov r8, [r11 + fields_blob_hdr_t.count]
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    mov rcx, r11
    call emit_async
%endmacro

; -----------------------------------------------------------------------------
%macro LOG_FIELDS_END 0
    add rsp, LOG_FIELDS_BLOB_BYTES
%endmacro

%endif ; LIB_ULOG_EMIT_EMIT_VARARGS_ASM
