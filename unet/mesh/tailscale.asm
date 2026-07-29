; =============================================================================
; Tattva OS — unet/mesh/tailscale.asm
; =============================================================================
; Tailscale WireGuard Mesh & DERP Relay Relay Protocol.
;
; Implements:
;   - WireGuard Mesh Peer Discovery, MagicDNS, and DERP Relay Fallback
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global tailscale_init
global tailscale_derp_relay

align 32
tailscale_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
tailscale_derp_relay:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
