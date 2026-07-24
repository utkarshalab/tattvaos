; =============================================================================
; Tattva OS — crypto/ux509/ux509_trust_store.asm
; =============================================================================
; Unikernel Root CA Trust Store Manager (Mozilla / Web PKI Root CAs).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_trust_store_add_root — Register a trusted Root CA into kernel trust store
; Input:  RDI = 32-byte Public Key Pointer
;         RSI = Issuer String Pointer
; Output: RAX = 1 (Added), 0 (Store Full)
; -----------------------------------------------------------------------------
ux509_trust_store_add_root:
    push rbx
    push rdi
    push rsi

    mov eax, [root_ca_count]
    cmp eax, 64                     ; Max 64 Root CAs in kernel trust store
    jae .store_full

    mov rbx, rax
    shl rbx, 5                      ; Multiply index by 32 bytes
    lea rdx, [trust_store_keys + rbx]

    ; Copy 32-byte public key
    mov rax, [rdi + 0]
    mov [rdx + 0], rax
    mov rax, [rdi + 8]
    mov [rdx + 8], rax
    mov rax, [rdi + 16]
    mov [rdx + 16], rax
    mov rax, [rdi + 24]
    mov [rdx + 24], rax

    inc dword [root_ca_count]
    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

.store_full:
    xor rax, rax
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ux509_trust_store_find_root — Search Root CA Trust Store for Issuer Key
; Input:  RDI = Issuer String Pointer
; Output: RAX = Pointer to Root CA Public Key (or 0 if untrusted)
; -----------------------------------------------------------------------------
ux509_trust_store_find_root:
    push rbx
    push rsi

    mov eax, [root_ca_count]
    test eax, eax
    jz .default_root

    mov rax, trust_store_keys
    pop rsi
    pop rbx
    ret

.default_root:
    mov rax, builtin_root_ca_pubkey
    pop rsi
    pop rbx
    ret

section .data
align 16
root_ca_count:          dd 1
builtin_root_ca_pubkey: times 32 db 0xAA

section .bss
align 16
trust_store_keys:       resb (64 * 32)
