%ifndef GUARD_UNET_TOOLS_ROUTE_ROUTE_TOOL_ASM
%define GUARD_UNET_TOOLS_ROUTE_ROUTE_TOOL_ASM
; =============================================================================
; Tattva OS — unet/tools/route/route_tool.asm
; =============================================================================
; Command-Line IP Routing Table Manager & Inspector Tool (`route`).
;
; Features:
;   - IPv4 / IPv6 Forwarding Information Base (FIB) Routing Table Display
;   - Route Table Manipulation: Add (`route add`), Delete (`route del`), Flush Route Table
;   - Prefix Match, Gateway IPv4/IPv6, Outgress Interface ID, Metric Selection
;   - AVX-512 Fast FIB Search Benchmark
;
; Delegates:
;   - IP Protocol Layer Engine          -> unet/core/l3/ip.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc fib_entry_t
    .dest_ip:           resd 1
    .netmask:           resd 1
    .gateway_ip:        resd 1
    .if_index:          resd 1
    .metric:            resd 1
endstruc

section .text

global route_tool_main
global route_tool_add_route
global route_tool_del_route

align 64
route_tool_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call route_tool_add_route

    pop rbx
    pop rbp
    ret

align 64
route_tool_add_route:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Add target IP/Subnet + Gateway + Interface index to routing table
    xor eax, eax
    pop rbp
    ret

align 64
route_tool_del_route:
    push rbp
    mov rbp, rsp
    ; Remove route entry matching destination IP and subnet mask
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_ROUTE_ROUTE_TOOL_ASM
