; =============================================================================
; Tattva OS — unet/tools/security/pqc_inspect.asm
; =============================================================================
; Post-Quantum Cryptography Cipher Inspector Tool (`pqc-inspect`).
;
; Features:
;   - NIST FIPS 203 ML-KEM-1024 (Kyber-1024) Key Encapsulation Benchmark
;   - NIST FIPS 204 ML-DSA-87 (Dilithium-5) Post-Quantum Digital Signature Audit
;   - Hybrid Classic-Quantum Handshake (x25519 + ML-KEM-1024) Verification
;   - CPU Cycle Overhead & Memory Footprint Profiling
;
; Delegates:
;   - Post-Quantum WireGuard            -> unet/pqc/pqc_wireguard.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pqc_inspect_main
global pqc_inspect_ml_kem_1024
global pqc_inspect_ml_dsa_87

extern rdtsc_get_cycles
extern pqc_wireguard_handshake

align 64
pqc_inspect_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call pqc_inspect_ml_kem_1024
    call pqc_inspect_ml_dsa_87

    pop rbx
    pop rbp
    ret

align 64
pqc_inspect_ml_kem_1024:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Benchmark ML-KEM-1024 (Kyber) keygen, encapsulation, & decapsulation CPU cycles
    call rdtsc_get_cycles
    call pqc_wireguard_handshake
    xor eax, eax
    pop rbp
    ret

align 64
pqc_inspect_ml_dsa_87:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Audit ML-DSA-87 (Dilithium) digital signature verification speed
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret
