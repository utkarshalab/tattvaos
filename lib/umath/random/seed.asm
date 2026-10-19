%ifndef GUARD_LIB_UMATH_RANDOM_SEED_ASM
%define GUARD_LIB_UMATH_RANDOM_SEED_ASM
; =============================================================================
; umath - unified math library
; random/seed.asm - xoshiro256 seeding (splitmix64 + lib/urand)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Seed a 4-word xoshiro256 state from a single u64 seed using splitmix64,
; or from lib/urand/ hardware entropy (one-time seeding).
;
; State layout (random_state_t, 32 bytes):
;   +00: s0  dq
;   +08: s1  dq
;   +16: s2  dq
;   +24: s3  dq
; =============================================================================

bits 64

%include "lib/umath/random/xoshiro256.asm"

section .text

; -----------------------------------------------------------------------------
; splitmix64 — splitmix64 mixing function (not exported)
; args:  rax = input state
; out:   rax = mixed 64-bit value
; clobbers: rbx, rcx
; -----------------------------------------------------------------------------
splitmix64:
    push    rbx
    mov     rbx, rax                    ; rbx = state
    mov     rcx, 0x9E3779B97F4A7C15
    add     rax, rcx                    ; state += GOLDEN_RATIO
    mov     rbx, rax                    ; z = state
    shr     rbx, 30                     ; z = (z >> 30)
    xor     rax, rbx                    ; z ^= (z >> 30)
    mov     rbx, rax
    imul    rbx, rcx                    ; z *= 0x9E3779B97F4A7C15
    mov     rbx, rax
    shr     rbx, 27                     ; z = (z >> 27)
    xor     rax, rbx                    ; z ^= (z >> 27)
    mov     rbx, rax
    imul    rbx, rcx                    ; z *= 0x9E3779B97F4A7C15
    mov     rbx, rax
    shr     rbx, 31                     ; z = (z >> 31)
    xor     rax, rbx                    ; z ^= (z >> 31)
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; random_xoshiro256_seed_from_u64 — seed state from a single u64
; Input:  rdi = pointer to random_state_t
;         rsi = seed u64
; Output: state filled; at least one state word non-zero guaranteed
; Clobbers: rax, rbx, rcx
; -----------------------------------------------------------------------------
global random_xoshiro256_seed_from_u64
random_xoshiro256_seed_from_u64:
    push    rbx
    mov     rbx, rdi                    ; rbx = state pointer
    mov     rax, rsi                    ; rax = seed

    call    splitmix64                  ; rax = splitmix64(seed) -> s0
    mov     [rbx + 0], rax
    mov     rax, [rbx + 0]              ; chain from s0
    call    splitmix64                  ; rax = splitmix64(s0) -> s1
    mov     [rbx + 8], rax
    mov     rax, [rbx + 8]              ; chain from s1
    call    splitmix64                  ; rax = splitmix64(s1) -> s2
    mov     [rbx + 16], rax
    mov     rax, [rbx + 16]             ; chain from s2
    call    splitmix64                  ; rax = splitmix64(s2) -> s3
    mov     [rbx + 24], rax

    ; Guarantee at least one word is non-zero (splitmix64(0) != 0, so this
    ; only triggers if seed and all splits happen to be zero — practically
    ; impossible but cheap to guard).
    or      qword [rbx + 0], 1

    pop     rbx
    ret

; -----------------------------------------------------------------------------
; random_xoshiro256_seed_from_urand — seed state from lib/urand entropy
; Input:  rdi = pointer to random_state_t
;         rsi = pointer to urand_fill(buf, nbytes) function
; Output: rax = 1 on success, 0 if urand pointer is NULL
; Clobbers: rax, rbx, r12
; -----------------------------------------------------------------------------
global random_xoshiro256_seed_from_urand
random_xoshiro256_seed_from_urand:
    push    rbx
    push    r12

    test    rsi, rsi                    ; urand NULL?
    jz      .null_urand

    mov     rbx, rdi                    ; rbx = state pointer
    mov     r12, rsi                    ; r12 = urand_fill function

    ; Read 32 bytes of entropy directly into the state
    mov     rdi, rbx                    ; buf = state
    mov     rsi, 32                     ; nbytes = 32
    call    r12                         ; rax = urand_fill(state, 32)
    test    rax, rax
    jz      .null_urand

    ; Guarantee at least one word non-zero
    or      qword [rbx + 0], 1

    mov     rax, 1                      ; success
    jmp     .done

.null_urand:
    xor     rax, rax                    ; failure

.done:
    pop     r12
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_RANDOM_SEED_ASM