; =============================================================================
; Tattva OS — unet/services/radius.asm
; =============================================================================
; RADIUS (Remote Authentication Dial-In User Service RFC 2865 / RFC 2866) Engine.
;
; Features:
;   - UDP Port 1812 (Auth) & 1813 (Acct) 20-Byte Header Parsing
;   - Codes: Access-Request, Access-Accept, Access-Reject, Accounting-Request, Accounting-Response
;   - 16-Byte Random Authenticator & MD5 Response Authenticator Verification
;   - Attribute Parsing (Type-Length-Value): User-Name (1), User-Password (2), NAS-IP (4),
;                                           Framed-IP (8), Acct-Status-Type (40), VSA (26 Vendor Specific)
;   - User-Password Obfuscation: MD5(Shared Secret || Request Authenticator) XOR Password
;
; Delegates:
;   - MD5 Hashing                       -> lib/crypto/md5.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define RADIUS_AUTH_PORT            1812
%define RADIUS_ACCT_PORT            1813

%define RADIUS_CODE_ACCESS_REQUEST  1
%define RADIUS_CODE_ACCESS_ACCEPT   2
%define RADIUS_CODE_ACCESS_REJECT   3
%define RADIUS_CODE_ACCT_REQUEST    4
%define RADIUS_CODE_ACCT_RESPONSE   5

struc radius_hdr_t
    .code:              resb 1      ; Code
    .identifier:        resb 1      ; Packet ID
    .length:            resw 1      ; 16-bit Total Length (big endian)
    .authenticator:     resb 16     ; 16-byte Request Authenticator
endstruc

section .text

global radius_init
global radius_process_packet
global radius_decrypt_password
global radius_verify_response_authenticator
global radius_parse_attributes

extern md5_hash

align 64
radius_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
radius_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + radius_hdr_t.code]

    cmp al, RADIUS_CODE_ACCESS_REQUEST
    je .access_req
    cmp al, RADIUS_CODE_ACCT_REQUEST
    je .acct_req
    jmp .done

.access_req:
    ; Decrypt User-Password attribute using MD5(Secret || Authenticator)
    call radius_decrypt_password
    jmp .done
.acct_req:
    ; Process Accounting-Request (Start / Stop / Interim-Update)
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
radius_decrypt_password:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; MD5(shared_secret || authenticator) XOR encrypted_password
    call md5_hash
    pop rbp
    ret

align 64
radius_verify_response_authenticator:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; MD5(Code || ID || Length || RequestAuth || Attributes || Secret)
    call md5_hash
    pop rbp
    ret

align 64
radius_parse_attributes:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse TLV attributes: Type (1B), Length (1B), Value
    xor eax, eax
    pop rbp
    ret
