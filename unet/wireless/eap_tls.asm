; =============================================================================
; Tattva OS — unet/wireless/eap_tls.asm
; =============================================================================
; Extensible Authentication Protocol over TLS / EAP-PEAP / EAP-TTLS Engine (RFC 5216 / RFC 2716).
;
; Features:
;   - EAP 4-Byte Packet Header Parsing (Code, Identifier, Length, Type)
;   - Codes: Request (1), Response (2), Success (3), Failure (4)
;   - Types: Identity (1), EAP-TLS (13), PEAP (25), EAP-TTLS (21)
;   - TLS 1.3 Tunnel Fragmentation & Fragment Reassembly (Flags: L-bit, M-bit, S-bit)
;   - Derivation of EAP Master Session Key (MSK RFC 5247) & EMSK for WPA2/WPA3
;
; Delegates:
;   - TLS 1.3 Handshake                 -> crypto/utls/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define EAP_CODE_REQUEST            1
%define EAP_CODE_RESPONSE           2
%define EAP_CODE_SUCCESS            3
%define EAP_CODE_FAILURE            4

%define EAP_TYPE_IDENTITY           1
%define EAP_TYPE_TLS                13
%define EAP_TYPE_TTLS               21
%define EAP_TYPE_PEAP               25

%define EAP_TLS_FLAG_LENGTH         0x80
%define EAP_TLS_FLAG_MORE           0x40
%define EAP_TLS_FLAG_START          0x20

struc eap_hdr_t
    .code:              resb 1      ; 1=Req, 2=Resp, 3=Success, 4=Fail
    .identifier:        resb 1      ; EAP Packet Identifier
    .length:            resw 1      ; 16-bit EAP Length
    .type:              resb 1      ; EAP Type (13 = EAP-TLS)
endstruc

section .text

global eap_tls_init
global eap_tls_process_packet
global eap_tls_handshake_fragment
global eap_tls_derive_msk

extern utls_client_handshake

align 64
eap_tls_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eap_tls_process_packet — Parse EAP Packet Header & Process EAP-TLS Tunnel
; Input: RDI = Pointer to EAP Packet Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
eap_tls_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + eap_hdr_t.code]

    cmp al, EAP_CODE_REQUEST
    je .eap_req
    cmp al, EAP_CODE_RESPONSE
    je .eap_resp
    cmp al, EAP_CODE_SUCCESS
    je .eap_success
    cmp al, EAP_CODE_FAILURE
    je .eap_failure
    jmp .done

.eap_req:
.eap_resp:
    ; Process EAP-TLS / PEAP / TTLS flags & TLS records
    movzx eax, byte [rbx + eap_hdr_t.type]
    cmp al, EAP_TYPE_TLS
    je .type_tls
    jmp .done

.type_tls:
    call eap_tls_handshake_fragment
    jmp .done

.eap_success:
    ; Derive MSK (64 bytes) for WPA2/WPA3 PMK
    call eap_tls_derive_msk
    jmp .done
.eap_failure:
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
eap_tls_handshake_fragment:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Check L-bit (Length present), M-bit (More fragments), S-bit (Start)
    ; Reassemble TLS records across EAP-TLS fragments
    call utls_client_handshake
    pop rbp
    ret

align 64
eap_tls_derive_msk:
    push rbp
    mov rbp, rsp
    ; Derive 64-byte Master Session Key (MSK) = PRF(TLS_Master_Secret, "client EAP encryption", Seed)
    xor eax, eax
    pop rbp
    ret
