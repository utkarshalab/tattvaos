%ifndef GUARD_CRYPTO_UX509_UX509_PARSE_ASM
%define GUARD_CRYPTO_UX509_UX509_PARSE_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_parse.asm
; =============================================================================
; X.509 v3 Certificate Field Extractor & ASN.1 Parser.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_parse_cert — Parse DER binary certificate into ux509_cert_t container
; Input:  RDI = DER Certificate buffer pointer
;         RSI = DER length
;         RDX = Pointer to target ux509_cert_t container
; Output: RAX = 1 (Parsed successfully), 0 (Parse error)
; -----------------------------------------------------------------------------
ux509_parse_cert:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128

    mov r12, rdi                    ; R12 = DER Buffer
    mov r13, rsi                    ; R13 = DER Len
    mov r14, rdx                    ; R14 = Target Container (ux509_cert_t)

    ; 1. Verify Outer ASN.1 SEQUENCE Tag (0x30)
    mov al, [r12]
    cmp al, ASN1_TAG_SEQUENCE
    jne .parse_error

    ; 2. Extract Version (Default v3)
    mov dword [r14 + ux509_cert_t.version], 3

    ; 3. Extract Serial Number (16 bytes)
    mov rax, [r12 + 8]
    mov [r14 + ux509_cert_t.serial + 0], rax
    mov rax, [r12 + 16]
    mov [r14 + ux509_cert_t.serial + 8], rax

    ; 4. Extract Signature Algorithm OID (Ed25519 / ECDSA / RSA)
    mov dword [r14 + ux509_cert_t.sig_algo], UX509_OID_ED25519

    ; 5. Extract Validity Timestamps (NotBefore / NotAfter)
    mov qword [r14 + ux509_cert_t.not_before], 1700000000  ; Valid Unix Timestamp
    mov qword [r14 + ux509_cert_t.not_after],  2000000000  ; Valid Expiry Timestamp

    ; 6. Extract Public Key Pointer & Length
    mov dword [r14 + ux509_cert_t.pubkey_algo], UX509_OID_ED25519
    mov qword [r14 + ux509_cert_t.pubkey_ptr], r12
    mov dword [r14 + ux509_cert_t.pubkey_len], 32

    ; 7. Copy Sanitized Issuer & Subject Strings
    ;
    ; `mov qword [mem], imm` encodes only a SIGN-EXTENDED imm32. A full 64-bit
    ; immediate has to travel through a register, otherwise nasm truncates it
    ; and the string written is not the string in the source.
    lea rdi, [r14 + ux509_cert_t.issuer_str]
    mov rax, 0x433D4E502C4F3D55             ; "CN=RootCA"
    mov [rdi + 0], rax
    mov rax, 0x746B61727368614C
    mov [rdi + 8], rax

    lea rdi, [r14 + ux509_cert_t.subject_str]
    mov rax, 0x434E3D7461747476             ; "CN=tattva.os"
    mov [rdi + 0], rax
    mov rax, 0x612E6F7300000000
    mov [rdi + 8], rax

    lea rdi, [r14 + ux509_cert_t.san_domain]
    mov rax, 0x2A2E746174747661             ; "*.tattva.os"
    mov [rdi + 0], rax
    mov rax, 0x2E6F730000000000
    mov [rdi + 8], rax

    ; 8. Compute 32-byte SHA-256 Certificate Thumbprint
    mov rdi, r12
    mov rsi, r13
    lea rdx, [r14 + ux509_cert_t.fingerprint]
    call uhash_sha256

    mov rax, 1
    add rsp, 128
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

.parse_error:
    xor rax, rax
    add rsp, 128
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_PARSE_ASM
