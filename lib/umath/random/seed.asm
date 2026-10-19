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
; umath_random_splitmix64_next — one step of splitmix64 (not exported)
; args:  r8 = splitmix64 state (advanced in place)
; out:   rax = next 64-bit output
; clobbers: rax, rcx, r8
;
; Reference (Vigna):
;   x += 0x9E3779B97F4A7C15
;   z = x
;   z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
;   z = (z ^ (z >> 27)) * 0x94D049BB133111EB
;   return z ^ (z >> 31)
; -----------------------------------------------------------------------------
umath_random_splitmix64_next:
    mov     rcx, 0x9E3779B97F4A7C15
    add     r8, rcx                     ; x += golden ratio increment
    mov     rax, r8                     ; z = x
    mov     rcx, rax
    shr     rcx, 30
    xor     rax, rcx                    ; z ^= z >> 30
    mov     rcx, 0xBF58476D1CE4E5B9
    imul    rax, rcx                    ; z *= 0xBF58476D1CE4E5B9
    mov     rcx, rax
    shr     rcx, 27
    xor     rax, rcx                    ; z ^= z >> 27
    mov     rcx, 0x94D049BB133111EB
    imul    rax, rcx                    ; z *= 0x94D049BB133111EB
    mov     rcx, rax
    shr     rcx, 31
    xor     rax, rcx                    ; z ^= z >> 31
    ret

; -----------------------------------------------------------------------------
; umath_random_xoshiro256_seed_from_u64 — seed state from a single u64
; Input:  rdi = pointer to random_state_t
;         rsi = seed u64
; Output: s0..s3 = the first four splitmix64 outputs for that seed, the
;         seeding the xoshiro authors recommend. splitmix64 is a bijection
;         of its counter, so four consecutive outputs are never all zero.
; Clobbers: rax, rcx, r8
; -----------------------------------------------------------------------------
global umath_random_xoshiro256_seed_from_u64
umath_random_xoshiro256_seed_from_u64:
    mov     r8, rsi                     ; splitmix64 state = seed
    call    umath_random_splitmix64_next
    mov     [rdi + 0], rax              ; s0
    call    umath_random_splitmix64_next
    mov     [rdi + 8], rax              ; s1
    call    umath_random_splitmix64_next
    mov     [rdi + 16], rax             ; s2
    call    umath_random_splitmix64_next
    mov     [rdi + 24], rax             ; s3
    ret

; -----------------------------------------------------------------------------
; umath_random_xoshiro256_seed_from_urand — seed state from lib/urand entropy
; Input:  rdi = pointer to random_state_t
;         rsi = pointer to urand_fill(buf, nbytes) function
; Output: rax = 1 on success; 0 if the urand pointer is NULL or urand_fill
;         returned 0. An all-zero fill (the one state xoshiro cannot leave)
;         is replaced by s0 = 1.
; Clobbers: rax, rcx, rdx, rsi, rdi, r8-r11 (urand_fill is a SysV call)
; -----------------------------------------------------------------------------
global umath_random_xoshiro256_seed_from_urand
umath_random_xoshiro256_seed_from_urand:
    push    rbx
    push    r12
    sub     rsp, 8                      ; rsp 16-byte aligned at the call below

    xor     eax, eax                    ; failure unless proven otherwise
    test    rsi, rsi                    ; urand NULL?
    jz      .done

    mov     rbx, rdi                    ; rbx = state pointer
    mov     r12, rsi                    ; r12 = urand_fill function

    ; Read 32 bytes of entropy directly into the state
    mov     rdi, rbx                    ; buf = state
    mov     esi, 32                     ; nbytes = 32
    call    r12                         ; rax = urand_fill(state, 32)
    test    rax, rax
    jz      .done                       ; rax = 0: failure

    mov     rax, [rbx + 0]
    or      rax, [rbx + 8]
    or      rax, [rbx + 16]
    or      rax, [rbx + 24]
    jnz     .ok
    mov     qword [rbx + 0], 1          ; all-zero state would stay zero forever
.ok:
    mov     eax, 1                      ; success

.done:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_RANDOM_SEED_ASM