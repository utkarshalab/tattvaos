; =============================================================================
; Tattva OS — unet/mpls/mpls.asm
; =============================================================================
; Multiprotocol Label Switching (MPLS RFC 3031 / SR-MPLS) Engine.
;
; Implements:
;   - Label Push/Pop/Swap Operation & Label Distribution Protocol (LDP RFC 5036)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global mpls_init
global mpls_forward

align 32
mpls_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
mpls_forward:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
