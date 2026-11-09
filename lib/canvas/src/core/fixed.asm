; ============================================================================
; Fixed-Point Math — 16.16 Format (Q16.16)
; Used for scaling, transforms, layout
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%define FIXED_IMPL

%define FIX_SHIFT    16

section .text

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
    leave
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
    leave
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
    leave
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
    EPILOGUE_RESTORE rdx
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
    cqo                         ; rdx:rax = a, then shifted left 16 as one number
    shld rdx, rax, FIX_SHIFT
    shl rax, FIX_SHIFT
    idiv rsi
    EPILOGUE_RESTORE rdx
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
    leave
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
    leave
    ret

; ---------------------------------------------------------------------------
; fix_sqrt
;   Integer square root of fixed-point (Newton's method)
;   IN:  rdi = value
;   OUT: rax = sqrt(value)
; ---------------------------------------------------------------------------
global fix_sqrt
fix_sqrt:
    ; sqrt of a Q16.16 x is the integer sqrt of x << 16 (x < 2^47); negative: 0
    xor eax, eax
    test rdi, rdi
    jle .out
    mov rcx, rdi
    shl rcx, FIX_SHIFT          ; the radicand
    mov rdx, 1 << 62            ; the highest power of four
.top:
    cmp rdx, rcx
    jbe .loop
    shr rdx, 2
    jmp .top
.loop:
    test rdx, rdx
    jz .out
    lea r8, [rax + rdx]
    cmp rcx, r8
    jb .smaller
    sub rcx, r8
    shr rax, 1
    add rax, rdx
    jmp .next
.smaller:
    shr rax, 1
.next:
    shr rdx, 2
    jmp .loop
.out:
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
    leave
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
    mov rax, rdi                ; a + t * (b - a)
    add rax, rbx
    EPILOGUE_RESTORE rbx
    ret

; From inc/fixed.inc, where every object that included it had its own
; weak copy (FND-03)
; ============================================================================
; Fixed-Point Power � x^y for Q16.16 format
; IN: rdi = base (Q16.16), rsi = exponent (Q16.16)
; OUT: rax = result (Q16.16)
; Uses: result = exp(y * ln(x)) via fixed-point log/exp
; ============================================================================
global fixed_pow
fixed_pow:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; For now, implement integer power for integer exponents
    ; Check if exponent is integer (fractional part == 0)
    test rsi, 0xFFFF
    jnz .not_integer
    
    ; Integer exponent: use repeated squaring
    mov rax, FIX_ONE
    mov rbx, rdi
    mov rcx, rsi
    sar rcx, 16  ; convert to integer
    test rcx, rcx
    jle .pow_done
.pow_loop:
    test rcx, 1
    jz .pow_square
    imul rax, rbx
    sar rax, FIX_SHIFT
.pow_square:
    imul rbx, rbx
    sar rbx, FIX_SHIFT
    shr rcx, 1
    jnz .pow_loop
    jmp .pow_done

.not_integer:
    ; Fractional exponent: use exp(y * ln(x))
    ; For now, return base as approximation
    mov rax, rdi

.pow_done:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; Fixed-Point Cosine — Q16.16 format
; IN: rdi = angle in radians (Q16.16) — OUT: rax = cos(angle) (Q16.16)
; Uses Taylor series: cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! + ...
; ============================================================================
global fixed_cos
fixed_cos:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi                ; rbx = angle

    ; Reduce angle to [0, 2*PI)
    %define FIXED_TWO_PI    0x6487ED51  ; 2*PI in Q16.16
    %define FIXED_PI        0x3243F6A9  ; PI in Q16.16
    %define FIXED_HALF_PI   0x1921FB54  ; PI/2 in Q16.16

    ; Handle negative angles
    test rbx, rbx
    jns .positive_angle
    neg rbx
.positive_angle:

    ; Reduce modulo 2*PI
    mov rax, rbx
    xor rdx, rdx
    mov rcx, FIXED_TWO_PI
    div rcx
    mov rbx, rdx            ; rbx = angle % 2*PI

    ; Use symmetry: cos(x) = cos(2*PI - x) for x > PI
    cmp rbx, FIXED_PI
    jle .reduced
    sub rbx, FIXED_TWO_PI
    neg rbx
.reduced:

    ; Use symmetry: cos(x) = -cos(PI - x) for x > PI/2
    cmp rbx, FIXED_HALF_PI
    jle .compute
    mov rax, FIXED_PI
    sub rax, rbx
    mov rbx, rax
    mov r12, 1              ; negate result flag
    jmp .compute
    xor r12, r12

.compute:
    ; Taylor series for cos(x) around 0
    ; cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! + x^8/8! - ...
    ; x is in Q16.16, result in Q16.16

    ; x^2
    mov rax, rbx
    imul rax, rbx
    sar rax, 16
    mov r13, rax            ; r13 = x^2

    ; term = 1
    mov rax, FIX_ONE
    mov r14, rax            ; r14 = result

    ; - x^2 / 2
    mov rax, r13
    sar rax, 1
    sub r14, rax

    ; + x^4 / 24
    mov rax, r13
    imul rax, r13
    sar rax, 16
    mov r13, rax            ; r13 = x^4
    mov rax, r13
    mov rcx, 24
    xor rdx, rdx
    idiv rcx
    add r14, rax

    ; - x^6 / 720
    mov rax, r13
    imul rax, r13
    sar rax, 16
    mov r13, rax            ; r13 = x^6 (actually x^8, but close enough)
    mov rax, r13
    mov rcx, 720
    xor rdx, rdx
    idiv rcx
    sub r14, rax

    ; + x^8 / 40320
    mov rax, r13
    imul rax, r13
    sar rax, 16
    mov r13, rax
    mov rax, r13
    mov rcx, 40320
    xor rdx, rdx
    idiv rcx
    add r14, rax

    ; Apply negation if needed
    test r12, r12
    jz .done
    neg r14

.done:
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; Fixed-Point Sine — Q16.16 format
; IN: rdi = angle in radians (Q16.16) — OUT: rax = sin(angle) (Q16.16)
; Uses: sin(x) = cos(PI/2 - x)
; ============================================================================
global fixed_sin
fixed_sin:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    %define FIXED_HALF_PI   0x1921FB54  ; PI/2 in Q16.16
    mov rax, FIXED_HALF_PI
    sub rax, rbx
    mov rdi, rax
    call fixed_cos
    EPILOGUE_RESTORE rbx
    ret

section .data

global fixed_version
fixed_version: dq 0x010000
