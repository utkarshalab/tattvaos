; ============================================================================
; Fill — Solid Color Fill (Scalar + SIMD)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/color.inc"

section .text

; ---------------------------------------------------------------------------
; fill_solid
;   Fill rectangle with solid color
;   IN:  rdi = dst (u32*), rsi = color (u32 BGRA), rdx = width, rcx = height, r8 = stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global fill_solid
fill_solid:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    test r13, r13
    jz .done
    test r14, r14
    jz .done

.row_loop:
    push r14
    push rbx
    mov r14, r13

.pixel_loop:
    mov [rbx], r12
    add rbx, 4
    dec r14
    jnz .pixel_loop

    pop rbx
    pop r14
    add rbx, r8
    sub rbx, r13
    shl r13, 2
    add rbx, r13
    sub rbx, r13
    dec r14
    jnz .row_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; fill_solid_sse2
;   SSE2 fill (4 pixels/iter)
; ---------------------------------------------------------------------------
global fill_solid_sse2
fill_solid_sse2:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    test r13, 3
    jz .aligned
    call fill_solid
    ret

.aligned:
    ; Broadcast color to xmm0
    movd xmm0, r12
    pshufd xmm0, xmm0, 0

    test r13, r13
    jz .done
    test r14, r14
    jz .done

.row_loop:
    push r14
    push rbx
    mov r14, r13
    shr r14, 2

.pixel_loop:
    movdqu [rbx], xmm0
    add rbx, 16
    dec r14
    jnz .pixel_loop

    pop rbx
    pop r14
    add rbx, r8
    sub rbx, r13
    shl r13, 2
    add rbx, r13
    sub rbx, r13
    dec r14
    jnz .row_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data

global fill_version
fill_version: dq 0x010000