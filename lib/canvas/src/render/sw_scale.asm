; ============================================================================
; Software Scale — Nearest and Bilinear (SIMD Optimized)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern scale_bilinear

section .text

; ---------------------------------------------------------------------------
; sw_scale_nearest
;   Nearest neighbor scaling
;   IN:  rdi = dst, rsi = src, rdx = src_w, rcx = src_h, r8 = src_stride
;        r9 = dst_w, r10 = dst_h, r11 = dst_stride
; ---------------------------------------------------------------------------
global sw_scale_nearest
sw_scale_nearest:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Compute scale factors (16.16 fixed point)
    mov rax, r13
    shl rax, 16
    div r9
    mov r13, rax          ; x_scale

    mov rax, r14
    shl rax, 16
    div r10
    mov r14, rax          ; y_scale

    test r9, r9
    jz .done
    test r10, r10
    jz .done

.row_loop:
    push r10
    push rbx
    push r12
    mov r10, r9

    ; Compute src_y
    mov rax, r10
    mul r14
    shr rax, 16
    mov rsi, r12
    imul rax, r15
    add rsi, rax

.pixel_loop:
    ; Compute src_x
    mov rax, r10
    mul r13
    shr rax, 16
    mov ecx, [rsi + rax * 4]
    mov [rbx], ecx
    add rbx, 4
    dec r10
    jnz .pixel_loop

    pop r12
    pop rbx
    pop r10
    add rbx, r11
    sub rbx, r9
    shl r9, 2
    add r12, r9
    sub r12, r9
    dec r10
    jnz .row_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; sw_scale_bilinear
;   Bilinear scaling through the canonical native scalar kernel
; ---------------------------------------------------------------------------
global sw_scale_bilinear
sw_scale_bilinear:
    jmp scale_bilinear

section .data
global sw_scale_version
sw_scale_version: dq 0x010000
