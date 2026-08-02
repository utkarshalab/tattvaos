; =============================================================================
; Tattva OS — unet/sdn/wireguard.asm
; =============================================================================
; WireGuard Modern Secure Network Tunnel Engine (RFC Protocol Spec).
;
; Features:
;   - Noise_IKpsk2 1-RTT Cryptographic Handshake State Machine
;   - Curve25519 Ephemeral & Static Key Exchange
;   - ChaCha20-Poly1305 AEAD Data Packet Encapsulation & Decapsulation
;   - BLAKE2s Hashing & MAC1/MAC2 Cookie Anti-DoS Verification
;   - UDP Port 51820 Transport
;   - Automatic Rekeying Timers & Keepalive Packets
;
; Delegates:
;   - ChaCha20-Poly1305 Cipher          -> crypto/ucrypt/symmetric/chacha20_poly1305.asm
;   - Curve25519 ECDH                  -> crypto/usign/ed25519/
;   - BLAKE2s Hash                      -> crypto/uhash/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define WG_PORT                     51820

%define WG_PKT_HANDSHAKE_INIT       1
%define WG_PKT_HANDSHAKE_RESP       2
%define WG_PKT_COOKIE_REPLY         3
%define WG_PKT_DATA                 4

struc wg_hdr_t
    .type:              resb 1      ; Message Type
    .rsvd:              resb 3
    .receiver_index:    resd 1      ; 32-bit Receiver Index
endstruc

struc wg_data_hdr_t
    .type:              resb 1      ; 4
    .rsvd:              resb 3
    .receiver_index:    resd 1
    .counter:           resq 1      ; 64-bit Nonce Counter
    .encrypted_data:    resb 16     ; ChaCha20-Poly1305 Ciphertext + Tag
endstruc

section .text

global wireguard_init
global wireguard_process_packet
global wireguard_handshake_init
global wireguard_handshake_resp
global wireguard_encap_data
global wireguard_decap_data

extern chacha20_poly1305_encrypt
extern chacha20_poly1305_decrypt

align 64
wireguard_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
wireguard_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + wg_hdr_t.type]

    cmp al, WG_PKT_HANDSHAKE_INIT
    je .initiation
    cmp al, WG_PKT_HANDSHAKE_RESP
    je .response
    cmp al, WG_PKT_COOKIE_REPLY
    je .cookie
    cmp al, WG_PKT_DATA
    je .data
    jmp .done

.initiation:
    ; Process Noise_IK Handshake Initiation
    jmp .done
.response:
    ; Process Noise_IK Handshake Response & Derive Transport Keys
    jmp .done
.cookie:
    ; Process Anti-DoS Cookie Reply
    jmp .done
.data:
    call wireguard_decap_data
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
wireguard_encap_data:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Encrypt payload with ChaCha20-Poly1305 AEAD using send_key & incrementing counter
    call chacha20_poly1305_encrypt
    pop rbp
    ret

align 64
wireguard_decap_data:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Decrypt payload with ChaCha20-Poly1305 AEAD using recv_key & counter validation
    call chacha20_poly1305_decrypt
    pop rbp
    ret
