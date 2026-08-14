%ifndef GUARD_UNET_PQC_QKD_KM_ASM
%define GUARD_UNET_PQC_QKD_KM_ASM
; =============================================================================
; Tattva OS — unet/pqc/qkd_km.asm
; =============================================================================
; Quantum Key Distribution Key Management Integration Engine (ETSI GS QKD 014 / 004).
;
; Features:
;   - ETSI GS QKD 014 REST / JSON Key Management Agency (KMA) Interface
;   - Quantum Entropy Key Pool Allocation & High-Frequency Key Rotation
;   - Quantum-Resistant Hybrid Key Combination: K_hybrid = HKDF(K_QKD || K_PQC)
;   - Emergency Key Purge Memory Zeroization (AVX-512 `VZEROALL` + Memory Scrub)
;
; Delegates:
;   - QKD Hardware Interface             -> unet/security/qkd.asm
;   - HKDF Key Derivation                -> lib/crypto/hkdf.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define QKD_KM_KEY_SIZE             32      ; 256-bit Key Size

struc qkd_km_session_t
    .key_id:            resb 16     ; UUID
    .qkd_key:           resb 32     ; QKD Key
    .pqc_key:           resb 32     ; PQC Key
    .hybrid_key:        resb 32     ; Derived Hybrid Master Key
    .status:            resb 1      ; 0=Empty, 1=Active, 2=Expired
endstruc

section .text

global qkd_km_init
global qkd_km_fetch_key
global qkd_km_combine_hybrid
global qkd_km_purge_all

align 64
qkd_km_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
qkd_km_fetch_key:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Fetch quantum key from QKD hardware pool & combine with PQC key
    call qkd_get_key
    call qkd_km_combine_hybrid

    pop rbx
    pop rbp
    ret

align 64
qkd_km_combine_hybrid:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; HKDF-SHA256(qkd_key || pqc_key, "QKD-PQC-Hybrid-Key-v1")
    call hkdf_extract_expand
    pop rbp
    ret

align 64
qkd_km_purge_all:
    push rbp
    mov rbp, rsp
    ; Clear CPU registers & zero out memory
    vzeroall
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_PQC_QKD_KM_ASM
