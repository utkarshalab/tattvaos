; ============================================================================
; Fixed-Point Math — 16.16 Format (Q16.16)
; Used for scaling, transforms, layout
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

%define FIX_SHIFT    16
%define FIX_ONE      (1 << FIX_SHIFT)
%define FIX_MASK     (FIX_ONE - 1)

; ---------------------------------------------------------------------------
; fix_from_int
;   Convert integer to fixed-point
;   IN:  rdi = integer
;   OUT: rax = fixed
; ---------------------------------------------------------------------------
global fix_from_int
fix_from_int:
    PROLOGUE
    mov rax, rdi
    sal rax, FIX_SHIFT
    ret

; ---------------------------------------------------------------------------
; fix_to_int
;   Convert fixed-point to integer (truncate)
;   IN:  rdi = fixed
;   OUT: rax = integer
; ---------------------------------------------------------------------------
global fix_to_int
fix_to_int:
    PROLOGUE
    sar rdi, FIX_SHIFT
    mov rax, rdi
    ret

; ---------------------------------------------------------------------------
; fix_to_int_round
;   Convert with rounding
;   IN:  rdi = fixed
;   OUT: rax = integer
; ---------------------------------------------------------------------------
global fix_to_int_round
fix_to_int_round:
    PROLOGUE
    mov rax, rdi
    add rax, FIX_ONE / 2
    sar rax, FIX_SHIFT
    ret

; ---------------------------------------------------------------------------
; fix_mul
;   Multiply two fixed-point numbers
;   IN:  rdi = a, rsi = b
;   OUT: rax = a * b
; ---------------------------------------------------------------------------
global fix_mul
fix_mul:
    PROLOGUE_SAVE rdx
    mov rax, rdi
    imul rsi
    shrd rax, rdx, FIX_SHIFT
    ret

; ---------------------------------------------------------------------------
; fix_div
;   Divide two fixed-point numbers
;   IN:  rdi = a, rsi = b
;   OUT: rax = a / b
; ---------------------------------------------------------------------------
global fix_div
fix_div:
    PROLOGUE_SAVE rdx
    mov rax, rdi
    cqo
    sal rax, FIX_SHIFT
    rcl rdx, 1
    idiv rsi
    ret

; ---------------------------------------------------------------------------
; fix_add
;   Add two fixed-point numbers
; ---------------------------------------------------------------------------
global fix_add
fix_add:
    PROLOGUE
    add rdi, rsi
    mov rax, rdi
    ret

; ---------------------------------------------------------------------------
; fix_sub
;   Subtract fixed-point numbers
; ---------------------------------------------------------------------------
global fix_sub
fix_sub:
    PROLOGUE
    sub rdi, rsi
    mov rax, rdi
    ret

; ---------------------------------------------------------------------------
; fix_sqrt
;   Integer square root of fixed-point (Newton's method)
;   IN:  rdi = value
;   OUT: rax = sqrt(value)
; ---------------------------------------------------------------------------
global fix_sqrt
fix_sqrt:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    test rbx, rbx
    jz .zero

    ; Initial guess: value / 2
    mov rax, rbx
    sar rax, 1
    test rax, rax
    jnz .iterate
    mov rax, FIX_ONE

.iterate:
    mov r12, rax
    mov rax, rbx
    cqo
    idiv r12
    add rax, r12
    sar rax, 1
    cmp rax, r12
    jge .check_converge
    mov rax, r12
.check_converge:
    sub rax, r12
    cmp rax, 1
    jg .iterate
    cmp rax, -1
    jl .iterate
    ret

.zero:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; fix_clamp
;   Clamp fixed-point to range
;   IN:  rdi = value, rsi = min, rdx = max
;   OUT: rax = clamped value
; ---------------------------------------------------------------------------
global fix_clamp
fix_clamp:
    PROLOGUE
    mov rax, rdi
    cmp rax, rsi
    cmovl rax, rsi
    cmp rax, rdx
    cmovg rax, rdx
    ret

; ---------------------------------------------------------------------------
; fix_lerp
;   Linear interpolation: a + t * (b - a)
;   IN:  rdi = a, rsi = b, rdx = t (0 to FIX_ONE)
;   OUT: rax = interpolated
; ---------------------------------------------------------------------------
global fix_lerp
fix_lerp:
    PROLOGUE_SAVE rbx
    mov rbx, rsi
    sub rbx, rdi
    imul rbx, rdx
    sar rbx, FIX_SHIFT
    add rax, rbx
    EPILOGUE_RESTORE rbx
    ret

section .data

global fixed_version
fixed_version: dq 0x010000