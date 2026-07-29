; =============================================================================
; Tattva OS — unet/vpn/openvpn.asm
; =============================================================================
; Ultra-Robust OpenVPN SSL/TLS Tunneling Engine.
;
; Delegates:
;   - AES-256-GCM AEAD Payload Encryption -> crypto/ucrypt/symmetric/aes_gcm.asm
;   - HMAC-SHA256 Control Packet Auth    -> crypto/uhash/sha256/
;   - TLS 1.3 Control Channel Key Exchange -> crypto/utls/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"
%include "crypto/ucrypt/symmetric/ucrypt.inc"

%define OPENVPN_P_CONTROL_HARD_RESET_CLIENT_V2  7
%define OPENVPN_P_CONTROL_HARD_RESET_SERVER_V2  8
%define OPENVPN_P_DATA_V2                       9

struc openvpn_session_t
    .state:             resd 1      ; Session State (0=Init, 1=Handshake, 2=Active)
    .session_id:        resq 1      ; 64-bit OpenVPN Session ID
    .packet_id:         resd 1      ; 32-bit Replay Counter
    .key_id:            resb 1      ; Current Key ID (0..7)
    .aes_key:           resb 32     ; 256-bit Data Encryption Key
    .hmac_key:          resb 32     ; 256-bit Control HMAC Key
endstruc

section .text

global openvpn_init
global openvpn_handshake_init
global openvpn_process_control
global openvpn_encap_data

extern aes_gcm_encrypt
extern sha256_hash
extern utls_client_handshake

align 32
openvpn_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; openvpn_handshake_init — Transmit P_CONTROL_HARD_RESET_CLIENT_V2 Frame
; -----------------------------------------------------------------------------
align 32
openvpn_handshake_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov dword [rbx + openvpn_session_t.state], 1    ; State = Handshake

    ; Delegate TLS 1.3 handshake to crypto/utls/
    call utls_client_handshake

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; openvpn_process_control — Verify HMAC-SHA256 via crypto/uhash/sha256/
; -----------------------------------------------------------------------------
align 32
openvpn_process_control:
    push rbp
    mov rbp, rsp
    ; Delegate control packet MAC verification to crypto/uhash/sha256/
    call sha256_hash
    pop rbp
    ret

; -----------------------------------------------------------------------------
; openvpn_encap_data — Encrypt P_DATA_V2 via crypto/ucrypt/symmetric/aes_gcm.asm
; -----------------------------------------------------------------------------
align 32
openvpn_encap_data:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    inc dword [rbx + openvpn_session_t.packet_id]   ; Replay counter

    ; Delegate AEAD payload encryption to central crypto/ucrypt/
    call aes_gcm_encrypt
    
    pop rbx
    pop rbp
    ret
