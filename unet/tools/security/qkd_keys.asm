; =============================================================================
; Tattva OS — unet/tools/security/qkd_keys.asm
; =============================================================================
; Quantum Key Distribution Key Management Agency Inspector (`qkd-keys`).
;
; Features:
;   - ETSI GS QKD 014 Key Pool Status, Entropy Rate, and Key Rotation Rate Audit
;   - Emergency Quantum Key Purge Benchmark
;
; Delegates:
;   - QKD Key Manager                   -> unet/pqc/qkd_km.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global qkd_keys_main

extern qkd_km_fetch_key

align 64
qkd_keys_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Query ETSI GS QKD 014 Key Management Agency REST/UDP endpoint & audit key pool status
    call qkd_km_fetch_key
    pop rbp
    ret
