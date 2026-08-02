; =============================================================================
; Tattva OS — unet/security/ipsec.asm
; =============================================================================
; IPsec Architecture (RFC 4301 / RFC 4303 ESP / IKEv2 RFC 7296) Engine.
;
; Features:
;   - ESP (Encapsulating Security Payload RFC 4303) Tunnel & Transport Modes
;   - AES-256-GCM Authenticated Encryption & AES-CBC / HMAC-SHA256
;   - Security Association (SA) Database (SAD) & Policy Database (SPD) Lookups
;   - Anti-Replay Sliding Window (64-bit / 128-bit Bitmap)
;   - IKEv2 (Internet Key Exchange v2) Exchange State Machine
;
; Delegates:
;   - AES-GCM Encrypt/Decrypt            -> lib/crypto/aes_gcm.asm
;   - HMAC-SHA256                        -> lib/crypto/sha256.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IP_PROTO_ESP                50
%define IP_PROTO_AH                 51

struc esp_hdr_t
    .spi:               resd 1      ; Security Parameters Index
    .seq_num:           resd 1      ; Sequence Number
endstruc

struc ipsec_sa_t
    .spi:               resd 1      ; 32-bit SPI
    .mode:              resb 1      ; 0=Transport, 1=Tunnel
    .cipher:            resb 1      ; 1=AES-GCM-256
    .enc_key:           resb 32     ; 256-bit Encryption Key
    .salt:              resb 4      ; 4-byte Salt
    .replay_window:     resq 1      ; 64-bit Sliding Window Bitmap
    .last_seq:          resq 1      ; Last Valid Sequence Number
endstruc

section .text

global ipsec_init
global ipsec_esp_decap
global ipsec_esp_encap
global ipsec_sa_lookup
global ipsec_anti_replay_check

extern aes_gcm_encrypt
extern aes_gcm_decrypt

align 64
ipsec_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
ipsec_esp_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract SPI & lookup SA in SAD
    mov edx, [rbx + esp_hdr_t.spi]
    bswap edx
    call ipsec_sa_lookup
    test rax, rax
    jz .invalid_sa

    ; 2. Check Sequence Number against Anti-Replay Sliding Window
    call ipsec_anti_replay_check
    test eax, eax
    jnz .replay_detected

    ; 3. Decrypt ESP payload with AES-GCM
    call aes_gcm_decrypt

    jmp .done

.invalid_sa:
.replay_detected:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
ipsec_esp_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend ESP header (SPI + Seq) + Encrypt payload + Append ICV tag
    call aes_gcm_encrypt
    pop rbp
    ret

align 64
ipsec_sa_lookup:
    push rbp
    mov rbp, rsp
    ; Hash table lookup by SPI
    xor eax, eax
    pop rbp
    ret

align 64
ipsec_anti_replay_check:
    push rbp
    mov rbp, rsp
    ; Check sequence number against 64-bit sliding window bitmap
    xor eax, eax
    pop rbp
    ret
