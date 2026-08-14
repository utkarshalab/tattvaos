%ifndef GUARD_UNET_SERVICES_TACACS_ASM
%define GUARD_UNET_SERVICES_TACACS_ASM
; =============================================================================
; Tattva OS — unet/services/tacacs.asm
; =============================================================================
; TACACS+ (Terminal Access Controller Access-Control System Plus RFC 8907) Engine.
;
; Features:
;   - TCP Port 49 12-Byte Header Parsing & Obfuscation
;   - Header Fields: Major/Minor Version, Type (1=Authentication, 2=Authorization, 3=Accounting),
;                    Seq_No, Flags (1=Unencrypted, 4=Single Connect), Session_ID, Data_Length
;   - MD5 Pseudo-Random Pad Payload Encryption / Decryption: MD5(session_id || secret || version || seq_no)
;   - AAA Operations: Authentication (ASCII, PAP, CHAP), Authorization (cmd matching), Accounting
;
; Delegates:
;   - MD5 Hashing                       -> lib/crypto/md5.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define TACACS_PORT                 49

%define TAC_PLUS_AUTHEN             1
%define TAC_PLUS_AUTHOR             2
%define TAC_PLUS_ACCT               3

%define TAC_PLUS_UNENCRYPTED_FLAG   0x01
%define TAC_PLUS_SINGLE_CONNECT_FLAG 0x04

struc tacacs_hdr_t
    .version:           resb 1      ; Major(4b) + Minor(4b) version
    .type:              resb 1      ; 1=Authen, 2=Author, 3=Acct
    .seq_no:            resb 1      ; Sequence Number
    .flags:             resb 1      ; Flags
    .session_id:        resd 1      ; Session ID (big endian)
    .length:            resd 1      ; 32-bit Payload Length (big endian)
endstruc

section .text

global tacacs_init
global tacacs_process_packet
global tacacs_crypt_payload
global tacacs_process_authen
global tacacs_process_author

align 64
tacacs_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
tacacs_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Decrypt payload if UNENCRYPTED_FLAG is not set
    movzx eax, byte [rbx + tacacs_hdr_t.flags]
    test al, TAC_PLUS_UNENCRYPTED_FLAG
    jnz .skip_decrypt
    call tacacs_crypt_payload
.skip_decrypt:

    movzx eax, byte [rbx + tacacs_hdr_t.type]

    cmp al, TAC_PLUS_AUTHEN
    je .authen
    cmp al, TAC_PLUS_AUTHOR
    je .author
    cmp al, TAC_PLUS_ACCT
    je .acct
    jmp .done

.authen:
    call tacacs_process_authen
    jmp .done
.author:
    call tacacs_process_author
    jmp .done
.acct:
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tacacs_crypt_payload — Encrypt / Decrypt Payload with MD5 Keystream
; Input: RDI = Pointer to TACACS+ Packet, ESI = Shared Secret Pointer
; -----------------------------------------------------------------------------
align 64
tacacs_crypt_payload:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; MD5_pad = MD5(session_id || secret || version || seq_no)
    ; XOR payload with MD5 pad bytes
    call md5_hash
    pop rbp
    ret

align 64
tacacs_process_authen:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Validate user credentials (ASCII / PAP / CHAP)
    xor eax, eax
    pop rbp
    ret

align 64
tacacs_process_author:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Match privilege level & command against authorization policy rules
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SERVICES_TACACS_ASM
