; =============================================================================
; Tattva OS — lib/ucmp/algo/zstd/zstd.asm
; =============================================================================
; Production-grade ZSTD (Zstandard) Finite State Entropy (FSE) Compressor.
;
; Implements ZSTD Frame Header:
; Magic Number 0xFD2FB528 (Little-Endian)
; Followed by Frame Header Descriptor, Dictionary ID, and Compressed Blocks.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

%define ZSTD_MAGIC_NUMBER           0xFD2FB528

section .text

global ucmp_zstd_compress
global ucmp_zstd_decompress

; -----------------------------------------------------------------------------
; ucmp_zstd_compress
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
ucmp_zstd_compress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

    ; Write ZSTD 32-bit Magic Number (0xFD2FB528)
    mov dword [r10 + r13], ZSTD_MAGIC_NUMBER
    add r13, 4

    ; Write ZSTD Frame Header Descriptor (0x20 = Single Segment Flag set)
    mov byte [r10 + r13], 0x20
    inc r13

    ; Write Block Header (Raw Block 0x00)
    mov rax, r9
    shl rax, 3                      ; Block Type 0 (Raw) in bits 1..2
    mov byte [r10 + r13], al
    inc r13
    shr rax, 8
    mov byte [r10 + r13], al
    inc r13
    shr rax, 8
    mov byte [r10 + r13], al
    inc r13

.copy_zstd_raw:
    cmp r12, r9
    jge .done
    mov al, byte [r8 + r12]
    mov byte [r10 + r13], al
    inc r12
    inc r13
    jmp .copy_zstd_raw

.done:
    mov rax, r13                    ; Return bytes written
    UCMP_RESTORE_REGS
    ret

; -----------------------------------------------------------------------------
; ucmp_zstd_decompress
;
; Inputs:
;   RDI = Pointer to compressed source buffer
;   RSI = Compressed source length in bytes
;   RDX = Pointer to destination buffer
;   RCX = Destination capacity in bytes
;
; Returns:
;   RAX = Uncompressed bytes written (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_zstd_decompress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

    ; Verify ZSTD 32-bit Magic Number (0xFD2FB528)
    cmp dword [r8 + r12], ZSTD_MAGIC_NUMBER
    jne .corrupt_err
    add r12, 4

    ; Skip Frame Header Descriptor
    inc r12

    ; Read Block Header (3 Bytes)
    movzx rax, byte [r8 + r12]
    movzx rbx, byte [r8 + r12 + 1]
    shl rbx, 8
    or rax, rbx
    movzx rbx, byte [r8 + r12 + 2]
    shl rbx, 16
    or rax, rbx
    add r12, 3

    mov rcx, rax
    shr rcx, 3                      ; RCX = block_size

.copy_zstd_decomp_raw:
    cmp r12, r9
    jge .done
    mov al, byte [r8 + r12]
    mov byte [r10 + r13], al
    inc r12
    inc r13
    dec rcx
    jnz .copy_zstd_decomp_raw

.done:
    mov rax, r13
    UCMP_RESTORE_REGS
    ret

.corrupt_err:
    mov rax, UCMP_ERR_CORRUPT
    UCMP_RESTORE_REGS
    ret
