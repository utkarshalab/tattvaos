; ============================================================================
; Blend SSE2 — 4 pixels per iteration using PMADDUBSW
; ============================================================================

%include "ugfx.inc"

extern blend_scalar

section .text

global blend_sse2
blend_sse2:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, 3
    jz .aligned
    call blend_scalar
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.aligned:
    test r13, r13
    jz .done
    test r14, r14
    jz .done

.row_loop:
    push r14
    push rbx
    push r12
    mov r14, r13
    shr r14, 2

.pixel_loop:
    ; Load 4 src pixels
    movdqu xmm0, [r12]
    ; Load 4 dst pixels
    movdqu xmm1, [rbx]

    ; Unpack src to words (B G R A x4)
    movdqa xmm2, xmm0
    punpcklbw xmm0, [zero]
    punpckhbw xmm2, [zero]

    ; Unpack dst to words
    movdqa xmm3, xmm1
    punpcklbw xmm1, [zero]
    punpckhbw xmm3, [zero]

    ; Extract alpha from src (high byte of each word)
    movdqa xmm4, xmm0
    movdqa xmm5, xmm2
    psrlw xmm4, 8
    psrlw xmm5, 8

    ; 255 - src_alpha
    movdqa xmm6, [alpha_255]
    psubw xmm6, xmm4
    movdqa xmm7, [alpha_255]
    psubw xmm7, xmm5

    ; dst * (255 - src_alpha) >> 8
    pmullw xmm1, xmm6
    pmullw xmm3, xmm7
    psrlw xmm1, 8
    psrlw xmm3, 8

    ; src + dst_part
    paddusw xmm0, xmm1
    paddusw xmm2, xmm3

    ; Pack back to bytes
    packuswb xmm0, xmm2
    movdqu [rbx], xmm0

    add rbx, 16
    add r12, 16
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

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .rodata
align 16
zero:          dq 0, 0
alpha_255:     dw 255, 255, 255, 255, 255, 255, 255, 255

global blend_sse2_version
blend_sse2_version: dq 0x010000
