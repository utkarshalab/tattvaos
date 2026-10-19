%ifndef GUARD_LIB_UMATH_RANDOM_XOSHIRO256_ASM
%define GUARD_LIB_UMATH_RANDOM_XOSHIRO256_ASM
; =============================================================================
; umath - unified math library
; random/xoshiro256.asm - xoshiro256** 64-bit PRNG core
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; xoshiro256** by David Blackman and Sebastiano Vigna.
; Fast, small-state (4 x 64-bit words), passes BigCrush. Good for numerical
; work (weight init, dropout masks, sampling) — not cryptographic.
; Use lib/urand/ for seeding entropy.
;
; State layout (passed as a pointer in RDI):
;   +00: s0  dq
;   +08: s1  dq
;   +16: s2  dq
;   +24: s3  dq
;
; All state words must be non-zero (at least one bit set somewhere).
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; rotl64 — 64-bit rotate left (helper, not exported)
; args:  rax = value, cl = shift count
; out:   rax = rotated value
; clobbers: rax
; -----------------------------------------------------------------------------
rotl64:
    rol     rax, cl
    ret

; -----------------------------------------------------------------------------
; umath_random_xoshiro256_next — produce the next u64 from the state
; args:  rdi = pointer to random_state_t (4 x u64: s0,s1,s2,s3)
; out:   rax = next 64-bit random value
; clobbers: rax, rcx, r8, r9 (rbx and rbp are saved and restored)
; -----------------------------------------------------------------------------
global umath_random_xoshiro256_next
umath_random_xoshiro256_next:
    push    rbx
    push    rbp

    mov     rbx, rdi                    ; rbx = state pointer

    ; result = rotl(s1 * 5, 7) * 9   (s1 still original here)
    mov     rax, [rbx + 8]              ; rax = s1
    imul    rax, 5                      ; rax = s1 * 5
    mov     rcx, 7
    call    rotl64                      ; rax = rotl(s1*5, 7)
    imul    rax, 9                      ; rax = result
    mov     r8, rax                     ; r8 = result (callee-saved, restore later)

    ; t = s1 << 17   (s1 is still original here)
    mov     rax, [rbx + 8]              ; rax = s1 (original)
    shl     rax, 17                     ; rax = t
    mov     r9, rax                     ; r9 = t

    ; s2 ^= s0
    mov     rax, [rbx + 16]             ; rax = s2
    xor     rax, [rbx + 0]              ; rax ^= s0
    mov     [rbx + 16], rax             ; s2 = s2 ^ s0

    ; s3 ^= s1
    mov     rax, [rbx + 24]             ; rax = s3
    xor     rax, [rbx + 8]              ; rax ^= s1 (original)
    mov     [rbx + 24], rax             ; s3 = s3 ^ s1

    ; s1 ^= s2   (s2 is now s2 ^ s0)
    mov     rax, [rbx + 8]              ; rax = s1 (original)
    xor     rax, [rbx + 16]             ; rax ^= s2 (new)
    mov     [rbx + 8], rax              ; s1 = s1 ^ s2

    ; s0 ^= s3   (s3 is now s3 ^ s1_original)
    mov     rax, [rbx + 0]              ; rax = s0
    xor     rax, [rbx + 24]             ; rax ^= s3 (new)
    mov     [rbx + 0], rax              ; s0 = s0 ^ s3

    ; s2 ^= t    (s2 is now s2 ^ s0; XOR with t)
    mov     rax, [rbx + 16]             ; rax = s2 (new)
    xor     rax, r9                     ; rax ^= t
    mov     [rbx + 16], rax             ; s2 = s2 ^ s0 ^ t

    ; s3 = rotl(s3, 45)   (s3 is now s3 ^ s1_original)
    mov     rax, [rbx + 24]             ; rax = s3 (new)
    mov     cl, 45
    call    rotl64                      ; rax = rotl(s3, 45)
    mov     [rbx + 24], rax             ; s3 = rotl(s3, 45)

    mov     rax, r8                     ; rax = result

    pop     rbp
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_RANDOM_XOSHIRO256_ASM