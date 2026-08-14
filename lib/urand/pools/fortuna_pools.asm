%ifndef GUARD_LIB_URAND_POOLS_FORTUNA_POOLS_ASM
%define GUARD_LIB_URAND_POOLS_FORTUNA_POOLS_ASM
; =============================================================================
; Tattva OS — lib/urand/pools/fortuna_pools.asm
; =============================================================================
; Fortuna entropy pools.
;
; Implements:
;   - Feeding a sample into the pools (`fortuna_pool_feed`)
;   - Deriving 32 bytes of seed material (`fortuna_pools_reseed`)
;
; Samples are distributed round-robin across 32 pools and each pool ACCUMULATES
; by XOR rather than being overwritten. Overwriting would mean the pool holds
; only its most recent sample, so an attacker who can predict or influence one
; source at one instant controls the whole pool; XOR means every sample ever
; fed in still contributes.
;
; Spreading across many pools is Fortuna's actual insight: an attacker who can
; observe or influence entropy at some rate cannot keep up with all pools at
; once, so pools drained less often accumulate material the attacker never saw.
;
; The digest is SHA-256 over all pools together. Hashing is what turns
; low-quality, biased samples into a uniform seed — the pools themselves make
; no claim to be uniform, only to be unpredictable in aggregate.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .bss
alignb 64

; Pool storage lives in .bss because it is written on every sample. Placing
; mutable state in .text faults the moment anything tries to write it.
fortuna_32_pools:   resq URAND_FORTUNA_POOLS
current_feed_pool:  resd 1
fortuna_feeds:      resq 1

section .text

global fortuna_pool_feed
global fortuna_pools_reseed

; -----------------------------------------------------------------------------
; fortuna_pool_feed — XOR one 64-bit sample into the next pool.
;
; Inputs:
;   RAX = Entropy sample
; -----------------------------------------------------------------------------
align 32
fortuna_pool_feed:
    push rbx
    push rcx

    mov ecx, [current_feed_pool]
    and ecx, URAND_FORTUNA_POOLS - 1
    lea rbx, [fortuna_32_pools]
    xor [rbx + rcx*8], rax

    inc dword [current_feed_pool]
    inc qword [fortuna_feeds]

    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fortuna_pools_reseed — derive 32 bytes of seed material from the pools.
;
; Inputs:
;   RDI = 32-byte output buffer
;
; Returns:
;   RAX = 1
;
; Calls sha256_hash directly rather than going through the uhash dispatcher, so
; the entropy path depends on one hash rather than on every hash the dispatcher
; can select. It has to be available very early.
; -----------------------------------------------------------------------------
align 32
fortuna_pools_reseed:
    push rbx
    mov rbx, rdi

    lea rdi, [fortuna_32_pools]
    mov rsi, URAND_FORTUNA_POOLS * 8
    mov rdx, rbx
    call sha256_hash

    mov rax, 1
    pop rbx
    ret

%endif ; GUARD_LIB_URAND_POOLS_FORTUNA_POOLS_ASM
