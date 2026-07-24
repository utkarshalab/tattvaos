; =============================================================================
; Tattva OS — lib/urand/pools/fortuna_pools.asm
; =============================================================================
; Fortuna 32-Pool Entropy Accumulator Architecture (Ferguson & Schneier).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; fortuna_pool_feed — Feed 64-bit entropy sample into Fortuna pool
; Input:  RAX = 64-bit entropy sample
; Output: none
; -----------------------------------------------------------------------------
fortuna_pool_feed:
    push rbx
    push rcx

    mov ecx, [current_feed_pool]
    and ecx, 31                     ; Mask 0..31 pools

    ; XOR entropy into pool
    xor [fortuna_32_pools + rcx*8], rax

    inc dword [current_feed_pool]
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fortuna_pools_reseed — Collect pools and reseed master CSPRNG key
; Input:  RDI = Pointer to Master Key Buffer (32 bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
fortuna_pools_reseed:
    push rbx
    push rcx
    push rsi

    ; Hash all 32 Fortuna pools into 256-bit Key via SHA-256
    mov rsi, 256                    ; 32 pools * 8 bytes = 256 bytes
    mov rdx, rdi                    ; Output key
    mov rdi, fortuna_32_pools
    call uhash_sha256

    mov rax, 1
    pop rsi
    pop rcx
    pop rbx
    ret

section .data
align 16
fortuna_32_pools:  times 32 dq 0
current_feed_pool: dd 0
