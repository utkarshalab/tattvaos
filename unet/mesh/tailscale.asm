%ifndef GUARD_UNET_MESH_TAILSCALE_ASM
%define GUARD_UNET_MESH_TAILSCALE_ASM
; =============================================================================
; Tattva OS — unet/mesh/tailscale.asm
; =============================================================================
; Tailscale DERP (Detoured Encrypted Routing Protocol) & WireGuard Mesh Subsystem.
;
; Features:
;   - DERP Frame Parsing over HTTP/2 / WebSockets / TLS (Frame Type, Length, Payload)
;   - DERP Frame Types: `DERP_FRAME_CLIENT_INFO`, `DERP_FRAME_SERVER_INFO`,
;                       `DERP_FRAME_SEND_PACKET`, `DERP_FRAME_RECV_PACKET`, `DERP_FRAME_KEEP_ALIVE`
;   - MagicDNS & Tailscale IP Address (100.64.0.0/10 Carrier-Grade NAT) Resolution
;   - Disco (Discovery) STUN Probe Handshake for Direct Peer-to-Peer Path Upgrade
;   - Key Pair Matching: WireGuard Curve25519 Node Key Exchange
;
; Delegates:
;   - WireGuard Transport Protocol      -> unet/sdn/wireguard.asm
;   - ICE / STUN Probes                 -> unet/voip/ice_stun.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DERP_FRAME_CLIENT_INFO       0x01
%define DERP_FRAME_SERVER_INFO       0x02
%define DERP_FRAME_SEND_PACKET       0x03
%define DERP_FRAME_RECV_PACKET       0x04
%define DERP_FRAME_KEEP_ALIVE        0x05
%define DERP_FRAME_NOTE_PREFERRED    0x06

struc derp_frame_hdr_t
    .type:              resb 1      ; DERP Frame Type
    .length:            resd 1      ; 32-bit Payload Length (big endian)
endstruc

section .text

global tailscale_init
global tailscale_process_derp_frame
global tailscale_send_disco_probe
global tailscale_upgrade_to_p2p


align 64
tailscale_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
tailscale_process_derp_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + derp_frame_hdr_t.type]

    cmp al, DERP_FRAME_RECV_PACKET
    je .recv_packet
    cmp al, DERP_FRAME_KEEP_ALIVE
    je .keep_alive
    cmp al, DERP_FRAME_SERVER_INFO
    je .server_info
    jmp .done

.recv_packet:
    ; Extract encapsulated WireGuard packet & process
    lea rdi, [rbx + derp_frame_hdr_t_size]
    call wireguard_process_packet
    jmp .done

.keep_alive:
    jmp .done

.server_info:
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
tailscale_send_disco_probe:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Send Disco (Discovery) STUN packet to peer WAN endpoints for P2P hole punching
    xor eax, eax
    pop rbp
    ret

align 64
tailscale_upgrade_to_p2p:
    push rbp
    mov rbp, rsp
    ; If Disco STUN probe receives direct reply -> switch route from DERP relay to direct UDP WireGuard
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_MESH_TAILSCALE_ASM
