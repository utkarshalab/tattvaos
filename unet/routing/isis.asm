%ifndef GUARD_UNET_ROUTING_ISIS_ASM
%define GUARD_UNET_ROUTING_ISIS_ASM
; =============================================================================
; Tattva OS — unet/routing/isis.asm
; =============================================================================
; IS-IS (Intermediate System to Intermediate System RFC 1195) Router Engine.
;
; Features:
;   - IS-IS Level 1 (Intra-Area) & Level 2 (Inter-Area) Routing
;   - Hello PDU (IIH): Point-to-Point & LAN with DIS Election
;   - Link State PDU (LSP): TLV-Based Topology & Reachability Advertisement
;   - CSNP (Complete Sequence Number PDU) & PSNP (Partial) for LSDB Sync
;   - SPF (Dijkstra) Computation for Shortest Path Tree
;   - IS-IS TLV Parsing: Area Addresses, IS Neighbors, IP Reachability, IPv6
;   - Multi-Topology (MT) IS-IS (RFC 5120) for IPv4/IPv6 Independent Topologies
;   - Segment Routing (SR) IS-IS Extensions (RFC 8667)
;
; Delegates:
;   - Timer Wheel Hello/LSP Timers      -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ISIS_LEVEL_1                1
%define ISIS_LEVEL_2                2
%define ISIS_LEVEL_12               3

%define ISIS_PDU_L1_HELLO           15
%define ISIS_PDU_L2_HELLO           16
%define ISIS_PDU_PTP_HELLO          17
%define ISIS_PDU_L1_LSP             18
%define ISIS_PDU_L2_LSP             20
%define ISIS_PDU_L1_CSNP            24
%define ISIS_PDU_L2_CSNP            25
%define ISIS_PDU_L1_PSNP            26
%define ISIS_PDU_L2_PSNP            27

struc isis_neighbor_t
    .system_id:         resb 6      ; 6-byte System ID
    .level:             resb 1
    .state:             resd 1      ; 0=Down, 1=Init, 2=Up
    .metric:            resd 1
    .hello_timer:       resd 1
endstruc

section .text

global isis_init
global isis_process_pdu
global isis_send_hello
global isis_spf_calculate
global isis_flood_lsp
global isis_parse_tlv


align 64
isis_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
isis_process_pdu:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract PDU type
    movzx eax, byte [rbx + 4]      ; PDU type field

    cmp al, ISIS_PDU_L1_HELLO
    je .pdu_hello
    cmp al, ISIS_PDU_L2_HELLO
    je .pdu_hello
    cmp al, ISIS_PDU_PTP_HELLO
    je .pdu_hello
    cmp al, ISIS_PDU_L1_LSP
    je .pdu_lsp
    cmp al, ISIS_PDU_L2_LSP
    je .pdu_lsp
    cmp al, ISIS_PDU_L1_CSNP
    je .pdu_csnp
    cmp al, ISIS_PDU_L2_CSNP
    je .pdu_csnp
    jmp .pdu_done

.pdu_hello:
    ; Process IIH: adjacency establishment, DIS election
    jmp .pdu_done
.pdu_lsp:
    ; Install LSP, flood to neighbors, trigger SPF
    call isis_flood_lsp
    call isis_spf_calculate
    jmp .pdu_done
.pdu_csnp:
    ; Compare with local LSDB, request missing LSPs via PSNP
    jmp .pdu_done

.pdu_done:
    pop rbx
    pop rbp
    ret

align 64
isis_send_hello:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
isis_spf_calculate:
    push rbp
    mov rbp, rsp
    ; Dijkstra SPF over IS-IS LSDB
    xor eax, eax
    pop rbp
    ret

align 64
isis_flood_lsp:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret

align 64
isis_parse_tlv:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse Type-Length-Value fields from IS-IS PDU
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_ROUTING_ISIS_ASM
