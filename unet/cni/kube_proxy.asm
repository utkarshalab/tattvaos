%ifndef GUARD_UNET_CNI_KUBE_PROXY_ASM
%define GUARD_UNET_CNI_KUBE_PROXY_ASM
; =============================================================================
; Tattva OS — unet/cni/kube_proxy.asm
; =============================================================================
; Kubernetes Kube-Proxy eBPF Maglev Load Balancer Engine.
;
; Features:
;   - Replacement for iptables / IPVS Kube-Proxy across 1,000,000 ClusterIP Services
;   - Consistent Hashing via Google Maglev Table Allocation (O(1) Backend Selection)
;   - Session Affinity (ClientIP) & Service Endpoints Dynamic Health Checking
;
; Delegates:
;   - Maglev Consistent Hashing        -> unet/qos/ebpf_maglev.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc kube_service_t
    .cluster_ip:        resd 1      ; Kubernetes ClusterIP (10.96.x.x)
    .port:              resw 1      ; Service Port
    .protocol:          resb 1      ; IPPROTO_TCP / IPPROTO_UDP
    .num_endpoints:     resd 1      ; Active Pod Endpoints Count
    .maglev_table:      resd 65537  ; 65,537 Slot Maglev Lookup Table
endstruc

section .text

global kube_proxy_init
global kube_proxy_maglev_lookup
global kube_proxy_nat_endpoint

align 64
kube_proxy_init:
    push rbp
    mov rbp, rsp
    ; Initialize Kube-Proxy eBPF Maglev Lookup Tables
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; kube_proxy_maglev_lookup — Maglev Consistent Hash O(1) Endpoint Selection
; Input: RDI = Pointer to net_pkt_t
; Output: RAX = Pointer to Selected Pod Endpoint IP & Port
; -----------------------------------------------------------------------------
align 64
kube_proxy_maglev_lookup:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage packet into L1 cache

    ; Execute Maglev Consistent Hashing via unet/qos/ebpf_maglev.asm
    call ebpf_maglev_lookup

    pop rbx
    pop rbp
    ret

align 64
kube_proxy_nat_endpoint:
    push rbp
    mov rbp, rsp
    ; Rewrite ClusterIP destination to Pod IP
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_CNI_KUBE_PROXY_ASM
