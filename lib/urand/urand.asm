%ifndef GUARD_LIB_URAND_URAND_ASM
%define GUARD_LIB_URAND_URAND_ASM
; =============================================================================
; Tattva OS — lib/urand/urand.asm
; =============================================================================
; Entropy manager and CSPRNG dispatcher.
;
; Implements:
;   - Initialisation and reseeding (`urand_init`, `urand_reseed`)
;   - The master API (`urand_get_bytes`)
;
; Everything that needs unpredictability goes through here: password salts,
; the usrauth token signing key, nonces. A weakness at this layer is not a
; local bug — it silently removes the security of every layer above.
;
; STATE LIVES IN .bss, NOT .text. This is not a style preference. The CSPRNG
; state is written on every call, and .text is mapped read-only, so state
; placed there faults on the first store. That is exactly what the previous
; version of this file did, and because the test harnesses substitute their own
; urand_get_bytes, nothing above ever exercised it.
;
; RESEEDING IS PERIODIC, NOT ONE-SHOT. Boot-time entropy can be thin —
; RDSEED may be unavailable and the jitter source has barely had time to
; accumulate anything. Folding fresh entropy in as the system runs is what
; recovers from a poor initial seed rather than living with it forever.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"
%include "lib/urand/urand_wipe.asm"
%include "lib/urand/sources/rdrand.asm"
%include "lib/urand/sources/jitter.asm"
%include "lib/urand/sources/interrupt_entropy.asm"
%include "lib/urand/health/entropy_health.asm"
%include "lib/urand/pools/fortuna_pools.asm"
%include "lib/urand/generators/chacha20_rng.asm"
%include "lib/urand/generators/aes_ctr_drbg.asm"
%include "lib/urand/urand_percpu.asm"

; Blocks emitted before fresh entropy is folded in.
%define URAND_RESEED_BLOCKS     1024

section .bss
alignb 64

global master_urand_state
master_urand_state: resb urand_ctx_t_size

section .text

global urand_init
global urand_reseed
global urand_get_bytes

; -----------------------------------------------------------------------------
; urand_init — bring the CSPRNG up.
;
; Returns:
;   RAX = 1 on success, 0 when no entropy source produced anything
;
; Refusing to start beats starting with a known key. A CSPRNG that reports
; success on an unseeded state hands out predictable "random" values, and
; every caller believes them.
; -----------------------------------------------------------------------------
align 32
urand_init:
    push rbx

    lea rbx, [master_urand_state]

    ; Clear the state. BSS is zero at load in a hosted build, but a kernel that
    ; skipped the wipe would otherwise start from whatever was in memory.
    mov rdi, rbx
    mov rsi, urand_ctx_t_size
    call urand_wipe_buffer

    mov dword [rbx + urand_ctx_t.generator_id], URAND_GEN_CHACHA20
    mov dword [rbx + urand_ctx_t.health_status], URAND_HEALTH_OK

    call urand_reseed
    test rax, rax
    jz .no_entropy

    mov dword [rbx + urand_ctx_t.initialized], 1
    mov rax, 1
    pop rbx
    ret

.no_entropy:
    mov dword [rbx + urand_ctx_t.health_status], URAND_HEALTH_FAILED
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; urand_reseed — harvest entropy and fold it into the key.
;
; Returns:
;   RAX = 1 when at least one source contributed, 0 otherwise
;
; Sources are combined, never selected between. RDSEED could be backdoored,
; the jitter source could be weak on a deterministic machine, and the IRQ pool
; could be empty early in boot; XORing all of them into the pool means an
; attacker has to defeat every one, not the weakest.
;
; The new key is the hash of the pools XORed with the OLD key, so a reseed can
; only ever add uncertainty. Overwriting the key outright would let a
; compromised entropy source REPLACE good state with attacker-chosen state.
; -----------------------------------------------------------------------------
align 32
urand_reseed:
    push rbx
    push r12
    push r13
    sub rsp, 64

    lea rbx, [master_urand_state]
    xor r12d, r12d                  ; Sources that contributed

    ; ---- 1. RDSEED, then RDRAND as a fallback ----
    call rdseed_get_uint64
    test rdx, rdx
    jz .try_rdrand

    ; The health check returns its verdict in RAX, destroying the sample, so
    ; the sample is held aside rather than re-read. Re-reading would test one
    ; value and then feed a different, untested one.
    mov r13, rax
    call entropy_health_check_rct
    cmp rax, URAND_HEALTH_OK
    jne .harvest_jitter
    mov rax, r13
    call fortuna_pool_feed
    inc r12d
    jmp .harvest_jitter

.try_rdrand:
    call rdrand_get_uint64
    test rdx, rdx
    jz .harvest_jitter
    call fortuna_pool_feed
    inc r12d

.harvest_jitter:
    ; ---- 2. Execution timing jitter ----
    call jitter_get_uint64
    test rax, rax
    jz .derive
    call fortuna_pool_feed
    inc r12d

.derive:
    test r12d, r12d
    jz .none

    ; ---- 3. New key = SHA-256(pools) XOR old key ----
    lea rdi, [rsp]
    call fortuna_pools_reseed

%assign i 0
%rep 4
    mov rax, [rsp + i*8]
    xor [rbx + urand_ctx_t.key + i*8], rax
%assign i i+1
%endrep

    mov dword [rbx + urand_ctx_t.counter], 0
    mov qword [rbx + urand_ctx_t.blocks_out], 0
    inc qword [rbx + urand_ctx_t.reseed_counter]

    ; Seed V for the CTR_DRBG path from the upper half of the same digest.
    ; Only 32 bytes came back, so reading past them would seed the counter
    ; from uninitialised stack.
    mov rax, [rsp + 16]
    xor [rbx + urand_ctx_t.drbg_v], rax
    mov rax, [rsp + 24]
    xor [rbx + urand_ctx_t.drbg_v + 8], rax

    mov rdi, rsp
    mov rsi, 64
    call urand_wipe_buffer

    mov rax, 1
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

.none:
    xor eax, eax
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; urand_get_bytes — the master API.
;
; Inputs:
;   RDI = Output buffer
;   RSI = Length in bytes
;
; Returns:
;   RAX = Bytes written, or 0 when the CSPRNG is unavailable
;
; On failure NOTHING is written and 0 is returned. Callers must check: a salt
; or key buffer left untouched holds whatever was there before, and treating a
; failed call as success is how a fixed salt reaches every credential.
; -----------------------------------------------------------------------------
align 32
urand_get_bytes:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 64                     ; One keystream block

    mov r12, rdi                    ; Output
    mov r13, rsi                    ; Remaining
    mov rbp, rdi                    ; Cursor

    test r12, r12
    jz .fail
    test r13, r13
    jz .nothing_to_do

    lea rbx, [master_urand_state]
    cmp dword [rbx + urand_ctx_t.initialized], 1
    je .ready
    call urand_init
    test rax, rax
    jz .fail

.ready:
    cmp dword [rbx + urand_ctx_t.health_status], URAND_HEALTH_OK
    jne .fail

    ; Fold in fresh entropy periodically rather than only at boot.
    cmp qword [rbx + urand_ctx_t.blocks_out], URAND_RESEED_BLOCKS
    jb .generate
    call urand_reseed

.generate:
    mov r14, r13                    ; Bytes still owed

.block_loop:
    test r14, r14
    jz .finish

    mov rdi, rbx
    mov rsi, rsp
    cmp dword [rbx + urand_ctx_t.generator_id], URAND_GEN_AES_DRBG
    je .use_aes
    call chacha20_rng_generate
    jmp .have_block
.use_aes:
    call aes_ctr_drbg_generate

.have_block:
    ; Copy min(64, remaining). The source is the scratch block at RSP — and it
    ; must be addressed with nothing pushed on top of it, which is what the
    ; previous version got wrong: it pushed two registers and then took RSP as
    ; the source, so every call emitted saved register values, starting with a
    ; kernel pointer, instead of keystream.
    mov rcx, 64
    cmp rcx, r14
    jbe .copy
    mov rcx, r14
.copy:
    mov rdi, rbp
    mov rsi, rsp
    rep movsb                       ; Advances RDI and RSI, leaves RCX zero

    mov rbp, rdi                    ; Cursor moved on by the copy
    mov rax, 64
    cmp rax, r14
    jbe .advance
    mov rax, r14
.advance:
    sub r14, rax
    jmp .block_loop

.finish:
    ; Key erasure: what was just handed out must not be recomputable from the
    ; state that remains.
    mov rdi, rbx
    cmp dword [rbx + urand_ctx_t.generator_id], URAND_GEN_AES_DRBG
    je .aes_rekeyed
    call chacha20_rng_rekey
.aes_rekeyed:
    ; The CTR_DRBG rotates its own state inside generate, so it needs nothing
    ; further here.

    mov rdi, rsp
    mov rsi, 64
    call urand_wipe_buffer

    mov rax, r13
    jmp .out

.nothing_to_do:
    xor eax, eax
    jmp .out

.fail:
    xor eax, eax

.out:
    add rsp, 64
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; GUARD_LIB_URAND_URAND_ASM
