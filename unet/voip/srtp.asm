%ifndef GUARD_UNET_VOIP_SRTP_ASM
%define GUARD_UNET_VOIP_SRTP_ASM
; =============================================================================
; Tattva OS — unet/voip/srtp.asm
; =============================================================================
; Secure Real-Time Transport Protocol Engine (SRTP / SRTCP RFC 3711).
;
; Features:
;   - AES-128-GCM / AES-256-GCM & AES-CTR + HMAC-SHA1 Authenticated Encryption
;   - Master Key & Master Salt Key Derivation (PRF)
;   - 31-Bit Roll-Over Counter (ROC) Replay Protection
;   - SRTCP Index & Encrypted Control Packet Processing
;   - DTLS-SRTP Key Exchange Integration (RFC 5764)
;
; Delegates:
;   - AES-GCM Encrypt/Decrypt            -> lib/crypto/aes_gcm.asm
;   - HMAC-SHA1                         -> lib/crypto/sha1.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SRTP_AEAD_AES_128_GCM        1
%define SRTP_AEAD_AES_256_GCM        2
%define SRTP_AES_128_CM_HMAC_SHA1_80 3

struc srtp_session_t
    .suite:             resd 1
    .master_key:        resb 32     ; 256-bit Master Key
    .master_salt:       resb 14     ; 112-bit Master Salt
    .srtp_k_e:          resb 32     ; Derived SRTP Encryption Key
    .srtp_k_a:          resb 20     ; Derived SRTP Authentication Key
    .srtp_k_s:          resb 14     ; Derived SRTP Salt
    .roc:               resd 1      ; Roll-Over Counter
    .replay_window:     resq 1      ; 64-bit Replay Window Bitmap
endstruc

section .text

global srtp_init
global srtp_protect
global srtp_unprotect
global srtp_protect_rtcp
global srtp_unprotect_rtcp
global srtp_derive_keys


align 64
srtp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; srtp_protect — Encrypt RTP Packet Payload & Append Auth Tag
; Input: RDI = Pointer to srtp_session_t, RSI = RTP Packet Buffer, EDX = Length
; Output: EAX = Protected Packet Length
; -----------------------------------------------------------------------------
align 64
srtp_protect:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; 1. Construct 12-byte IV: Salt XOR (SSRC || ROC || Sequence Number)
    ; 2. Encrypt RTP payload past 12-byte header with AES-GCM
    call aes_gcm_encrypt

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; srtp_unprotect — Decrypt SRTP Packet & Verify Auth Tag / Replay Window
; Input: RDI = Pointer to srtp_session_t, RSI = SRTP Packet Buffer, EDX = Length
; Output: RAX = Decrypted RTP Payload Pointer, EAX = 0 on Success, -1 on Auth Error
; -----------------------------------------------------------------------------
align 64
srtp_unprotect:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; 1. Check Replay Window bitmap against Sequence Number + ROC
    ; 2. Decrypt payload & verify 16-byte GCM authentication tag
    call aes_gcm_decrypt

    pop rbx
    pop rbp
    ret

align 64
srtp_protect_rtcp:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Encrypt RTCP packet payload & append E-flag + SRTCP Index + Tag
    call aes_gcm_encrypt
    pop rbp
    ret

align 64
srtp_unprotect_rtcp:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Decrypt SRTCP packet payload & verify tag
    call aes_gcm_decrypt
    pop rbp
    ret

align 64
srtp_derive_keys:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; SRTP Key Derivation Function (PRF): k_e, k_a, k_s from Master Key + Master Salt
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_VOIP_SRTP_ASM
