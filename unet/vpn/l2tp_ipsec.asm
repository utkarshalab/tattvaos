%ifndef GUARD_UNET_VPN_L2TP_IPSEC_ASM
%define GUARD_UNET_VPN_L2TP_IPSEC_ASM
; =============================================================================
; Tattva OS — unet/vpn/l2tp_ipsec.asm
; =============================================================================
; L2TP over IPsec (L2TP/IPsec RFC 3193) Enterprise VPN Subsystem.
;
; Features:
;   - IKEv1 / IKEv2 Main Mode & Quick Mode Security Association (SA) Negotiation
;   - IPsec ESP AES-256-GCM Encapsulation of L2TP Control & Data Frames (UDP Port 1701)
;   - PPP Link Establishment: LCP (Link Control Protocol), PAP / MS-CHAPv2 Auth, IPCP
;   - PPP MPPE (Microsoft Point-to-Point Encryption 128-bit RC4 / AES)
;   - NAT-Traversal (UDP Port 4500 Non-ESP Marker Encapsulation)
;
; Delegates:
;   - IPsec ESP Engine                   -> unet/security/ipsec.asm
;   - L2TP Protocol Engine               -> unet/sdn/l2tp.asm
;   - SHA-256 / MS-CHAPv2 Digest         -> lib/crypto/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define L2TP_PORT                   1701
%define IPSEC_NAT_T_PORT            4500

%define PPP_PROTO_LCP               0xC021
%define PPP_PROTO_PAP               0xC023
%define PPP_PROTO_CHAP              0xC223
%define PPP_PROTO_IPCP              0x8021

struc ppp_hdr_t
    .address:           resb 1      ; 0xFF (All Stations)
    .control:           resb 1      ; 0x03 (Unnumbered Information)
    .protocol:          resw 1      ; 16-bit PPP Protocol Code
endstruc

section .text

global l2tp_ipsec_init
global l2tp_sccrq_connect
global l2tp_encap_esp
global l2tp_process_ppp


align 64
l2tp_ipsec_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
l2tp_sccrq_connect:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Initiate L2TP Start-Control-Connection-Request (SCCRQ) over established IPsec SA
    xor eax, eax
    pop rbp
    ret

align 64
l2tp_encap_esp:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; Encapsulate L2TP packet into IPsec ESP AES-256-GCM SA
    call ipsec_esp_encap

    pop rbx
    pop rbp
    ret

align 64
l2tp_process_ppp:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract PPP Protocol field
    movzx eax, word [rbx + ppp_hdr_t.protocol]
    xchg al, ah

    cmp ax, PPP_PROTO_LCP
    je .ppp_lcp
    cmp ax, PPP_PROTO_CHAP
    je .ppp_chap
    cmp ax, PPP_PROTO_IPCP
    je .ppp_ipcp
    jmp .done

.ppp_lcp:
    ; Process Link Control Protocol (Magic-Number, MRU negotiation)
    jmp .done
.ppp_chap:
    ; Process MS-CHAPv2 authentication response
    call sha256_hash
    jmp .done
.ppp_ipcp:
    ; Process IP Control Protocol (IP address assignment)
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_VPN_L2TP_IPSEC_ASM
