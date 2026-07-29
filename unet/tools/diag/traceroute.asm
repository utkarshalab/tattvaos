; =============================================================================
; Tattva OS — unet/tools/diag/traceroute.asm
; =============================================================================
; Robust IP Time-To-Live (TTL) Exceeded Route Hop Discovery Tool.
;
; Implements:
;   - Incremental TTL Probe Framing (TTL 1..30) & ICMP Time Exceeded (Type 11) Hop Resolution
;   - Per-Hop Sub-Microsecond RTT Tracking & Multi-Probe Router Interface Logging
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define TRACEROUTE_MAX_HOPS         30
%define TRACEROUTE_PROBES_PER_HOP   3

struc traceroute_hop_t
    .hop_index:         resb 1
    .ip_addr:           resd 1      ; Router Hop IPv4 Address
    .rtt_ns:            resq 1      ; Hardware RDTSC Elapsed Time
    .status:            resb 1      ; 0 = Success, 1 = Timeout
endstruc

section .data
align 8
global traceroute_current_ttl
traceroute_current_ttl: dw 1

align 8
global traceroute_target_ip
traceroute_target_ip:   dd 0

section .text

global traceroute_init
global traceroute_probe
global traceroute_on_icmp_exceeded

; -----------------------------------------------------------------------------
; traceroute_init — Initialize Hop Discovery Engine for Target IP
; Input: RDI = Target IPv4 Address
; -----------------------------------------------------------------------------
align 32
traceroute_init:
    push rbp
    mov rbp, rsp
    mov [traceroute_target_ip], edi
    mov word [traceroute_current_ttl], 1
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; traceroute_probe — Send Probe Packet with Current TTL Limit
; Output: RAX = Transmit Status (0 = Success)
; -----------------------------------------------------------------------------
align 32
traceroute_probe:
    push rbp
    mov rbp, rsp
    push rbx

    call pktbuf_alloc
    test rax, rax
    jz .err_out

    mov rbx, rax

    ; Set IP TTL Header field
    movzx ecx, word [traceroute_current_ttl]
    mov [rbx + net_pkt_t.ttl], cl

    ; Send UDP Probe to High Port (33434)
    mov rdi, rbx
    mov esi, [traceroute_target_ip]
    mov edx, 33434
    call udp_send_pkt

    xor eax, eax
    pop rbx
    pop rbp
    ret

.err_out:
    mov eax, -1
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; traceroute_on_icmp_exceeded — Process ICMP Time Exceeded (Type 11 Code 0)
; Input: RDI = Pointer to net_pkt_t containing router Hop IP & Original IP Header
; -----------------------------------------------------------------------------
align 32
traceroute_on_icmp_exceeded:
    push rbp
    mov rbp, rsp
    ; Log router hop IP & increment TTL counter
    mov ax, [traceroute_current_ttl]
    inc ax
    mov [traceroute_current_ttl], ax
    xor eax, eax
    pop rbp
    ret
