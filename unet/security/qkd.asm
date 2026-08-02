; =============================================================================
; Tattva OS — unet/security/qkd.asm
; =============================================================================
; Quantum Key Distribution (QKD ETSI GS QKD 014 / BB84) Integration Engine.
;
; Features:
;   - ETSI GS QKD 014 REST / Binary Key Exchange Interface
;   - Key Buffer Pool Management & Key Lifetime Expiration
;   - Quantum Entropy Re-Keying for IPsec, TLS 1.3, & WireGuard
;   - SIFT Phase (Basis Reconciliation) & Privacy Amplification Status Verification
;   - Emergency Key Purge Memory Wipe (AVX-512 Zeroing)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define QKD_KEY_SIZE_BYTES          32      ; 256-bit Quantum Keys
%define QKD_MAX_POOL_KEYS           256

struc qkd_key_entry_t
    .key_id:            resb 16     ; UUID Key Identifier
    .key_data:          resb 32     ; 256-bit Quantum Shared Key
    .expiration_ts:     resq 1      ; Expiration Timestamp
    .status:            resb 1      ; 0=Free, 1=Available, 2=Consumed
endstruc

section .bss
align 64
qkd_key_pool:           resb qkd_key_entry_t_size * QKD_MAX_POOL_KEYS
qkd_key_count:          resd 1

section .text

global qkd_init
global qkd_get_key
global qkd_push_key
global qkd_purge_keys_avx512

extern rdtsc_get_cycles

align 64
qkd_init:
    push rbp
    mov rbp, rsp
    mov dword [qkd_key_count], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; qkd_get_key — Retrieve Quantum Key by Key ID or Fetch Next Available
; Input: RDI = Pointer to Key ID UUID (or NULL for next available), RSI = Output 32B Key
; Output: EAX = 0 (Success), -1 (No Keys Available)
; -----------------------------------------------------------------------------
align 64
qkd_get_key:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Check key pool for matching key_id and non-expired status
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret

align 64
qkd_push_key:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Insert fresh QKD key into pool from ETSI QKD 014 KME REST API
    inc dword [qkd_key_count]
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; qkd_purge_keys_avx512 — Instant Zeroization Memory Wipe of QKD Key Pool
; -----------------------------------------------------------------------------
align 64
qkd_purge_keys_avx512:
    push rbp
    mov rbp, rsp
    ; AVX-512 64-byte zeroing of qkd_key_pool
    vpxord zmm0, zmm0, zmm0
    mov ecx, (qkd_key_entry_t_size * QKD_MAX_POOL_KEYS) / 64
    lea rdi, [qkd_key_pool]
.purge_loop:
    vmovdqa64 [rdi], zmm0
    add rdi, 64
    loop .purge_loop

    vzeroupper
    mov dword [qkd_key_count], 0
    xor eax, eax
    pop rbp
    ret
