%ifndef GUARD_LIB_UMATH_RANDOM_UNIFORM_ASM
%define GUARD_LIB_UMATH_RANDOM_UNIFORM_ASM
; =============================================================================
; umath - unified math library
; random/uniform.asm - uniform distribution samplers
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Uniform [0, 1) sampling from xoshiro256**:
;   f32: top 24 bits of u64, divided by 2^24  (24-bit precision)
;   f64: top 53 bits of u64, divided by 2^53  (53-bit precision)
;
; Array-fill variants fill a whole buffer in one pass.
; =============================================================================

bits 64

%include "lib/umath/random/xoshiro256.asm"

section .rodata
align 16
uniform_f32_two24:   dd 0x33800000      ; 1.0 / 2^24 = 2^-24
uniform_f64_two53:   dq 0x3CA0000000000000  ; 1.0 / 2^53 = 2^-53

section .text

; -----------------------------------------------------------------------------
; umath_random_uniform_f32 — next u64 mapped to [0, 1) f32
; args:  rdi = pointer to random_state_t
; out:   xmm0 = f32 in [0, 1)
; clobbers: rax, rbx
; -----------------------------------------------------------------------------
global umath_random_uniform_f32
umath_random_uniform_f32:
    push    rbx
    call    umath_random_xoshiro256_next      ; rax = u64
    mov     rbx, rdi                    ; rbx = state (umath_random_xoshiro256_next may clobber)
    shr     rax, 40                     ; rax = top 24 bits
    cvtsi2ss xmm0, rax                  ; xmm0 = u24 as f32
    mulss   xmm0, [rel uniform_f32_two24]   ; xmm0 *= 1/2^24
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_random_uniform_f64 — next u64 mapped to [0, 1) f64
; Input:  rdi = pointer to random_state_t
; OUT:    xmm0 = f64 in [0, 1)
; clobbers: rax, rbx
; -----------------------------------------------------------------------------
global umath_random_uniform_f64
umath_random_uniform_f64:
    push    rbx
    call    umath_random_xoshiro256_next      ; rax = u64
    mov     rbx, rdi                    ; rbx = state (umath_random_xoshiro256_next may clobber)
    shr     rax, 11                     ; rax = top 53 bits
    cvtsi2sd xmm0, rax                  ; xmm0 = u53 as f64
    mulsd   xmm0, [rel uniform_f64_two53] ; xmm0 *= 1/2^53
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_random_uniform_f32_range — [lo, hi) f32
; args:  rdi = pointer to random_state_t
;        xmm0 = lo, xmm1 = hi
; out:   xmm0 = f32 in [lo, hi)
; clobbers: rax, rbx
; -----------------------------------------------------------------------------
global umath_random_uniform_f32_range
umath_random_uniform_f32_range:
    push    rbx
    movss   xmm2, xmm0                  ; xmm2 = lo (save before call)
    call    umath_random_uniform_f32          ; xmm0 = u in [0, 1)
    subss   xmm1, xmm2                  ; xmm1 = hi - lo
    mulss   xmm0, xmm1                  ; xmm0 = u * (hi - lo)
    addss   xmm0, xmm2                  ; xmm0 = lo + u * (hi - lo)
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_random_uniform_f64_range — [lo, hi) f64
; args:  rdi = pointer to random_state_t
;        xmm0 = lo, xmm1 = hi
; out:   xmm0 = f64 in [lo, hi)
; clobbers: rax, rbx
; -----------------------------------------------------------------------------
global umath_random_uniform_f64_range
umath_random_uniform_f64_range:
    push    rbx
    movsd   xmm2, xmm0                  ; xmm2 = lo (save before call)
    call    umath_random_uniform_f64          ; xmm0 = u in [0, 1)
    subsd   xmm1, xmm2                  ; xmm1 = hi - lo
    mulsd   xmm0, xmm1                  ; xmm0 = u * (hi - lo)
    addsd   xmm0, xmm2                  ; xmm0 = lo + u * (hi - lo)
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_random_fill_uniform_f32 — fill array with f32 uniform [0, 1)
; args:  rdi = pointer to random_state_t
;        rsi = destination f32 array
;        rdx = count
; out:   none
; clobbers: rax, rbx, rcx
; -----------------------------------------------------------------------------
global umath_random_fill_uniform_f32
umath_random_fill_uniform_f32:
    push    rbx
    push    rcx
    mov     rbx, rdi                    ; rbx = state
    mov     rcx, rdx                    ; rcx = count
    test    rcx, rcx
    jz      .done
.loop:
    push    rcx
    mov     rdi, rbx                    ; state
    call    umath_random_uniform_f32          ; xmm0 = u in [0, 1)
    movss   [rsi], xmm0                 ; store to array
    add     rsi, 4
    pop     rcx
    dec     rcx
    jnz     .loop
.done:
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_random_fill_uniform_f64 — fill array with f64 uniform [0, 1)
; args:  rdi = pointer to random_state_t
;        rsi = destination f64 array
;        rdx = count
; out:   none
; clobbers: rax, rbx, rcx
; -----------------------------------------------------------------------------
global umath_random_fill_uniform_f64
umath_random_fill_uniform_f64:
    push    rbx
    push    rcx
    mov     rbx, rdi                    ; rbx = state
    mov     rcx, rdx                    ; rcx = count
    test    rcx, rcx
    jz      .done
.loop:
    push    rcx
    mov     rdi, rbx                    ; state
    call    umath_random_uniform_f64          ; xmm0 = u in [0, 1)
    movsd   [rsi], xmm0                 ; store to array
    add     rsi, 8
    pop     rcx
    dec     rcx
    jnz     .loop
.done:
    pop     rcx
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_RANDOM_UNIFORM_ASM