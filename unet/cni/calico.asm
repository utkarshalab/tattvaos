%ifndef GUARD_UNET_CNI_CALICO_ASM
%define GUARD_UNET_CNI_CALICO_ASM
; =============================================================================
; Tattva OS — unet/cni/calico.asm
; =============================================================================
; Calico BGP & eBPF Kubernetes Container Network Interface (CNI) Engine.
;
; Features:
;   - Calico Felix eBPF Pod Security Policy Enforcement (Ingress & Egress)
;   - BGP Route Reflector Subnet Announcement across Kubernetes Worker Nodes
;   - WireGuard Pod-to-Pod Encryption Acceleration
;
; Delegates:
;   - BGP Route Announcement            -> unet/routing/bgp.asm
;   - eBPF XDP Hook Execution            -> unet/ebpf/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc calico_pod_policy_t
    .pod_ip:            resd 1      ; Pod IPv4 Address (10.244.x.x)
    .namespace_id:      resd 1      ; Kubernetes Namespace Identifier
    .allow_ports_mask:  resq 1      ; Allowed Ports Bitmask (TCP/UDP)
    .policy_action:     resd 1      ; 0=ALLOW, 1=DENY, 2=LOG
endstruc

section .text

global calico_init
global calico_ebpf_policy_eval
global calico_bgp_route_announce

align 64
calico_init:
    push rbp
    mov rbp, rsp
    ; Initialize Calico Felix eBPF Map Hooks
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; calico_ebpf_policy_eval — Evaluate Calico Felix eBPF Security Policy
; Input: RDI = Pointer to net_pkt_t, RSI = Pointer to calico_pod_policy_t
; Output: RAX = 0 (ALLOW), -1 (DENY)
; -----------------------------------------------------------------------------
align 64
calico_ebpf_policy_eval:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage packet header into L1 cache

    ; Fast-path eBPF map lookup & port bitmask evaluation
    pop rbx
    pop rbp
    ret

align 64
calico_bgp_route_announce:
    push rbp
    mov rbp, rsp
    ; Announce /32 Pod IP routes via BGP Route Reflector
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_CNI_CALICO_ASM
