; ============================================================================
; Blend AVX-512 — 16 pixels per iteration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

global blend_avx512
blend_avx512:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, 15
    jz .aligned
    call blend_avx2
    ret

.aligned:
    test r13, r13
    jz .done
    test r14, r14
    jz .done

    vzeroupper

.row_loop:
    push r14
    push rbx
    push r12
    mov r14, r13
    shr r14, 4

.pixel_loop:
    ; Load 16 src pixels
    vmovdqu64 zmm0, [r12]
    ; Load 16 dst pixels
    vmovdqu64 zmm1, [rbx]

    ; AVX-512 blend using VPMADDUBSW with mask registers
    ; Simplified - falls back to AVX2 for now
    call blend_avx2_fallback
    jmp .next_chunk

next_chunk:
    add rbx, 64
    add r12, 64
    dec r14
    jnz .pixel_loop

    pop r12
    pop rbx
    pop r14
    add rbx, r15
    sub rbx, r13
    shl r13, 2
    add r12, r13
    sub r12, r13
    dec r14
    jnz .row_loop

    vzeroupper

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

blend_avx2_fallback:
    ; Process 8 pixels at a time using AVX2
    vmovdqu ymm0, [r12]
    vmovdqu ymm1, [r12 + 32]
    vmovdqu ymm2, [rbx]
    vmovdqu ymm3, [rbx + 32]
    call blend_avx2_core
    vmovdqu [rbx], ymm0
    vmovdqu [rbx + 32], ymm2
    ret

blend_avx2_core:
    ; Core AVX2 blend logic (from blend_avx2.asm)
    vpunpcklbw ymm4, ymm0, [zero]
    vpunpckhbw ymm0, ymm0, [zero]
    vpunpcklbw ymm5, ymm2, [zero]
    vpunpckhbw ymm2, ymm2, [zero]
    vpunpcklbw ymm6, ymm1, [zero]
    vpunpckhbw ymm1, ymm1, [zero]
    vpunpcklbw ymm7, ymm3, [zero]
    vpunpckhbw ymm3, ymm3, [zero]

    vpsrlw ymm8, ymm4, 8
    vpsrlw ymm9, ymm0, 8
    vpsrlw ymm10, ymm6, 8
    vpsrlw ymm11, ymm2, 8

    vpsubw ymm12, [alpha_255], ymm8
    vpsubw ymm13, [alpha_255], ymm9
    vpsubw ymm14, [alpha_255], ymm10
    vpsubw ymm15, [alpha_255], ymm11

    vpmullw ymm5, ymm5, ymm12
    vpmullw ymm2, ymm2, ymm13
    vpmullw ymm7, ymm7, ymm14
    vpmullw ymm3, ymm3, ymm15

    vpsrlw ymm5, 8
    vpsrlw ymm2, 8
    vpsrlw ymm7, 8
    vpsrlw ymm3, 8

    vpaddusw ymm4, ymm4, ymm5
    vpaddusw ymm0, ymm0, ymm2
    vpaddusw ymm6, ymm6, ymm7
    vpaddusw ymm2, ymm2, ymm3

    vpackuswb ymm0, ymm4, ymm0
    vpackuswb ymm2, ymm6, ymm2
    ret

section .rodata
align 64
zero:          dq 0, 0, 0, 0, 0, 0, 0, 0
alpha_255:     dw 255, 255, 255, 255, 255, 255, 255, 255
                dw 255, 255, 255, 255, 255, 255, 255, 255
                dw 255, 255, 255, 255, 255, 255, 255, 255
                dw 255, 255, 255, 255, 255, 255, 255, 255

global blend_avx512_version
blend_avx512_version: dq 0x010000