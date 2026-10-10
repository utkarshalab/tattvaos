%ifndef GUARD_LIB_UMATH_REDUCE_SUM_INT_ASM
%define GUARD_LIB_UMATH_REDUCE_SUM_INT_ASM
; =============================================================================
; umath - unified math library
; reduce/sum_int.asm - exact integer sums (no overflow)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Integer sums wrap silently in the element width; these widen instead:
;
;   - 32-bit elements accumulate in 64 bits (SSE2: each dword interleaved
;     with its sign or with zero, two paddq lanes in each of two registers),
;     exact for any count below 2^32.
;   - 64-bit elements accumulate in 128 bits (add + adc), exact for any
;     count, returned as rdx:rax (the System V layout of a 128-bit integer).
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; redsumint_i32 - shared loop for the 32-bit sums
; args:    %1 = signed or unsigned
; expects: rdi = src, rsi = count (non-zero)
; returns: rax = 64-bit sum
; -----------------------------------------------------------------------------
%macro redsumint_i32 1
    pxor    xmm0, xmm0
    pxor    xmm1, xmm1
    pxor    xmm4, xmm4          ; zero dwords (unsigned high halves)
    mov     rcx, rsi
    shr     rcx, 2              ; count of 4-element groups
    jz      %%reduce
%%loop4:
    movdqu  xmm2, [rdi]
%ifidn %1, signed
    movdqa  xmm4, xmm2
    psrad   xmm4, 31            ; sign dwords (signed high halves)
%endif
    movdqa  xmm3, xmm2
    punpckldq xmm2, xmm4        ; elements 0-1 widened to 64 bits
    punpckhdq xmm3, xmm4        ; elements 2-3
    paddq   xmm0, xmm2
    paddq   xmm1, xmm3
    add     rdi, 16
    dec     rcx
    jnz     %%loop4
%%reduce:
    paddq   xmm0, xmm1
    movq    rax, xmm0
    pshufd  xmm1, xmm0, 0xEE    ; high qword
    movq    rcx, xmm1
    add     rax, rcx
    and     rsi, 3
    jz      %%done
%%tail:
%ifidn %1, signed
    movsxd  rcx, dword [rdi]
%else
    mov     ecx, [rdi]          ; zero-extends
%endif
    add     rax, rcx
    add     rdi, 4
    dec     rsi
    jnz     %%tail
%%done:
%endmacro

; -----------------------------------------------------------------------------
; umath_reduce_sum_i32 - exact sum of int32 values
; args:    rdi = source pointer (src)
;          rsi = size of array (count, < 2^32 for exactness)
; returns: rax = sum as int64 (0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_sum_i32
umath_reduce_sum_i32:
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    redsumint_i32 signed
.done:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_sum_u32 - exact sum of uint32 values
; args:    rdi = source pointer (src)
;          rsi = size of array (count, < 2^32 for exactness)
; returns: rax = sum as uint64 (0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_sum_u32
umath_reduce_sum_u32:
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    redsumint_i32 unsigned
.done:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_sum_i64 - exact sum of int64 values
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rdx:rax = sum as a signed 128-bit integer (0 for empty or NULL)
; -----------------------------------------------------------------------------
global umath_reduce_sum_i64
umath_reduce_sum_i64:
    xor     eax, eax            ; low 64 bits
    xor     edx, edx            ; high 64 bits
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
.loop:
    mov     rcx, [rdi]
    mov     r8, rcx
    sar     r8, 63              ; sign extension: 0 or -1
    add     rax, rcx
    adc     rdx, r8
    add     rdi, 8
    dec     rsi
    jnz     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_sum_u64 - exact sum of uint64 values
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rdx:rax = sum as an unsigned 128-bit integer (0 for empty or NULL)
; -----------------------------------------------------------------------------
global umath_reduce_sum_u64
umath_reduce_sum_u64:
    xor     eax, eax
    xor     edx, edx
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
.loop:
    add     rax, [rdi]
    adc     rdx, 0
    add     rdi, 8
    dec     rsi
    jnz     .loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_REDUCE_SUM_INT_ASM
