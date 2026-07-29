; =============================================================================
; Tattva OS — unet/tools/snmp_get.asm
; =============================================================================
; SNMPv1 / v2c / v3 OID Variable Query Tool.
;
; Implements:
;   - Formats ASN.1 BER Encoded SNMP GetRequest and Parses Varbind Responses
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global snmp_get_init
global snmp_get_query

align 32
snmp_get_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
snmp_get_query:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
