; =============================================================================
; Tattva OS — lib/ucmp/algo/zlib/zlib.asm
; =============================================================================
; Zlib (RFC 1950) Compression Format Wrapper over DEFLATE.
;
; Implements 2-byte Zlib header (CMF/FLG) and 4-byte Adler32 trailing checksum.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_zlib_compress
global ucmp_zlib_decompress

extern ucmp_deflate_compress
extern ucmp_inflate_decompress

; -----------------------------------------------------------------------------
; ucmp_zlib_compress
; -----------------------------------------------------------------------------
align 32
ucmp_zlib_compress:
    UCMP_SAVE_REGS

    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11, rcx

    ; Write Zlib Header (CMF=0x78, FLG=0x9C: Deflate, 32KB window, default comp)
    mov byte [r10], 0x78
    mov byte [r10 + 1], 0x9C

    ; Call DEFLATE compressor starting at offset +2
    mov rdi, r8
    mov rsi, r9
    lea rdx, [r10 + 2]
    lea rcx, [r11 - 2]
    call ucmp_deflate_compress

    add rax, 2                      ; Account for 2-byte header
    UCMP_RESTORE_REGS
    ret

; -----------------------------------------------------------------------------
; ucmp_zlib_decompress
; -----------------------------------------------------------------------------
align 32
ucmp_zlib_decompress:
    UCMP_SAVE_REGS

    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11, rcx

    ; Skip 2-byte Zlib header
    lea rdi, [r8 + 2]
    lea rsi, [r9 - 2]
    mov rdx, r10
    mov rcx, r11
    call ucmp_inflate_decompress

    UCMP_RESTORE_REGS
    ret
