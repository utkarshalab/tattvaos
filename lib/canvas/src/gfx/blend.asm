; ============================================================================
; Blend — Premultiplied Alpha Compositing (Scalar + SIMD)
; Core hot path: dst = src + dst * (1 - src_a)
; Formats: 32-bit BGRA premultiplied
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; blend_scalar
;   Scalar premultiplied alpha blend
;   IN:  rdi = dst (u32*), rsi = src (u32*), rdx = width, rcx = height, r8 = stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global blend_scalar
blend_scalar:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jz .done
    test r14, r14
    jz .done

.row_loop:
    push r14
    push rbx
    push r12
    mov r14, r13

.pixel_loop:
    mov eax, [r12]
    mov edx, eax
    shr edx, 24
    test edx, edx
    jz .skip_blend

    cmp edx, 255
    je .opaque_blend

    mov ecx, [rbx]
    ; Blue
    mov r8d, eax
    and r8d, 0xFF
    mov r9d, ecx
    and r9d, 0xFF
    mov r10d, 255
    sub r10d, edx
    imul r9d, r10d
    shr r9d, 8
    add r8d, r9d
    cmp r8d, 255
    cmovg r8d, 255

    ; Green
    mov r9d, eax
    shr r9d, 8
    and r9d, 0xFF
    mov r10d, ecx
    shr r10d, 8
    and r10d, 0xFF
    imul r10d, r10d
    shr r10d, 8
    add r9d, r10d
    cmp r9d, 255
    cmovg r9d, 255

    ; Red
    mov r10d, eax
    shr r10d, 16
    and r10d, 0xFF
    mov r11d, ecx
    shr r11d, 16
    and r11d, 0xFF
    imul r11d, r11d
    shr r11d, 8
    add r10d, r11d
    cmp r10d, 255
    cmovg r10d, 255

    ; Alpha
    mov r11d, ecx
    shr r11d, 24
    sub r11d, edx
    imul r11d, r11d
    shr r11d, 8
    add edx, r11d
    cmp edx, 255
    cmovg edx, 255

    shl edx, 24
    shl r10d, 16
    shl r9d, 8
    or edx, r10d
    or edx, r9d
    or edx, r8d
    mov [rbx], edx
    jmp .next_pixel

.opaque_blend:
    mov [rbx], eax
    jmp .next_pixel

.skip_blend:
    jmp .next_pixel

.next_pixel:
    add rbx, 4
    add r12, 4
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

; ---------------------------------------------------------------------------
; blend_dispatch
;   Runtime CPU dispatch (patched at startup)
; ---------------------------------------------------------------------------
global blend_dispatch
blend_dispatch:
    jmp blend_scalar

section .data

global blend_version
blend_version: dq 0x010000