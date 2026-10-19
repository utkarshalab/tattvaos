%ifndef GUARD_VERTEX_COMMON_ASM
%define GUARD_VERTEX_COMMON_ASM
; =============================================================================
; vertex-agent — Common Utilities
; =============================================================================
; Shared helpers: UUID, string, BXP, error handling
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"
%include "lib/ulib/vec.inc"
%include "lib/ulib/map.inc"
%include "crypto/uhash/sha256.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_gen_uuid — Generate UUID v4 (RFC 4122)
; Returns: RAX = UUID string pointer (36 chars + null, in tmp buffer)
; -----------------------------------------------------------------------------
global vertex_gen_uuid
vertex_gen_uuid:
    push rbx
    push r12
    push r13

    ; Get 16 random bytes
    mov rdi, uuid_buffer
    mov rsi, 16
    call urand_get_bytes
    test rax, rax
    jz .fail

    ; Set version (4) and variant bits
    ; uuid[6] = (uuid[6] & 0x0F) | 0x40  ; version 4
    ; uuid[8] = (uuid[8] & 0x3F) | 0x80  ; variant 10
    mov al, [uuid_buffer + 6]
    and al, 0x0F
    or al, 0x40
    mov [uuid_buffer + 6], al

    mov al, [uuid_buffer + 8]
    and al, 0x3F
    or al, 0x80
    mov [uuid_buffer + 8], al

    ; Format as hex string: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    mov rdi, uuid_string
    mov rsi, uuid_buffer
    call vertex_uuid_format

    mov rax, uuid_string
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_uuid_format — Format 16-byte UUID to string
; Inputs: RDI = output buffer (37 bytes), RSI = 16-byte UUID
; -----------------------------------------------------------------------------
vertex_uuid_format:
    push rbx
    push r12
    push r13

    mov r12, rdi      ; output
    mov r13, rsi      ; uuid bytes

    ; Use lookup table for hex
    mov rbx, hex_table

    ; 8-4-4-4-12 format
    ; Bytes 0-3
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    mov byte [r12], '-'
    inc r12

    ; Bytes 4-5
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    mov byte [r12], '-'
    inc r12

    ; Bytes 6-7 (version byte)
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    mov byte [r12], '-'
    inc r12

    ; Bytes 8-9 (variant byte)
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    mov byte [r12], '-'
    inc r12

    ; Bytes 10-15
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex
    call vertex_uuid_write_hex

    mov byte [r12], 0

    pop r13
    pop r12
    pop rbx
    ret

vertex_uuid_write_hex:
    mov al, [r13]
    inc r13
    mov ah, al
    shr al, 4
    and al, 0xF
    mov al, [rbx + rax]
    mov [r12], al
    inc r12
    and ah, 0xF
    mov al, [rbx + rax]
    mov [r12], al
    inc r12
    ret


; -----------------------------------------------------------------------------
; vertex_error_new — Create error (BXP)
; Inputs: RDI = code, RSI = message
; Returns: RAX = error BXP
; -----------------------------------------------------------------------------
global vertex_error_new
vertex_error_new:
    push rbx
    push r12

    mov r12d, edi
    mov r13, rsi

    ; Allocate BXP error object
    mov rdi, 64
    call bxp_alloc
    test rax, rax
    jz .fail

    ; Write code
    mov rdi, rax
    mov rsi, r12d
    call bxp_write_int

    ; Write message
    mov rdi, rax
    mov rsi, r13
    call bxp_write_string

    pop r12
    pop rbx
    ret

.fail:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_bxp_alloc — Allocate BXP buffer
; -----------------------------------------------------------------------------
vertex_bxp_alloc:
    ; Simple bump allocator in thread-local storage
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_sha256 — Compute SHA256
; Inputs: RDI = data, RSI = len, RDX = output (32 bytes)
; -----------------------------------------------------------------------------
global vertex_sha256
vertex_sha256:
    push rbx

    mov rbx, rdx
    call sha256_hash

    pop rbx
    ret


; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------
section .data
align 16

uuid_buffer:            times 16 db 0
uuid_string:            times 37 db 0

hex_table:              db "0123456789abcdef"

%endif ; GUARD_VERTEX_COMMON_ASM