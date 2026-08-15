; =============================================================================
; Tattva OS — lib/ulog/context/fields_encode.asm
; =============================================================================
; Builds a structured-fields blob into a caller-provided buffer (sized for
; FIELDS_MAX_ENTRIES — no allocation on the hot path here either). emit_fmt.asm
; is the actual caller; this is deliberately just the accumulator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_FIELDS_ENCODE_ASM
%define LIB_ULOG_CONTEXT_FIELDS_ENCODE_ASM

[BITS 64]

%include "lib/ulog/context/fields_schema.inc"

section .text

; -----------------------------------------------------------------------------
; fields_encode_init — zero the count header
; Input:  RDI = buffer
; -----------------------------------------------------------------------------
global fields_encode_init
fields_encode_init:
    mov qword [rdi + fields_blob_hdr_t.count], 0
    ret

; -----------------------------------------------------------------------------
; fields_encode_add — append one entry
; Input:  RDI = buffer, RSI = key_ptr, DL = val_type, RCX = val (int or ptr)
; Output: RAX = 1 ok, 0 if FIELDS_MAX_ENTRIES already reached
; Clobbers: RAX, RCX omitted-safe (RCX is an input, preserved through)
; -----------------------------------------------------------------------------
global fields_encode_add
fields_encode_add:
    push rbx
    push rdi

    mov rax, [rdi + fields_blob_hdr_t.count]
    cmp rax, FIELDS_MAX_ENTRIES
    jae .full

    mov rbx, rax
    imul rbx, rbx, FIELD_ENTRY_SIZE
    add rbx, fields_blob_hdr_t_size
    add rbx, rdi                     ; RBX = &buffer.entries[count]

    mov [rbx + field_entry_t.key_ptr], rsi
    mov [rbx + field_entry_t.val_type], dl
    mov [rbx + field_entry_t.val], rcx

    inc qword [rdi + fields_blob_hdr_t.count]
    mov rax, 1
    jmp .done

.full:
    xor rax, rax

.done:
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fields_encoded_size — total byte size of a self-describing blob
; Input:  RDI = buffer
; Output: RAX = fields_blob_hdr_t_size + count * FIELD_ENTRY_SIZE
; -----------------------------------------------------------------------------
global fields_encoded_size
fields_encoded_size:
    mov rax, [rdi + fields_blob_hdr_t.count]
    imul rax, rax, FIELD_ENTRY_SIZE
    add rax, fields_blob_hdr_t_size
    ret

%endif ; LIB_ULOG_CONTEXT_FIELDS_ENCODE_ASM
