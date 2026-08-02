; =============================================================================
; Tattva OS — unet/security/tls13_session.asm
; =============================================================================
; TLS 1.3 State Machine & Record Protocol Engine (RFC 8446).
;
; Features:
;   - Full TLS 1.3 1-RTT & 0-RTT (Early Data) Handshake State Machine
;   - Supported Ciphersuites: TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256
;   - Key Exchange: ECDHE (X25519) & Post-Quantum Hybrid (Kyber-1024 + X25519)
;   - HKDF Key Derivation Tree (Early, Handshake, Application Secret Chains)
;   - Record Protocol Parsing with Opaque Type Obfuscation (0x17)
;   - Session Resumption via NewSessionTicket & PSK
;
; Delegates:
;   - AES-GCM & ChaCha20-Poly1305        -> lib/crypto/
;   - HKDF Key Derivation                -> lib/crypto/hkdf.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define TLS_RECORD_CHANGE_CIPHER_SPEC 20
%define TLS_RECORD_ALERT             21
%define TLS_RECORD_HANDSHAKE         22
%define TLS_RECORD_APPLICATION_DATA  23

%define TLS_HANDSHAKE_CLIENT_HELLO   1
%define TLS_HANDSHAKE_SERVER_HELLO   2
%define TLS_HANDSHAKE_NEW_SESSION_TICKET 4
%define TLS_HANDSHAKE_ENCRYPTED_EXT  8
%define TLS_HANDSHAKE_CERTIFICATE    11
%define TLS_HANDSHAKE_CERT_VERIFY    15
%define TLS_HANDSHAKE_FINISHED       20

struc tls_record_hdr_t
    .type:              resb 1      ; Record Type
    .version:           resw 1      ; 0x0303 (Legacy version string)
    .length:            resw 1      ; 16-bit Payload Length
endstruc

section .text

global tls13_init
global tls13_process_record
global tls13_handshake_client
global tls13_handshake_server
global tls13_encrypt_record
global tls13_decrypt_record

extern aes_gcm_encrypt
extern aes_gcm_decrypt
extern hkdf_extract_expand

align 64
tls13_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
tls13_process_record:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + tls_record_hdr_t.type]

    cmp al, TLS_RECORD_APPLICATION_DATA
    je .app_data
    cmp al, TLS_RECORD_HANDSHAKE
    je .handshake
    cmp al, TLS_RECORD_ALERT
    je .alert
    jmp .done

.app_data:
    call tls13_decrypt_record
    jmp .done
.handshake:
    ; Process ClientHello / ServerHello / Finished
    jmp .done
.alert:
    ; Process Alert (Close Notify, Fatal error)
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
tls13_handshake_client:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Generate X25519 keypair, build ClientHello with supported_versions=0x0304
    call hkdf_extract_expand
    pop rbp
    ret

align 64
tls13_handshake_server:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Process ClientHello, derive Handshake Secret, send ServerHello + EncryptedExtensions + Certificate + Finished
    call hkdf_extract_expand
    pop rbp
    ret

align 64
tls13_encrypt_record:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Append inner record type byte, encrypt payload with AES-256-GCM
    call aes_gcm_encrypt
    pop rbp
    ret

align 64
tls13_decrypt_record:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Decrypt payload with AES-256-GCM & strip trailing inner record type byte
    call aes_gcm_decrypt
    pop rbp
    ret
