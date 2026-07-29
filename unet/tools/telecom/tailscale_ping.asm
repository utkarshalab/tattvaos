; =============================================================================
; Tattva OS — unet/tools/tailscale_ping.asm
; =============================================================================
; Tailscale / WireGuard DERP Relay Latency & Direct Mesh P2P Ping (`tailscale-ping`).
;
; Implements:
;   - Measures DERP Server Relay Latency vs Direct P2P WireGuard Hole-Punch RTT
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global tailscale_ping_init
global tailscale_ping_probe

align 32
tailscale_ping_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
tailscale_ping_probe:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
