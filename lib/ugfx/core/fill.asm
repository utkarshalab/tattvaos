; ============================================================================
; Fill — Solid Color Fill (Scalar + SIMD)
; ============================================================================

%include "ugfx.inc"

section .text

; ---------------------------------------------------------------------------
; fill_solid
;   Fill rectangle with solid color
;   IN:  rdi = dst (u32*), rsi = color (u32 BGRA), rdx = width, rcx = height, r8 = stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global fill_solid
fill_solid:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rcx                        ; rows left
    ASSERT_PTR rbx
    test rdx, rdx
    jz .done
    test r12, r12
    jz .done
.row_loop:
    mov rdi, rbx
    mov eax, esi
    mov rcx, rdx
    rep stosd                           ; one row of 32-bit pixels
    add rbx, r8
    dec r12
    jnz .row_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fill_solid_sse2
;   SSE2 fill: 4 pixels per store, the row's last width % 4 one at a time
;   IN/OUT: as fill_solid
; ---------------------------------------------------------------------------
global fill_solid_sse2
fill_solid_sse2:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rcx                        ; rows left
    ASSERT_PTR rbx
    test rdx, rdx
    jz .done
    test r12, r12
    jz .done
    movd xmm0, esi
    pshufd xmm0, xmm0, 0                ; the colour four times
.row_loop:
    mov rdi, rbx
    mov rcx, rdx
    shr rcx, 2
    jz .tail
.quad:
    movdqu [rdi], xmm0
    add rdi, 16
    dec rcx
    jnz .quad
.tail:
    mov rcx, rdx
    and rcx, 3
    mov eax, esi
    rep stosd
    add rbx, r8
    dec r12
    jnz .row_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

global fill_version
fill_version: dq 0x010001
