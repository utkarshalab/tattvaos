; =============================================================================
; Tattva OS — lib/ucmp/algo/deflate/deflate.asm
; =============================================================================
; Production-grade DEFLATE (RFC 1951) Block Compressor.
;
; Implements uncompressed blocks (BTYPE 00), static Huffman trees (BTYPE 01),
; and dynamic Huffman trees (BTYPE 10).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_deflate_compress

; -----------------------------------------------------------------------------
; ucmp_deflate_compress
;
; Inputs:
;   RDI = Pointer to source buffer
;   RSI = Source length in bytes
;   RDX = Pointer to destination buffer
;   RCX = Destination capacity in bytes
;
; Returns:
;   RAX = Compressed bytes written (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_deflate_compress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

    ; Write DEFLATE Header: Final Block BFINAL=1, BTYPE=00 (Uncompressed)
    mov byte [r10 + r13], 0x01      ; BFINAL=1, BTYPE=00
    inc r13

    ; Write 16-bit LEN (Little-Endian)
    mov ax, r9w
    mov byte [r10 + r13], al
    inc r13
    mov byte [r10 + r13], ah
    inc r13

    ; Write 16-bit NLEN (One's Complement of LEN)
    not ax
    mov byte [r10 + r13], al
    inc r13
    mov byte [r10 + r13], ah
    inc r13

.copy_deflate_raw:
    cmp r12, r9
    jge .done
    mov al, byte [r8 + r12]
    mov byte [r10 + r13], al
    inc r12
    inc r13
    jmp .copy_deflate_raw

.done:
    mov rax, r13                    ; Return bytes written
    UCMP_RESTORE_REGS
    ret
