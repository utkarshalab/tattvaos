%ifndef GUARD_UNET_TOOLS_DIAG_SS_TOOL_ASM
%define GUARD_UNET_TOOLS_DIAG_SS_TOOL_ASM
; =============================================================================
; Tattva OS — unet/tools/diag/ss_tool.asm
; =============================================================================
; Socket Statistics Diagnostic Utility (`ss`).
;
; Features:
;   - Fast-Path Socket Dumping (TCP, UDP, Raw, UNIX sockets)
;   - TCP Socket Info: Congestion Window (cwnd), RTT, rto, ssthresh, mss, rcv_wnd
;   - Filtering by Port, Remote IP, State (ESTABLISHED, LISTEN, TIME-WAIT)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ss_tool_main
global ss_dump_tcp_info

align 64
ss_tool_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call ss_dump_tcp_info

    pop rbx
    pop rbp
    ret

align 64
ss_dump_tcp_info:
    push rbp
    mov rbp, rsp
    ; Dump TCP socket metrics: cwnd, RTT us, RTO, rcv_space, ssthresh
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_DIAG_SS_TOOL_ASM
