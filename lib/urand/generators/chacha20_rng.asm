%ifndef GUARD_LIB_URAND_GENERATORS_CHACHA20_RNG_ASM
%define GUARD_LIB_URAND_GENERATORS_CHACHA20_RNG_ASM
; =============================================================================
; Tattva OS — lib/urand/generators/chacha20_rng.asm
; =============================================================================
; ChaCha20 (RFC 8439) CSPRNG with key erasure.
;
; Implements:
;   - The bare block function (`chacha20_block`)
;   - Context-driven generation with counter advance (`chacha20_rng_generate`)
;   - Forward-secrecy rekey (`chacha20_rng_rekey`)
;
; TWENTY ROUNDS, i.e. ten double rounds: four column quarter-rounds then four
; diagonal ones. The diagonal pass is what couples the four columns together;
; running only the column pass produces four independent 128-bit permutations
; and the output looks fine while having a fraction of the intended strength.
;
; THE OUTPUT IS THE PERMUTED STATE ADDED TO THE ORIGINAL, not the permuted
; state alone. ChaCha's core permutation is invertible, so emitting it directly
; would let anyone run it backwards and recover the key from one block. The
; feed-forward addition is the entire reason that does not work.
;
; KEY ERASURE gives forward secrecy. After serving a request the key is
; replaced with fresh keystream and the counter restarts, so an attacker who
; later captures the RNG state cannot reproduce anything it already emitted.
; Without it, one memory disclosure retroactively exposes every salt, nonce and
; key the system has ever generated.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global chacha20_block
global chacha20_rng_generate
global chacha20_rng_rekey

; -----------------------------------------------------------------------------
; CHACHA_QR — quarter round on four state words held at [RSP].
;
;   a += b;  d ^= a;  d <<<= 16
;   c += d;  b ^= c;  b <<<= 12
;   a += b;  d ^= a;  d <<<=  8
;   c += d;  b ^= c;  b <<<=  7
;
; Rotations are left rotations of 32-bit words. Using 64-bit rotates here would
; be silently wrong: the top half is not part of the word.
; -----------------------------------------------------------------------------
%macro CHACHA_QR 4
    mov  eax, [rsp + %1*4]
    add  eax, [rsp + %2*4]
    mov  ecx, [rsp + %4*4]
    xor  ecx, eax
    rol  ecx, 16

    mov  edx, [rsp + %3*4]
    add  edx, ecx
    mov  r8d, [rsp + %2*4]
    xor  r8d, edx
    rol  r8d, 12

    add  eax, r8d
    mov  [rsp + %1*4], eax
    xor  ecx, eax
    rol  ecx, 8
    mov  [rsp + %4*4], ecx

    add  edx, ecx
    mov  [rsp + %3*4], edx
    xor  r8d, edx
    rol  r8d, 7
    mov  [rsp + %2*4], r8d
%endmacro

; -----------------------------------------------------------------------------
; chacha20_block — one 64-byte keystream block.
;
; Inputs:
;   RDI = 64-byte output
;   RSI = 32-byte key
;   RDX = 12-byte nonce
;   ECX = 32-bit block counter
;
; The state is the constant "expand 32-byte k", the key, the counter and the
; nonce, in that order. All words are little-endian, which on x86 makes the
; key and nonce plain dword loads.
; -----------------------------------------------------------------------------
align 32
chacha20_block:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 128                    ; [rsp] working state, [rsp+64] original

    mov r12, rdi                    ; out
    mov r13, rdx                    ; nonce

    ; Words 0..3: the constant, "expand 32-byte k".
    mov dword [rsp + 0*4], 0x61707865
    mov dword [rsp + 1*4], 0x3320646E
    mov dword [rsp + 2*4], 0x79622D32
    mov dword [rsp + 3*4], 0x6B206574

    ; Words 4..11: the key.
%assign i 0
%rep 8
    mov eax, [rsi + i*4]
    mov [rsp + (4 + i)*4], eax
%assign i i+1
%endrep

    ; Word 12: the block counter.
    mov [rsp + 12*4], ecx

    ; Words 13..15: the nonce.
%assign i 0
%rep 3
    mov eax, [r13 + i*4]
    mov [rsp + (13 + i)*4], eax
%assign i i+1
%endrep

    ; Keep the original for the feed-forward addition.
%assign i 0
%rep 16
    mov eax, [rsp + i*4]
    mov [rsp + 64 + i*4], eax
%assign i i+1
%endrep

    mov ebx, 10                     ; Ten double rounds = twenty rounds
.rounds:
    ; Columns
    CHACHA_QR 0, 4,  8, 12
    CHACHA_QR 1, 5,  9, 13
    CHACHA_QR 2, 6, 10, 14
    CHACHA_QR 3, 7, 11, 15
    ; Diagonals
    CHACHA_QR 0, 5, 10, 15
    CHACHA_QR 1, 6, 11, 12
    CHACHA_QR 2, 7,  8, 13
    CHACHA_QR 3, 4,  9, 14
    dec ebx
    jnz .rounds

    ; out = permuted + original
%assign i 0
%rep 16
    mov eax, [rsp + i*4]
    add eax, [rsp + 64 + i*4]
    mov [r12 + i*4], eax
%assign i i+1
%endrep

    add rsp, 128
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; chacha20_rng_generate — one block from a CSPRNG context.
;
; Inputs:
;   RDI = urand_ctx_t
;   RSI = 64-byte output
;
; Returns:
;   RAX = 1
;
; Advances the block counter. Failing to advance it is the classic keystream
; reuse bug: every call would return the same 64 bytes, which is exactly the
; behaviour the previous version of this file had.
; -----------------------------------------------------------------------------
align 32
chacha20_rng_generate:
    push rbx
    push r12

    mov rbx, rdi                    ; ctx
    mov r12, rsi                    ; out

    mov rdi, r12
    lea rsi, [rbx + urand_ctx_t.key]
    lea rdx, [rbx + urand_ctx_t.nonce]
    mov ecx, [rbx + urand_ctx_t.counter]
    call chacha20_block

    inc dword [rbx + urand_ctx_t.counter]
    inc qword [rbx + urand_ctx_t.blocks_out]

    mov rax, 1
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; chacha20_rng_rekey — replace the key with fresh keystream.
;
; Inputs:
;   RDI = urand_ctx_t
;
; Generates one block, takes its first 32 bytes as the new key, and restarts
; the counter. The old key is gone, so output already delivered cannot be
; recomputed from the state that remains.
;
; The nonce is advanced too. Restarting the counter under an unchanged nonce
; and a new key is safe, but advancing the nonce as well means that even a
; rekey that somehow produced the same key would not repeat a keystream.
; -----------------------------------------------------------------------------
align 32
chacha20_rng_rekey:
    push rbx
    sub rsp, 64

    mov rbx, rdi

    mov rdi, rbx
    mov rsi, rsp
    call chacha20_rng_generate

    ; New key from the fresh block.
%assign i 0
%rep 4
    mov rax, [rsp + i*8]
    mov [rbx + urand_ctx_t.key + i*8], rax
%assign i i+1
%endrep

    ; Advance the nonce as a 96-bit little-endian counter.
    mov eax, [rbx + urand_ctx_t.nonce]
    add eax, 1
    mov [rbx + urand_ctx_t.nonce], eax
    jnc .nonce_done
    mov eax, [rbx + urand_ctx_t.nonce + 4]
    adc eax, 0
    mov [rbx + urand_ctx_t.nonce + 4], eax
    jnc .nonce_done
    mov eax, [rbx + urand_ctx_t.nonce + 8]
    adc eax, 0
    mov [rbx + urand_ctx_t.nonce + 8], eax
.nonce_done:

    mov dword [rbx + urand_ctx_t.counter], 0

    ; The block still holds the new key; it must not be left on the stack.
    mov rdi, rsp
    mov rsi, 64
    call urand_wipe_buffer

    add rsp, 64
    pop rbx
    mov rax, 1
    ret

%endif ; GUARD_LIB_URAND_GENERATORS_CHACHA20_RNG_ASM
