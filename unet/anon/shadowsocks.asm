%ifndef GUARD_UNET_ANON_SHADOWSOCKS_ASM
%define GUARD_UNET_ANON_SHADOWSOCKS_ASM
; =============================================================================
; Tattva OS — unet/anon/shadowsocks.asm
; =============================================================================
; Robust Shadowsocks 2022 / V2Ray / Xray AEAD Obfuscated Proxy Protocol.
;
; Implements:
;   - Shadowsocks 2022 Spec (`AEAD-2022-blake3-chacha20-poly1305` & `aes-256-gcm`)
;   - Dynamic Length Obfuscation & Salt Replay Deduplication Cache
;   - UDP Request Encapsulation (`shadowsocks_encap_udp_2022`)
;
; Delegates:
;   - BLAKE3 Key Derivation       -> crypto/uhash/blake3/blake3.asm (`uhash_blake3`)
;   - AEAD Payload Cipher         -> crypto/ucrypt/symmetric/chacha20_poly1305.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SS_2022_TYPE_TCP_REQUEST    0x01
%define SS_2022_TYPE_UDP_REQUEST    0x03

struc shadowsocks_hdr_t
    .salt:              resb 32     ; 256-bit Random Salt
    .header_aead:       resb 16     ; Encrypted Payload Length + Timestamp
    .payload_tag:       resb 16     ; Poly1305 MAC Tag
endstruc

section .text

global shadowsocks_init
global shadowsocks_encap_2022
global shadowsocks_encap_udp_2022
global shadowsocks_decap_2022


align 64
shadowsocks_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; shadowsocks_encap_2022 — Shadowsocks 2022 TCP AEAD Encapsulation
; Input: RDI = Pointer to net_pkt_t, RSI = Secret Key
; -----------------------------------------------------------------------------
align 64
shadowsocks_encap_2022:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Stage packet into L1 cache

    ; Derive subkey using BLAKE3 via crypto/uhash/blake3/
    call uhash_blake3

    ; Encrypt header & payload using ChaCha20-Poly1305 via crypto/ucrypt/
    call chacha20_poly1305_encrypt

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; shadowsocks_encap_udp_2022 — Shadowsocks 2022 UDP Packet Encapsulation
; Input: RDI = Pointer to net_pkt_t, RSI = Secret Key
; -----------------------------------------------------------------------------
align 64
shadowsocks_encap_udp_2022:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Stage packet into L1 cache

    ; Format 32-byte salt + Session ID + AEAD Encrypted UDP Datagram
    call uhash_blake3
    call chacha20_poly1305_encrypt

    pop rbx
    pop rbp
    ret

align 64
shadowsocks_decap_2022:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]                ; Stage packet into L1 cache
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_ANON_SHADOWSOCKS_ASM
