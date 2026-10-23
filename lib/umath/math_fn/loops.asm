%ifndef GUARD_LIB_UMATH_MATH_FN_LOOPS_ASM
%define GUARD_LIB_UMATH_MATH_FN_LOOPS_ASM
; =============================================================================
; umath - unified math library
; math_fn/loops.asm - shared array/inplace loops and f32-through-f64 wrappers
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Macros only, no code of their own. The array loops keep their pointers and
; count in rbx/r12/r13/r14 (callee-saved), so they stay correct whatever the
; scalar routine clobbers -- the bug class described in README.md ("check what
; a callee clobbers before assuming a loop-carried register survives a
; call") cannot occur. Every element is exactly what the scalar call returns.
;
;   mathfn_unary_arrays   name, scalar, width
;       name_array   (rdi = dst, rsi = src, rdx = count)
;       name_inplace (rdi = buf, rsi = count)
;   mathfn_binary_arrays  name, scalar, width
;       name_array   (rdi = dst, rsi = a, rdx = b, rcx = count)
;       dst[i] = scalar(a[i], b[i])
;   mathfn_f32_unary      name, f64_scalar
;   mathfn_f32_binary     name, f64_scalar
;       name (xmm0[, xmm1] f32) -> xmm0 f32: widen, call the f64 routine,
;       round once. Widening is exact, so the f32 result inherits the f64
;       routine's accuracy plus a single final rounding.
;
; NULL pointers or a zero count do nothing.
; =============================================================================

%macro mathfn__load 2
%if %2 == 8
    movsd   xmm0, %1
%else
    movss   xmm0, %1
%endif
%endmacro

%macro mathfn__load1 2
%if %2 == 8
    movsd   xmm1, %1
%else
    movss   xmm1, %1
%endif
%endmacro

%macro mathfn__store 2
%if %2 == 8
    movsd   %1, xmm0
%else
    movss   %1, xmm0
%endif
%endmacro

%macro mathfn_unary_arrays 3
global %1_array
%1_array:
    push    rbx
    push    r12
    push    r13
    test    rdi, rdi
    jz      %%done
    test    rsi, rsi
    jz      %%done
    test    rdx, rdx
    jz      %%done
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
%%loop:
    mathfn__load [r12], %3
    call    %2
    mathfn__store [rbx], %3
    add     r12, %3
    add     rbx, %3
    dec     r13
    jnz     %%loop
%%done:
    pop     r13
    pop     r12
    pop     rbx
    ret

global %1_inplace
%1_inplace:
    mov     rdx, rsi            ; (buf, count) -> (dst = buf, src = buf, count)
    mov     rsi, rdi
    jmp     %1_array
%endmacro

%macro mathfn_binary_arrays 3
global %1_array
%1_array:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8              ; keep the stack 16-byte aligned at the call
    test    rdi, rdi
    jz      %%done
    test    rsi, rsi
    jz      %%done
    test    rdx, rdx
    jz      %%done
    test    rcx, rcx
    jz      %%done
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
%%loop:
    mathfn__load [r12], %3
    mathfn__load1 [r13], %3
    call    %2
    mathfn__store [rbx], %3
    add     r12, %3
    add     r13, %3
    add     rbx, %3
    dec     r14
    jnz     %%loop
%%done:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
%endmacro

%macro mathfn_f32_unary 2
global %1
%1:
    sub     rsp, 8
    cvtss2sd xmm0, xmm0
    call    %2
    cvtsd2ss xmm0, xmm0
    add     rsp, 8
    ret
%endmacro

%macro mathfn_f32_binary 2
global %1
%1:
    sub     rsp, 8
    cvtss2sd xmm0, xmm0
    cvtss2sd xmm1, xmm1
    call    %2
    cvtsd2ss xmm0, xmm0
    add     rsp, 8
    ret
%endmacro

%endif ; GUARD_LIB_UMATH_MATH_FN_LOOPS_ASM
