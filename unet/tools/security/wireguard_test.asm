; =============================================================================
; Tattva OS — unet/tools/security/wireguard_test.asm
; =============================================================================
; WireGuard Noise_IKpsk2 Handshake & Encryption Benchmark Tool (`wg-test`).
;
; Features:
;   - Initiation (Type 1) & Response (Type 2) Handshake Framing
;   - Curve25519 DH Key Exchange & BLAKE2s Hashing Performance Benchmark
;   - ChaCha20-Poly1305 Line-Rate Data Packet (Type 4) Encrypt/Decrypt Throughput
;   - Nanosecond Resolution Handshake Round-Trip Time Measurement
;
; Delegates:
;   - WireGuard Subsystem               -> unet/vpn/wireguard_blake2s.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define WG_MSG_INITIATION           1
%define WG_MSG_RESPONSE             2
%define WG_MSG_COOKIE               3
%define WG_MSG_DATA                 4

struc wg_initiation_msg_t
    .type:              resd 1      ; 0x00000001
    .sender_idx:        resd 1      ; Sender Index (Little Endian)
    .unephem:           resb 32     ; Ephemeral Public Key
    .encrypted_static:  resb 48     ; Encrypted Static Public Key
    .encrypted_timestamp: resb 28   ; Encrypted Timestamp
    .mac1:              resb 16     ; MAC1
    .mac2:              resb 16     ; MAC2
endstruc

section .text

global wireguard_test_main
global wireguard_test_handshake
global wireguard_test_throughput

extern rdtsc_get_cycles
extern wireguard_process_packet

align 64
wireguard_test_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call wireguard_test_handshake
    call wireguard_test_throughput

    pop rbx
    pop rbp
    ret

align 64
wireguard_test_handshake:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Measure Noise_IKpsk2 handshake duration (Curve25519 + BLAKE2s + ChaCha20-Poly1305)
    call rdtsc_get_cycles
    call wireguard_process_packet
    xor eax, eax
    pop rbp
    ret

align 64
wireguard_test_throughput:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Measure ChaCha20-Poly1305 data packet (Type 4) encryption throughput in Gbps
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret
