%ifndef GUARD_LIB_UCMP_ALGO_GZIP_GZIP_ASM
%define GUARD_LIB_UCMP_ALGO_GZIP_GZIP_ASM
; =============================================================================
; Tattva OS — lib/ucmp/algo/gzip/gzip.asm
; =============================================================================
; Gzip (RFC 1952) Compression Format Wrapper over DEFLATE.
;
; Implements 10-byte Gzip magic header (0x1F, 0x8B) and 8-byte trailing footer
; (32-bit CRC32 checksum + 32-bit ISIZE original length).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_gzip_compress
global ucmp_gzip_decompress


; -----------------------------------------------------------------------------
; ucmp_gzip_compress
; -----------------------------------------------------------------------------
align 32
ucmp_gzip_compress:
    UCMP_SAVE_REGS

    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11, rcx

    ; Write 10-byte Gzip Header (ID1=0x1F, ID2=0x8B, CM=8, FLG=0, MTIME=0, XFL=0, OS=3)
    mov byte [r10 + 0], 0x1F
    mov byte [r10 + 1], 0x8B
    mov byte [r10 + 2], 0x08        ; CM=8 (Deflate)
    mov byte [r10 + 3], 0x00        ; FLG=0
    mov dword [r10 + 4], 0          ; MTIME=0
    mov byte [r10 + 8], 0           ; XFL=0
    mov byte [r10 + 9], 3           ; OS=3 (Unix)

    ; Call DEFLATE compressor starting at offset +10
    mov rdi, r8
    mov rsi, r9
    lea rdx, [r10 + 10]
    lea rcx, [r11 - 18]
    call ucmp_deflate_compress
    mov r12, rax                    ; R12 = deflate_bytes

    ; Calculate CRC32 over original source
    mov rdi, 0xFFFFFFFF
    mov rsi, r8
    mov rdx, r9
    call ucmp_crc32_calc

    ; Write 8-byte Gzip Footer [CRC32 (4 bytes) | ISIZE (4 bytes)]
    lea r13, [r10 + 10 + r12]
    mov dword [r13], eax            ; 32-bit CRC32 checksum
    mov dword [r13 + 4], r9d        ; 32-bit original ISIZE

    lea rax, [r12 + 18]             ; Total gzip bytes written (10 header + payload + 8 footer)
    UCMP_RESTORE_REGS
    ret

; -----------------------------------------------------------------------------
; ucmp_gzip_decompress
; -----------------------------------------------------------------------------
align 32
ucmp_gzip_decompress:
    UCMP_SAVE_REGS

    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11, rcx

    ; Verify Gzip Magic ID1=0x1F, ID2=0x8B
    cmp byte [r8 + 0], 0x1F
    jne .corrupt_err
    cmp byte [r8 + 1], 0x8B
    jne .corrupt_err

    ; Skip 10-byte Gzip header
    lea rdi, [r8 + 10]
    lea rsi, [r9 - 18]
    mov rdx, r10
    mov rcx, r11
    call ucmp_inflate_decompress

    UCMP_RESTORE_REGS
    ret

.corrupt_err:
    mov rax, UCMP_ERR_HEADER_INVALID
    UCMP_RESTORE_REGS
    ret

%endif ; GUARD_LIB_UCMP_ALGO_GZIP_GZIP_ASM
