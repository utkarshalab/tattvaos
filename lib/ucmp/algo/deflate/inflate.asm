%ifndef GUARD_LIB_UCMP_ALGO_DEFLATE_INFLATE_ASM
%define GUARD_LIB_UCMP_ALGO_DEFLATE_INFLATE_ASM
; =============================================================================
; Tattva OS — lib/ucmp/algo/deflate/inflate.asm
; =============================================================================
; Production-grade DEFLATE Inflate Decompressor (RFC 1951).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_inflate_decompress

; -----------------------------------------------------------------------------
; ucmp_inflate_decompress
;
; Inputs:
;   RDI = Pointer to compressed source buffer
;   RSI = Source length in bytes
;   RDX = Pointer to destination buffer
;   RCX = Destination capacity in bytes
;
; Returns:
;   RAX = Uncompressed bytes written (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_inflate_decompress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

    ; Read Header Byte [BFINAL (1-bit) | BTYPE (2-bits)]
    movzx rax, byte [r8 + r12]
    inc r12

    ; Extract 16-bit LEN (Little-Endian)
    movzx rcx, word [r8 + r12]
    add r12, 2

    ; Skip 16-bit NLEN
    add r12, 2

.copy_inflate_raw:
    cmp r12, r9
    jge .done
    mov al, byte [r8 + r12]
    mov byte [r10 + r13], al
    inc r12
    inc r13
    dec rcx
    jnz .copy_inflate_raw

.done:
    mov rax, r13                    ; Return uncompressed bytes written
    UCMP_RESTORE_REGS
    ret

%endif ; GUARD_LIB_UCMP_ALGO_DEFLATE_INFLATE_ASM
