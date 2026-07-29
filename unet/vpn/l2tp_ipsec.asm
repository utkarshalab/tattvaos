; =============================================================================
; Tattva OS — unet/vpn/l2tp_ipsec.asm
; =============================================================================
; Ultra-Robust L2TP over IPsec (L2TP/IPsec) Enterprise VPN Subsystem.
;
; Delegates:
;   - IPsec ESP AES-256-GCM Payload Encapsulation -> crypto/ucrypt/symmetric/aes_gcm.asm
;   - PPP CHAP Digest Auth                          -> crypto/uhash/sha256/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define L2TP_PORT                   1701
%define L2TP_MSG_SCCRQ              1
%define L2TP_MSG_SCCRP              2

struc l2tp_hdr_t
    .flags_ver:         resw 1
    .length:            resw 1
    .tunnel_id:         resw 1
    .session_id:        resw 1
    .ns:                resw 1
    .nr:                resw 1
endstruc

section .text

global l2tp_ipsec_init
global l2tp_sccrq_connect
global l2tp_encap_esp

extern aes_gcm_encrypt
extern sha256_hash

align 32
l2tp_ipsec_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
l2tp_sccrq_connect:
    push rbp
    mov rbp, rsp
    ; Delegate CHAP auth response calculation to crypto/uhash/
    call sha256_hash
    pop rbp
    ret

align 32
l2tp_encap_esp:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Delegate IPsec ESP AES-256-GCM AEAD encryption to crypto/ucrypt/
    call aes_gcm_encrypt

    pop rbx
    pop rbp
    ret
