; =============================================================================
; Tattva OS — lib/ulog/context/fields_decode.asm
; =============================================================================
; Reads a fields blob back out — format/json_render.asm and format/
; text_render.asm are the callers, walking every entry to print it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_FIELDS_DECODE_ASM
%define LIB_ULOG_CONTEXT_FIELDS_DECODE_ASM

[BITS 64]

%include "lib/ulog/context/fields_schema.inc"

section .text

; -----------------------------------------------------------------------------
; fields_decode_count — Input: RDI = buffer -> Output: RAX = entry count
; -----------------------------------------------------------------------------
global fields_decode_count
fields_decode_count:
    mov rax, [rdi + fields_blob_hdr_t.count]
    ret

; -----------------------------------------------------------------------------
; fields_decode_get — Input: RDI = buffer, RSI = index
; Output: RAX = field_entry_t* (0 if index out of range)
; -----------------------------------------------------------------------------
global fields_decode_get
fields_decode_get:
    mov rax, [rdi + fields_blob_hdr_t.count]
    cmp rsi, rax
    jae .out_of_range

    mov rax, rsi
    imul rax, rax, FIELD_ENTRY_SIZE
    add rax, fields_blob_hdr_t_size
    add rax, rdi
    ret

.out_of_range:
    xor rax, rax
    ret

%endif ; LIB_ULOG_CONTEXT_FIELDS_DECODE_ASM
