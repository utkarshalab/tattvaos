; =============================================================================
; Tattva OS — lib/ulog/record/record_decode.asm
; =============================================================================
; Inverse of record_encode.asm, and the integrity check integrity/
; record_verify.asm calls into: decoding a record also validates it, since
; the checksum recomputation is the whole reason decode and verify are one
; pass instead of two.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_DECODE_ASM
%define LIB_ULOG_RECORD_RECORD_DECODE_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; record_decode — copy an encoded header back into a scratch log_record_t
; and verify its checksum. Does not recover the fields blob — callers that
; need fields read them directly from the encoded buffer at offset
; LOG_RECORD_SIZE, sized via record_encode's return value convention.
; Input:  RDI = encoded buffer (source), RSI = log_record_t* (64-byte dest)
; Output: RAX = 1 checksum ok, 0 checksum mismatch (record is suspect)
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global record_decode
record_decode:
    push rbx
    push rsi
    push rdi

    mov rbx, rsi                     ; RBX = dest, survives the checksum call below

    mov rsi, rdi
    mov rdi, rbx
    mov rcx, LOG_RECORD_SIZE / 8
    cld
    rep movsq

    mov rdi, rbx
    call record_checksum_compute
    mov ecx, [rbx + log_record_t.checksum]
    cmp eax, ecx
    jne .bad

    mov rax, 1
    jmp .done

.bad:
    xor rax, rax

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RECORD_DECODE_ASM
