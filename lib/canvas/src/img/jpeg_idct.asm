; ============================================================================
; JPEG IDCT — complete scalar 8x8 inverse DCT
; IN: rdi = int16[64] coefficients/output, rsi = uint32[64] quant table or 0
;
; This deliberately favors a small, auditable reference implementation over
; a fragile approximate fast path. Optimized SIMD IDCTs can be checked against
; this implementation bit-for-bit within the JPEG rounding tolerance.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

global jpeg_idct8x8
jpeg_idct8x8:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 256                    ; immutable dequantized int32 coefficients
    mov rbx, rdi
    mov r12, rsi
    lea r10, [rel idct_basis]
    ASSERT_PTR rbx

    xor ecx, ecx
.dequantize:
    movsx eax, word [rbx + rcx * 2]
    test r12, r12
    jz .store_coefficient
    imul eax, [r12 + rcx * 4]
.store_coefficient:
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 64
    jb .dequantize

    xor r13d, r13d                 ; output y
.row:
    xor r14d, r14d                 ; output x
.column:
    xorps xmm0, xmm0               ; accumulator
    xor r15d, r15d                 ; frequency v
.v_loop:
    xor r11d, r11d                 ; frequency u
.u_loop:
    mov eax, r15d
    shl eax, 3
    add eax, r11d
    mov edx, [rsp + rax * 4]
    cvtsi2ss xmm1, edx

    mov eax, r14d
    shl eax, 3
    add eax, r11d
    mulss xmm1, [r10 + rax * 4]

    mov eax, r13d
    shl eax, 3
    add eax, r15d
    mulss xmm1, [r10 + rax * 4]
    addss xmm0, xmm1

    inc r11d
    cmp r11d, 8
    jb .u_loop
    inc r15d
    cmp r15d, 8
    jb .v_loop

    mulss xmm0, [rel idct_quarter]
    addss xmm0, [rel idct_level_shift]
    cvtss2si eax, xmm0
    test eax, eax
    jns .not_negative
    xor eax, eax
.not_negative:
    cmp eax, 255
    jle .in_range
    mov eax, 255
.in_range:
    mov edx, r13d
    shl edx, 3
    add edx, r14d
    mov [rbx + rdx * 2], ax

    inc r14d
    cmp r14d, 8
    jb .column
    inc r13d
    cmp r13d, 8
    jb .row

    add rsp, 256
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .rodata
align 16
idct_quarter:     dd 0.25
idct_level_shift: dd 128.0

; A[x,u] = C(u) * cos((2*x+1)*u*pi/16), C(0)=1/sqrt(2).
idct_basis:
    dd 0.707106781, 0.980785280, 0.923879533, 0.831469612, 0.707106781, 0.555570233, 0.382683432, 0.195090322
    dd 0.707106781, 0.831469612, 0.382683432, -0.195090322, -0.707106781, -0.980785280, -0.923879533, -0.555570233
    dd 0.707106781, 0.555570233, -0.382683432, -0.980785280, -0.707106781, 0.195090322, 0.923879533, 0.831469612
    dd 0.707106781, 0.195090322, -0.923879533, -0.555570233, 0.707106781, 0.831469612, -0.382683432, -0.980785280
    dd 0.707106781, -0.195090322, -0.923879533, 0.555570233, 0.707106781, -0.831469612, -0.382683432, 0.980785280
    dd 0.707106781, -0.555570233, -0.382683432, 0.980785280, -0.707106781, -0.195090322, 0.923879533, -0.831469612
    dd 0.707106781, -0.831469612, 0.382683432, 0.195090322, -0.707106781, 0.980785280, -0.923879533, 0.555570233
    dd 0.707106781, -0.980785280, 0.923879533, -0.831469612, 0.707106781, -0.555570233, 0.382683432, -0.195090322

section .data
global jpeg_idct_version
jpeg_idct_version: dq 0x020000
