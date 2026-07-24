; =============================================================================
; Tattva OS — lib/urand/urand.asm
; =============================================================================
; Master Hyperscale Entropy Manager & CSPRNG API Dispatcher.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"
%include "lib/urand/sources/rdrand.asm"
%include "lib/urand/sources/jitter.asm"
%include "lib/urand/sources/interrupt_entropy.asm"
%include "lib/urand/health/entropy_health.asm"
%include "lib/urand/pools/fortuna_pools.asm"
%include "lib/urand/generators/chacha20_rng.asm"
%include "lib/urand/generators/aes_ctr_drbg.asm"
%include "lib/urand/urand_percpu.asm"
%include "lib/urand/urand_wipe.asm"

section .text

; Master CSPRNG Context State
align 16
global master_urand_state
master_urand_state: times urand_ctx_t_size db 0

; -----------------------------------------------------------------------------
; urand_init — Master Initialization of Hyperscale CSPRNG Engine
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
urand_init:
    push rbx
    push rdi

    mov rdi, master_urand_state
    mov dword [rdi + urand_ctx_t.initialized], 1
    mov dword [rdi + urand_ctx_t.generator_id], URAND_GEN_CHACHA20
    mov dword [rdi + urand_ctx_t.health_status], URAND_HEALTH_OK

    ; Reseed Fortuna pools
    call urand_reseed

    mov rax, 1
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; urand_reseed — Harvest RDRAND, Jitter & IRQ sources into Fortuna Pools
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
urand_reseed:
    push rbx
    push rdx

    ; 1. Harvest Intel RDRAND / RDSEED hardware entropy
    call rdseed_get_uint64
    test rdx, rdx
    jz .try_rdrand

    ; Run NIST SP 800-90B Repetition Count Test
    call entropy_health_check_rct
    cmp rax, URAND_HEALTH_OK
    jne .harvest_jitter

    call fortuna_pool_feed
    jmp .harvest_jitter

.try_rdrand:
    call rdrand_get_uint64
    call fortuna_pool_feed

.harvest_jitter:
    ; 2. Harvest CPU execution timing jitter
    call jitter_get_uint64
    call fortuna_pool_feed

    ; 3. Reseed master key from Fortuna 32-pool collector
    lea rdi, [master_urand_state + urand_ctx_t.key]
    call fortuna_pools_reseed

    mov rax, 1
    pop rdx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; urand_get_bytes — Master API for Cryptographically Secure Random Bytes
; Input:  RDI = Output Buffer Pointer
;         RSI = Output Length in bytes
; Output: RAX = Bytes generated
; -----------------------------------------------------------------------------
urand_get_bytes:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 64                     ; Scratch buffer for random block generation

    mov r12, rdi                    ; Output buffer
    mov r13, rsi                    ; Length

    ; Ensure CSPRNG is initialized
    cmp dword [master_urand_state + urand_ctx_t.initialized], 1
    je .generate
    call urand_init

.generate:
    xor rbx, rbx
.block_loop:
    cmp rbx, r13
    jae .done_gen

    ; Generate 64-byte random block via ChaCha20 generator
    lea rdi, [master_urand_state + urand_ctx_t.key]
    lea rsi, [master_urand_state + urand_ctx_t.nonce]
    mov rdx, rsp
    call chacha20_rng_generate

    ; Copy block bytes to output buffer
    mov rcx, 64
    mov r8, r13
    sub r8, rbx
    cmp rcx, r8
    jbe .do_copy
    mov rcx, r8

.do_copy:
    push rsi
    push rdi
    mov rdi, r12
    add rdi, rbx
    mov rsi, rsp
    rep movsb
    pop rdi
    pop rsi

    add rbx, 64
    jmp .block_loop

.done_gen:
    ; Memory Scrubbing & Zeroization of scratch stack frame
    mov rdi, rsp
    mov rsi, 64
    call urand_wipe_buffer

    mov rax, r13
    add rsp, 64
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret
