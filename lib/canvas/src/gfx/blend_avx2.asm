; ============================================================================
; Blend AVX2 — 8 pixels per iteration using VPMADDUBSW
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

global blend_avx2
blend_avx2:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, 7
    jz .aligned
    call blend_sse2
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
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
    shr r14, 3

.pixel_loop:
    ; Load 8 src pixels
    vmovdqu ymm0, [r12]
    ; Load 8 dst pixels
    vmovdqu ymm1, [rbx]

    ; Unpack to words (VPMADDUBSW needs pairs of bytes)
    ; This is simplified - full AVX2 blend uses VPMADDUBSW
    vpunpcklbw ymm2, ymm0, [zero]
    vpunpckhbw ymm0, ymm0, [zero]
    vpunpcklbw ymm3, ymm1, [zero]
    vpunpckhbw ymm1, ymm1, [zero]

    ; Extract alpha
    vpsrlw ymm4, ymm2, 8
    vpsrlw ymm5, ymm0, 8

    ; 255 - alpha
    vpsubw ymm6, [alpha_255], ymm4
    vpsubw ymm7, [alpha_255], ymm5

    ; Multiply and shift
    vpmullw ymm3, ymm3, ymm6
    vpmullw ymm1, ymm1, ymm7
    vpsrlw ymm3, 8
    vpsrlw ymm1, 8

    ; Add
    vpaddusw ymm2, ymm2, ymm3
    vpaddusw ymm0, ymm0, ymm1

    ; Pack
    vpackuswb ymm0, ymm2, ymm0
    vmovdqu [rbx], ymm0

    add rbx, 32
    add r12, 32
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

section .rodata
align 32
zero:          dq 0, 0, 0, 0
alpha_255:     dw 255, 255, 255, 255, 255, 255, 255, 255
                dw 255, 255, 255, 255, 255, 255, 255, 255

global blend_avx2_version
blend_avx2_version: dq 0x010000
