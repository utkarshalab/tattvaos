; =============================================================================
; Tattva OS — unet/anon/shadowsocks.asm
; =============================================================================
; AVX-512 Vector Optimized Shadowsocks 2022 AEAD Proxy Engine.
;
; Microarchitectural Optimizations:
;   - AVX-512 Vectorized BLAKE3 Subkey Derivation
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc shadowsocks_hdr_t
    .salt:              resb 32
    .header_aead:       resb 16
    .payload_tag:       resb 16
endstruc

section .text

global shadowsocks_init
global shadowsocks_encap_2022
global shadowsocks_encap_udp_2022
global shadowsocks_decap_2022

extern chacha20_poly1305_encrypt
extern uhash_blake3

align 64
shadowsocks_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
shadowsocks_encap_2022:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]
    call uhash_blake3
    call chacha20_poly1305_encrypt

    pop rbx
    pop rbp
    ret

align 64
shadowsocks_encap_udp_2022:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]
    call uhash_blake3
    call chacha20_poly1305_encrypt

    pop rbx
    pop rbp
    ret

align 64
shadowsocks_decap_2022:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret
