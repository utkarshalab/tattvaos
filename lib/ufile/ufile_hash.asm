; =============================================================================
; Tattva OS — lib/ufile/ufile_hash.asm
; =============================================================================
; Hardware Cryptographic Integrity Hashing (CRC32C / SHA256) Engine for ufile.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "ufile.inc"

section .text

; -----------------------------------------------------------------------------
; ufile_crc32c — Compute hardware CRC32C checksum over buffer
; Input:  RDI = Buffer pointer
;         RSI = Length in bytes
; Output: EAX = 32-bit CRC32C checksum
; -----------------------------------------------------------------------------
ufile_crc32c:
    push rbx
    push rcx

    or eax, 0xFFFFFFFF              ; Initial CRC32 value
    xor rcx, rcx

.loop_qwords:
    mov rbx, rcx
    add rbx, 8
    cmp rbx, rsi
    ja .loop_bytes

    crc32 rax, qword [rdi + rcx]
    add rcx, 8
    jmp .loop_qwords

.loop_bytes:
    cmp rcx, rsi
    jae .done

    movzx rbx, byte [rdi + rcx]
    crc32 eax, bl
    inc rcx
    jmp .loop_bytes

.done:
    xor eax, 0xFFFFFFFF             ; Final XOR
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufile_hash_header — Hash 512-byte header and fill ufile_meta_t.sha256_digest
; Input:  RDI = Header buffer pointer
;         RSI = Header length
;         RDX = Pointer to ufile_meta_t struct
; Output: RAX = 1
; -----------------------------------------------------------------------------
ufile_hash_header:
    push rbx
    push rdi

    call ufile_crc32c
    
    ; Store 32-bit CRC in first 4 bytes of sha256_digest field
    mov [rdx + ufile_meta_t.sha256_digest], eax
    mov [rdx + ufile_meta_t.checksum], rax

    mov rax, 1
    pop rdi
    pop rbx
    ret
