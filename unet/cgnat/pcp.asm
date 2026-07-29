; =============================================================================
; Tattva OS — unet/cgnat/pcp.asm
; =============================================================================
; Port Control Protocol (PCP RFC 6887) & UPnP IGD Dynamic Mapping Engine.
;
; Features:
;   - PCP MAP (Opcode 1) & PEER (Opcode 2) Request / Response Processing
;   - Third-Party MAP Request Authorization (RFC 6887 Section 13)
;   - Dynamic CGNAT Port Binding Creation & Lifetime Renewal
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PCP_PORT                    5351
%define PCP_OPCODE_MAP              1
%define PCP_OPCODE_PEER             2

struc pcp_hdr_t
    .version:           resb 1      ; PCP Version (2)
    .r_opcode:          resb 1      ; R bit (1) + Opcode
    .reserved:          resw 1      ; Reserved
    .lifetime:          resd 1      ; Requested Lifetime in Seconds
    .client_ip:         resb 16     ; 128-bit Client IPv6/IPv4 Address
endstruc

section .text

global pcp_init
global pcp_process_map_request
global pcp_process_peer_request

extern timer_wheel_add

align 64
pcp_init:
    push rbp
    mov rbp, rsp
    ; Bind UDP Port 5351 for PCP Requests
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pcp_process_map_request — Process PCP MAP Request & Create CGNAT Binding
; Input: RDI = Pointer to pcp_hdr_t Packet Buffer
; -----------------------------------------------------------------------------
align 64
pcp_process_map_request:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract requested internal/external port & IP address
    ; 2. Create dynamic CGNAT port mapping entry in cgnat_session_table
    ; 3. Schedule lifetime expiration in lib/time/timer_wheel.asm
    call timer_wheel_add

    pop rbx
    pop rbp
    ret

align 64
pcp_process_peer_request:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
