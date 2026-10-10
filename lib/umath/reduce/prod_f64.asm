%ifndef GUARD_LIB_UMATH_REDUCE_PROD_F64_ASM
%define GUARD_LIB_UMATH_REDUCE_PROD_F64_ASM
; =============================================================================
; umath - unified math library
; reduce/prod_f64.asm - product of an array without intermediate overflow
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; A plain running product overflows or underflows long before the final
; result does ([1e200, 1e200, 1e-200, 1e-200] gives Inf or 0 instead of 1).
; Here each factor is split into its IEEE-754 mantissa (+/-[1, 2)) and
; exponent: the running mantissa m is multiplied by the factor's mantissa
; and renormalized to +/-[1, 2) (an exact halving), and the exponents are
; summed in a 64-bit integer E. The result m * 2^E is applied once at the
; end as m * 2^(E>>1) * 2^(E-(E>>1)) (both factors normal, so only the
; last multiply rounds), which overflows to +/-Inf or underflows through
; subnormals to +/-0 exactly when the true product does. Subnormal factors
; are rescaled by 2^54 first. Rounding error is one rounding per factor,
; as for the plain product, plus one more when the result is subnormal
; (the rounded mantissa product is rounded again to fewer bits; measured
; within one subnormal ULP of the correctly rounded product).
;
; Special values: any NaN -> NaN; a zero and an Inf -> NaN; otherwise any
; zero -> +/-0 and any Inf -> +/-Inf, signed by the product of all signs.
; Empty array -> 1.0.
; =============================================================================

bits 64

section .rodata
align 8
prodf64_two54:  dq 18014398509481984.0      ; 2^54, rescales subnormal factors
prodf64_one:    dq 1.0
prodf64_nan:    dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; prodf64_step - fold one factor into the running product
; args:    xmm1 = factor (clobbered)
; state:   xmm0 = mantissa m, r8 = exponent sum E, r9 = saw a zero,
;          r10 = saw an Inf, r11 = sign accumulator (bit 63)
; Jumps to the enclosing function's .nan label on a NaN factor.
; Clobbers rax, rcx, rdx, xmm2.
; -----------------------------------------------------------------------------
%macro prodf64_step 0
    movq    rax, xmm1
    xor     r11, rax            ; sign of the product so far (bit 63)
    mov     rcx, rax
    shr     rcx, 52
    and     ecx, 0x7FF          ; biased exponent
    jz      %%zero_or_sub
    cmp     ecx, 0x7FF
    je      %%inf_or_nan
%%normal:
    lea     r8, [r8 + rcx - 1023]   ; E += unbiased exponent
    mov     rdx, 0x800FFFFFFFFFFFFF
    and     rax, rdx
    mov     rdx, 0x3FF0000000000000
    or      rax, rdx            ; factor mantissa, +/-[1, 2)
    movq    xmm2, rax
    mulsd   xmm0, xmm2          ; |m| in [1, 4)
    movq    rax, xmm0
    bt      rax, 62             ; set when |m| >= 2
    jnc     %%done
    mov     rdx, 0x0010000000000000
    sub     rax, rdx            ; m /= 2, exactly
    movq    xmm0, rax
    inc     r8
    jmp     %%done
%%zero_or_sub:
    mov     rdx, 0x000FFFFFFFFFFFFF
    test    rax, rdx
    jz      %%zero
    mulsd   xmm1, [rel prodf64_two54]   ; subnormal: rescale exactly
    sub     r8, 54
    movq    rax, xmm1
    mov     rcx, rax
    shr     rcx, 52
    and     ecx, 0x7FF
    jmp     %%normal
%%zero:
    mov     r9d, 1
    jmp     %%done
%%inf_or_nan:
    mov     rdx, 0x000FFFFFFFFFFFFF
    test    rax, rdx
    jnz     .nan
    mov     r10d, 1
%%done:
%endmacro

; -----------------------------------------------------------------------------
; prodf64__finish - internal: build the result from the prodf64_step state
; args:    xmm0 = m, r8 = E, r9 = zero flag, r10 = Inf flag, r11 = signs
; returns: xmm0 = product
; Not declared global.
; -----------------------------------------------------------------------------
prodf64__finish:
    mov     rdx, 0x8000000000000000
    and     r11, rdx            ; sign bit of the whole product
    test    r9, r9
    jz      .no_zero
    test    r10, r10
    jnz     .nan                ; 0 * Inf
    movq    xmm0, r11           ; +/-0
    ret
.no_zero:
    test    r10, r10
    jnz     .inf
    cmp     r8, 1024
    jge     .inf                ; |m| * 2^E >= 2^1024
    cmp     r8, -1076
    jle     .zero               ; below half the smallest subnormal
    mov     rax, r8
    sar     rax, 1              ; E1
    mov     rcx, r8
    sub     rcx, rax            ; E2
    add     rax, 1023
    shl     rax, 52
    movq    xmm1, rax
    mulsd   xmm0, xmm1          ; exact: m * 2^E1 is normal
    add     rcx, 1023
    shl     rcx, 52
    movq    xmm1, rcx
    mulsd   xmm0, xmm1          ; the single rounding
    ret
.inf:
    mov     rax, 0x7FF0000000000000
    or      rax, r11
    movq    xmm0, rax
    ret
.zero:
    movq    xmm0, r11
    ret
.nan:
    movsd   xmm0, [rel prodf64_nan]
    ret

; -----------------------------------------------------------------------------
; umath_reduce_prod_f64 - product of an array of doubles
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = product (1.0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_prod_f64
umath_reduce_prod_f64:
    movsd   xmm0, [rel prodf64_one]
    xor     r8d, r8d
    xor     r9d, r9d
    xor     r10d, r10d
    xor     r11d, r11d
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
.loop:
    movsd   xmm1, [rdi]
    prodf64_step
    add     rdi, 8
    dec     rsi
    jnz     .loop
.done:
    jmp     prodf64__finish
.nan:
    movsd   xmm0, [rel prodf64_nan]
    ret

%endif ; GUARD_LIB_UMATH_REDUCE_PROD_F64_ASM
