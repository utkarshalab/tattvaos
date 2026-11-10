; =============================================================================
; File     : src/kernels/scalar/scalar.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Scalar reference kernels — Blake3, chunking, diff.
; =============================================================================

%ifndef VCS_KERNELS_SCALAR_ASM
%define VCS_KERNELS_SCALAR_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; scalar_blake3 — Blake3 hash scalar reference
; Input:  rdi = input, rsi = len, rdx = output (32 bytes)
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global scalar_blake3
scalar_blake3:
    push    rbx
    ; Hashing is provided by lib/crypto/uhash; this legacy entry must not report
    ; success without producing a digest.
    mov     eax, VCS_ERR_UNSUPPORTED
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; scalar_chunk — Content-defined chunking (scalar)
; Input:  rdi = data, rsi = len, rdx = exclusive-end qword bounds,
;         rcx = bounds capacity
; Output: rax = chunk count, -1 for invalid input, -2 for insufficient output
; -----------------------------------------------------------------------------
global scalar_chunk
scalar_chunk:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    test    rsi, rsi
    jz      .empty
    test    rdi, rdi
    jz      .invalid
    test    rdx, rdx
    jz      .invalid
    test    rcx, rcx
    jz      .capacity

    xor     ebx, ebx                  ; rolling hash, reset at each boundary
    xor     r12d, r12d                ; current absolute offset
    xor     r13d, r13d                ; current chunk start
    mov     r14, rdx
    mov     r15, rcx
    mov     r10, 0x9e3779b185ebca87
    xor     eax, eax
.scan:
    movzx   r8d, byte [rdi+r12]
    inc     r8
    imul    r8, r10
    rol     rbx, 1
    xor     rbx, r8
    inc     r12
    cmp     r12, rsi
    je      .cut
    mov     r11, r12
    sub     r11, r13
    cmp     r11, 2048
    jb      .scan
    cmp     r11, 32768
    jae     .cut
    test    rbx, 8191
    jnz     .scan
.cut:
    cmp     rax, r15
    jae     .capacity
    mov     [r14+rax*8], r12
    inc     rax
    mov     r13, r12
    xor     ebx, ebx
    cmp     r12, rsi
    jb      .scan
    jmp     .done
.empty:
    xor     eax, eax
    jmp     .done
.invalid:
    mov     rax, -1
    jmp     .done
.capacity:
    mov     rax, -2
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; scalar_diff — Scalar diff of two buffers
; Input:  rdi = a, rsi = b, rdx = len
; Output: rax = number of differing bytes
; -----------------------------------------------------------------------------
global scalar_diff
scalar_diff:
    push    rbx
    push    rcx
    mov     rbx, rdi
    mov     rcx, rdx
    xor     rax, rax
.diff_loop:
    test    rcx, rcx
    jz      .done
    mov     dl, [rdi]
    cmp     dl, [rsi]
    jne     .found_diff
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .diff_loop
.found_diff:
    inc     rax
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .diff_loop
.done:
    pop     rcx
    pop     rbx
    ret

%endif ; VCS_KERNELS_SCALAR_ASM
