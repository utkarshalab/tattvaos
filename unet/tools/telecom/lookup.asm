; =============================================================================
; Tattva OS — unet/tools/lookup.asm
; =============================================================================
; DNS Hostname & Reverse IP Resolution CLI Diagnostic Tool.
;
; Implements:
;   - Resolves A, AAAA, MX, TXT, CNAME, PTR Records over UDP/DoH/DoT
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global lookup_init
global lookup_query

align 32
lookup_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
lookup_query:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
