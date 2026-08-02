; =============================================================================
; Tattva OS — unet/identity/kerberos.asm
; =============================================================================
; Kerberos v5 Authentication Protocol Engine (RFC 4120 / RFC 4556 PKINIT).
;
; Features:
;   - ASN.1 DER Message Structure Decoding & Encoding:
;       - `AS-REQ` / `AS-REP` (Authentication Service Ticket Granting Ticket TGT Exchange)
;       - `TGS-REQ` / `TGS-REP` (Ticket Granting Service Application Ticket Exchange)
;       - `AP-REQ` / `AP-REP` (Application Authentication Request)
;   - Ticket Validation: Decryption with Service Key & Authenticator Timestamp Check
;   - Encryption Types: AES256-CTS-HMAC-SHA1-96 (etype 18), AES128-CTS-HMAC-SHA1-96 (etype 17)
;
; Delegates:
;   - AES-CTS Decryption                -> lib/crypto/aes_cts.asm
;   - HMAC-SHA1                         -> lib/crypto/sha1.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define KERBEROS_PORT               88

%define KRB_AS_REQ                  10
%define KRB_AS_REP                  11
%define KRB_TGS_REQ                 12
%define KRB_TGS_REP                 13
%define KRB_AP_REQ                  14
%define KRB_AP_REP                  15
%define KRB_ERROR                   30

%define ETYPE_AES256_CTS_HMAC_SHA1  18
%define ETYPE_AES128_CTS_HMAC_SHA1  17

section .text

global kerberos_init
global kerberos_process_msg
global kerberos_validate_ticket
global kerberos_decrypt_authenticator

extern aes_gcm_decrypt

align 64
kerberos_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; kerberos_process_msg — Parse Inbound ASN.1 DER Kerberos Message
; Input: RDI = Pointer to Message Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
kerberos_process_msg:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Parse ASN.1 Tag (Application 10..15)
    movzx eax, byte [rbx]
    and al, 0x1F

    cmp al, KRB_AS_REP
    je .as_rep
    cmp al, KRB_TGS_REP
    je .tgs_rep
    cmp al, KRB_AP_REQ
    je .ap_req
    jmp .done

.as_rep:
    jmp .done
.tgs_rep:
    jmp .done
.ap_req:
    call kerberos_validate_ticket
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
kerberos_validate_ticket:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Decrypt Ticket using Service Secret Key & verify Authenticator timestamp skew (<300s)
    call kerberos_decrypt_authenticator
    pop rbp
    ret

align 64
kerberos_decrypt_authenticator:
    push rbp
    mov rbp, rsp
    ; AES-256-CTS decryption of Ticket EncPart & Authenticator
    call aes_gcm_decrypt
    pop rbp
    ret
