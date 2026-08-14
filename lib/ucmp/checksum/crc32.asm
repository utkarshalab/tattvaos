%ifndef GUARD_LIB_UCMP_CHECKSUM_CRC32_ASM
%define GUARD_LIB_UCMP_CHECKSUM_CRC32_ASM
; =============================================================================
; Tattva OS — lib/ucmp/checksum/crc32.asm
; =============================================================================
; Intel SSE4.2 Hardware-Accelerated CRC32 Checksum Engine.
;
; Uses `crc32` hardware instructions (`crc32 rax, rdx`, `crc32 eax, ecx`, etc.)
; for high-throughput checksum calculation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit SSE4.2)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"

section .text

global ucmp_crc32_calc

; -----------------------------------------------------------------------------
; ucmp_crc32_calc
;
; Calculates 32-bit CRC32 over buffer using SSE4.2 hardware.
;
; Inputs:
;   RDI = Initial CRC seed (usually 0xFFFFFFFF)
;   RSI = Pointer to buffer
;   RDX = Length in bytes
;
; Returns:
;   EAX = Final 32-bit CRC32 checksum (XORed with 0xFFFFFFFF)
; -----------------------------------------------------------------------------
align 32
ucmp_crc32_calc:
    mov rax, rdi                    ; RAX = running CRC accumulator

.qword_loop:
    cmp rdx, 8
    jl .dword_loop

    crc32 rax, qword [rsi]
    add rsi, 8
    sub rdx, 8
    jmp .qword_loop

.dword_loop:
    cmp rdx, 4
    jl .byte_loop

    crc32 eax, dword [rsi]
    add rsi, 4
    sub rdx, 4

.byte_loop:
    test rdx, rdx
    jz .done

    movzx ecx, byte [rsi]
    crc32 eax, cl
    inc rsi
    dec rdx
    jnz .byte_loop

.done:
    xor eax, 0xFFFFFFFF             ; Final XOR invert
    ret

%endif ; GUARD_LIB_UCMP_CHECKSUM_CRC32_ASM
