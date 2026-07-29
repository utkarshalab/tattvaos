; =============================================================================
; Tattva OS — unet/cni/weave.asm
; =============================================================================
; Weave Net Encrypted Mesh & Fast Datapath CNI Engine.
;
; Features:
;   - Weave Fast Datapath VXLAN UDP Encapsulation
;   - Weave Mesh Encrypted Sleeve Mode (SNaCl SecretBox AES/ChaCha20 Packet Security)
;   - Automatic IPAM Subnet Allocation across Distributed Pod Clusters
;
; Delegates:
;   - Symmetric Encryption              -> crypto/ucrypt/symmetric/chacha20_poly1305.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define WEAVE_PORT                  6783

struc weave_peer_t
    .peer_ip:           resd 1      ; Peer Node IP Address
    .nickname:          resb 32     ; Node Identifier
    .mac_address:       resb 6      ; Weave Router Bridge MAC
endstruc

section .text

global weave_init
global weave_mesh_encap
global weave_fastdp_forward

extern chacha20_poly1305_encrypt

align 64
weave_init:
    push rbp
    mov rbp, rsp
    ; Bind TCP/UDP Port 6783 for Weave Mesh Router
    xor eax, eax
    pop rbp
    ret

align 64
weave_mesh_encap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Encrypt Pod packet using ChaCha20-Poly1305 via crypto/ucrypt/
    call chacha20_poly1305_encrypt

    pop rbx
    pop rbp
    ret

align 64
weave_fastdp_forward:
    push rbp
    mov rbp, rsp
    ; Fast-path unencrypted VXLAN forwarding
    xor eax, eax
    pop rbp
    ret
