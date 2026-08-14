%ifndef GUARD_LIB_UCMP_ARCH_X86_64_SIMD_SCAN_ASM
%define GUARD_LIB_UCMP_ARCH_X86_64_SIMD_SCAN_ASM
; =============================================================================
; Tattva OS — lib/ucmp/arch/x86_64/simd/scan.asm
; =============================================================================
; AVX2 256-bit Vector Byte Scanner & High-Speed LZ77 Match Finder.
;
; Uses YMM vector registers (`vmovdqu`, `vpcmpeqb`, `vpmovmskb`) to scan 32
; bytes in parallel for maximum LZ77 match length discovery.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit AVX2)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_avx2_scan_match_length

; -----------------------------------------------------------------------------
; ucmp_avx2_scan_match_length
;
; Compares two byte streams 32 bytes at a time using AVX2 SIMD.
;
; Inputs:
;   RDI = Pointer to Buffer 1 (Reference stream)
;   RSI = Pointer to Buffer 2 (Match stream)
;   RDX = Max scan length in bytes
;
; Returns:
;   RAX = Total matching bytes count
; -----------------------------------------------------------------------------
align 32
ucmp_avx2_scan_match_length:
    push rbx
    xor rax, rax                    ; Total matched length counter = 0

.avx2_loop:
    cmp rdx, 32
    jl .scalar_tail

    ; Load 32 bytes from both buffers into YMM registers
    vmovdqu ymm0, [rdi + rax]
    vmovdqu ymm1, [rsi + rax]

    ; Compare 32 bytes in parallel (returns 0xFF for match, 0x00 for mismatch)
    vpcmpeqb ymm2, ymm0, ymm1

    ; Create 32-bit bitmask from byte comparison results
    vpmovmskb ebx, ymm2

    ; Check if all 32 bytes matched (mask == 0xFFFFFFFF)
    cmp ebx, 0xFFFFFFFF
    jne .partial_match_found

    add rax, 32
    sub rdx, 32
    jmp .avx2_loop

.partial_match_found:
    ; Invert bitmask to find first mismatch bit using Bit Scan Forward (BSF)
    not ebx
    bsf ecx, ebx                    ; ECX = index of first non-matching byte
    add rax, rcx
    vzeroall
    pop rbx
    ret

.scalar_tail:
    test rdx, rdx
    jz .done

.scalar_loop:
    mov cl, byte [rdi + rax]
    cmp cl, byte [rsi + rax]
    jne .done
    inc rax
    dec rdx
    jnz .scalar_loop

.done:
    vzeroall
    pop rbx
    ret

%endif ; GUARD_LIB_UCMP_ARCH_X86_64_SIMD_SCAN_ASM
