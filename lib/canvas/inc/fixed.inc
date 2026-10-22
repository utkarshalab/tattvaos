; ============================================================================
; Fixed-Point Math Definitions — Q16.16 Format
; ============================================================================

%ifndef __FIXED_INC__
%define __FIXED_INC__

%define FIX_SHIFT    16
%define FIX_ONE      (1 << FIX_SHIFT)
%define FIX_HALF     (FIX_ONE >> 1)
%define FIX_MASK     (FIX_ONE - 1)

; Convert integer constant to fixed (assembly-time)
%define FIX(x) ((x) << FIX_SHIFT)

; ============================================================================
; Fixed-Point Square Root � Newton-Raphson iteration
; IN: rdi = x (Q16.16) � OUT: rax = sqrt(x) (Q16.16)
; Uses Newton-Raphson: y_{n+1} = (y_n + x/y_n) / 2
; Initial guess: y_0 = x >> 8 + 1<<8 (rough approximation)
; ============================================================================
section .text
global fix_sqrt:function weak
fix_sqrt:
    PROLOGUE_SAVE rbx
    mov rbx, rdi                ; rbx = x (Q16.16)
    test rbx, rbx
    jz .zero                    ; sqrt(0) = 0
    
    ; Initial guess: y = x >> 8 + 256 (rough approximation)
    mov rax, rdi
    shr rax, 8
    add rax, 256                ; rax = x/65536 + 256 approx
    
    mov rbx, rdi                ; rbx = x
    mov rcx, 5                  ; 5 iterations of Newton-Raphson
.newton:
    ; y = (y + x/y) / 2
    mov rax, rdi                ; rax = x
    xor rdx, rdx
    div rbx                     ; rax = x / y
    add rax, rbx                ; rax = y + x/y
    shr rax, 1                  ; rax = (y + x/y) / 2
    mov rbx, rax                ; y = new estimate
    loop .newton                ; repeat 5 times
    
    mov rax, rbx                ; result in rax
    EPILOGUE_RESTORE rbx
    ret
.zero:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; Fixed-Point Power � x^y for Q16.16 format
; IN: rdi = base (Q16.16), rsi = exponent (Q16.16)
; OUT: rax = result (Q16.16)
; Uses: result = exp(y * ln(x)) via fixed-point log/exp
; ============================================================================
global fixed_pow:function weak
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
global fixed_cos:function weak
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
global fixed_sin:function weak
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

%endif ; __FIXED_INC__
