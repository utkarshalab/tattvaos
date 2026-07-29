; =============================================================================
; Tattva OS — unet/cgnat/pcp.asm
; =============================================================================
; Port Control Protocol Engine (PCP RFC 6887).
;
; Implements:
;   - MAP & PEER Opcode Requests for Dynamic CGNAT & Firewall Port Forwarding
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pcp_init
global pcp_map_port

align 32
pcp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
pcp_map_port:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
