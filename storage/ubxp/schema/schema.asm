%ifndef GUARD_STORAGE_UBXP_SCHEMA_SCHEMA_ASM
%define GUARD_STORAGE_UBXP_SCHEMA_SCHEMA_ASM
; =============================================================================
; Tattva OS — storage/ubxp/schema/schema.asm
; =============================================================================
; UBXP Field Tag Composition & Wire-Type Dispatch.
;
; Implements:
;   - Tag packing and field/wire extraction (`ubxp_tag_make`, `ubxp_tag_*`)
;   - Tagged field emission (`ubxp_write_tag`)
;   - Tag ingest with field and wire type split out (`ubxp_read_tag`)
;
; A tag is `(field_number << 3) | wire_type`, carried as a varint. Keeping the
; wire type inside the tag is what allows a decoder to skip a field number it
; has never heard of: it always knows the value's shape even when it does not
; know the value's meaning.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_tag_make
global ubxp_tag_field
global ubxp_tag_wire
global ubxp_write_tag
global ubxp_read_tag

; -----------------------------------------------------------------------------
; ubxp_tag_make
;
; Inputs:
;   RDI = Field number (1..UBXP_MAX_FIELD_NUMBER)
;   ESI = Wire type (UBXP_WIRE_*)
;
; Returns:
;   RAX = Packed tag, or UBXP_ERR_INVAL for an out-of-range field number
; -----------------------------------------------------------------------------
align 32
ubxp_tag_make:
    test rdi, rdi
    jz .tm_inval                    ; Field number 0 is reserved
    mov rax, UBXP_MAX_FIELD_NUMBER
    cmp rdi, rax
    ja .tm_inval

    mov rax, rdi
    shl rax, 3
    and esi, UBXP_WIRE_MASK
    or rax, rsi
    ret

.tm_inval:
    mov rax, UBXP_ERR_INVAL
    ret

; -----------------------------------------------------------------------------
; ubxp_tag_field
;
; Inputs:
;   RDI = Packed tag
;
; Returns:
;   RAX = Field number
; -----------------------------------------------------------------------------
align 32
ubxp_tag_field:
    mov rax, rdi
    shr rax, 3
    ret

; -----------------------------------------------------------------------------
; ubxp_tag_wire
;
; Inputs:
;   RDI = Packed tag
;
; Returns:
;   RAX = Wire type (UBXP_WIRE_*)
; -----------------------------------------------------------------------------
align 32
ubxp_tag_wire:
    mov rax, rdi
    and rax, UBXP_WIRE_MASK
    ret

; -----------------------------------------------------------------------------
; ubxp_write_tag
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   EDX = Wire type
;
; Returns:
;   RAX = Bytes written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_tag:
    push rbx

    mov rbx, rdi                    ; Cursor
    mov rdi, rsi
    mov esi, edx
    call ubxp_tag_make

    test rax, rax
    js .wt_inval                    ; Bad field number never reaches the buffer

    mov rsi, rax
    mov rdi, rbx
    pop rbx
    jmp ubxp_varint_encode

.wt_inval:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_INVAL
    mov rax, UBXP_ERR_INVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_read_tag
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a 64-bit field-number slot
;   RDX = Pointer to a 64-bit wire-type slot
;
; Returns:
;   RAX = Bytes consumed, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_tag:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 16                     ; Scratch slot for the raw tag

    mov rbx, rdi                    ; Cursor
    mov r12, rsi                    ; Field-number slot
    mov r13, rdx                    ; Wire-type slot

    mov rsi, rsp
    call ubxp_varint_decode
    mov r14, rax

    test rax, rax
    js .rt_return

    mov rcx, [rsp]                  ; Raw tag

    mov rax, rcx
    shr rax, 3
    mov [r12], rax                  ; Field number

    mov rax, rcx
    and rax, UBXP_WIRE_MASK
    mov [r13], rax                  ; Wire type

    mov rax, r14

.rt_return:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UBXP_SCHEMA_SCHEMA_ASM
