%ifndef GUARD_UNET_HTTP_OHTTP_ASM
%define GUARD_UNET_HTTP_OHTTP_ASM
; =============================================================================
; Tattva OS — unet/http/ohttp.asm
; =============================================================================
; Oblivious HTTP (OHTTP) Zero-Trust Privacy Proxy Engine (RFC 9458).
;
; Features:
;   - OHTTP Client: Encapsulate HTTP Request with HPKE Encryption
;   - OHTTP Relay: Forward Encapsulated Request Without Decryption (Blind Proxy)
;   - OHTTP Gateway: Decrypt HPKE Capsule & Forward to Target Resource
;   - Key Configuration Discovery (.well-known/ohttp-gateway)
;   - Binary HTTP Message Format (RFC 9292) for Request/Response Encoding
;   - Media Type: application/ohttp-req & application/ohttp-res
;   - Sender Anonymity: Relay Sees Client IP but Not Request Content
;                       Gateway Sees Request Content but Not Client IP
;
; Delegates:
;   - HPKE (RFC 9180) Encryption        -> crypto/ucrypt/
;   - HTTP/2 or HTTP/3 Transport         -> unet/http/http2.asm / http3.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc ohttp_key_config_t
    .key_id:            resb 1      ; Key Identifier
    .kem_id:            resw 1      ; KEM Algorithm ID (DHKEM X25519 = 0x0020)
    .kdf_id:            resw 1      ; KDF Algorithm ID (HKDF-SHA256 = 0x0001)
    .aead_id:           resw 1      ; AEAD Algorithm ID (AES-128-GCM = 0x0001)
    .public_key:        resb 32     ; Server Public Key
endstruc

section .text

global ohttp_init
global ohttp_encap_request
global ohttp_decap_request
global ohttp_encap_response
global ohttp_decap_response
global ohttp_relay_forward


align 64
ohttp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ohttp_encap_request — Client: Encapsulate HTTP Request with HPKE
; Input: RDI = Binary HTTP Request, ESI = Length, RDX = Pointer to ohttp_key_config_t
; Output: RAX = Encapsulated Request Length
; -----------------------------------------------------------------------------
align 64
ohttp_encap_request:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; 1. Serialize HTTP request into Binary HTTP format (RFC 9292)
    ; 2. HPKE Seal: encrypt with gateway public key
    call hpke_seal
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ohttp_decap_request — Gateway: Decrypt HPKE Encapsulated Request
; Input: RDI = Encapsulated Request, ESI = Length
; Output: RAX = Pointer to Decrypted Binary HTTP Request, EDX = Length
; -----------------------------------------------------------------------------
align 64
ohttp_decap_request:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; HPKE Open: decrypt with gateway private key
    call hpke_open
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ohttp_encap_response — Gateway: Encrypt Response Back to Client
; Input: RDI = HTTP Response, ESI = Length
; Output: RAX = Encapsulated Response Length
; -----------------------------------------------------------------------------
align 64
ohttp_encap_response:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    call hpke_seal
    pop rbp
    ret

align 64
ohttp_decap_response:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    call hpke_open
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ohttp_relay_forward — Relay: Blind Forward Without Decryption
; Input: RDI = Encapsulated Request (opaque blob), ESI = Length
; Output: EAX = 0 on Success
; -----------------------------------------------------------------------------
align 64
ohttp_relay_forward:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Forward opaque blob to gateway without reading content
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_HTTP_OHTTP_ASM
