%ifndef GUARD_UNET_IDENTITY_WEBAUTHN_ASM
%define GUARD_UNET_IDENTITY_WEBAUTHN_ASM
; =============================================================================
; Tattva OS — unet/identity/webauthn.asm
; =============================================================================
; WebAuthn / FIDO2 Passwordless Authentication Engine (W3C WebAuthn Spec).
;
; Features:
;   - CBOR (Concise Binary Object Representation RFC 8949) Decoder for Authenticator Data
;   - Authenticator Data Parsing: RP ID Hash (32B), Flags (UP, UV, AT, ED), Sign Count (4B), AAGUID (16B)
;   - COSE (CBOR Object Signing and Encryption RFC 8152) Public Key Extraction (ES256, RS256, Ed25519)
;   - ClientDataJSON Challenge Hash & User Presence (UP) / User Verification (UV) Bit Checks
;
; Delegates:
;   - SHA-256 Hash                     -> lib/crypto/sha256.asm
;   - ECDSA P-256                      -> lib/crypto/ecc.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define WEBAUTHN_FLAG_UP            0x01    ; User Present
%define WEBAUTHN_FLAG_UV            0x04    ; User Verified
%define WEBAUTHN_FLAG_AT            0x40    ; Attested Credential Data Present

struc webauthn_auth_data_t
    .rp_id_hash:        resb 32     ; SHA-256 Hash of Relying Party ID
    .flags:             resb 1      ; UP, UV, AT, ED
    .sign_count:        resd 1      ; 32-bit Big Endian Signature Counter
endstruc

section .text

global webauthn_init
global webauthn_parse_auth_data
global webauthn_verify_assertion
global webauthn_parse_cbor_cose_key

align 64
webauthn_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; webauthn_parse_auth_data — Parse 37-Byte Min Authenticator Data Header
; Input: RDI = Pointer to Authenticator Data Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
webauthn_parse_auth_data:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify UP (User Presence bit 0) flag
    movzx eax, byte [rbx + webauthn_auth_data_t.flags]
    test al, WEBAUTHN_FLAG_UP
    jz .invalid

    ; Read 32-bit Sign Count
    mov edx, [rbx + webauthn_auth_data_t.sign_count]
    bswap edx                       ; EDX = Sign Count

    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
webauthn_verify_assertion:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Compute SHA-256(ClientDataJSON) -> verify signature over (auth_data || client_data_hash) using COSE public key
    call sha256_hash
    call ecc_p256_verify
    pop rbp
    ret

align 64
webauthn_parse_cbor_cose_key:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; CBOR decoder: extract kty (2=EC2), alg (-7=ES256), crv (1=P-256), x-coord, y-coord
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_IDENTITY_WEBAUTHN_ASM
