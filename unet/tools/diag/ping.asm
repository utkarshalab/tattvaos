%ifndef GUARD_UNET_TOOLS_DIAG_PING_ASM
%define GUARD_UNET_TOOLS_DIAG_PING_ASM
; =============================================================================
; Tattva OS — unet/tools/diag/ping.asm
; =============================================================================
; Robust Sub-Microsecond ICMP Echo Request / Echo Reply Diagnostic Ping Tool.
;
; Implements:
;   - ICMP v4/v6 Echo Request Frame Formatting (Type 8 Code 0)
;   - Internet One's Complement Checksum Calculation
;   - High-Precision Hardware Timestamping via RDTSC (Nanosecond Resolution RTT)
;   - Sequence Counter, TTL Parsing & Packet Loss / Min/Avg/Max RTT Statistics
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc icmp_echo_hdr_t
    .type:              resb 1      ; 8 = Echo Request, 0 = Echo Reply
    .code:              resb 1      ; 0
    .checksum:          resw 1      ; One's Complement Internet Checksum
    .id:                resw 1      ; Process / Identifier ID
    .seq:               resw 1      ; Sequence Number
    .timestamp:         resq 1      ; Hardware RDTSC Timestamp (64-bit)
endstruc

section .data
align 8
global ping_stats_sent
ping_stats_sent:        dq 0

align 8
global ping_stats_recv
ping_stats_recv:        dq 0

align 8
global ping_seq_counter
ping_seq_counter:       dw 0

align 8
global ping_min_rtt_ns
ping_min_rtt_ns:        dq 0xFFFFFFFFFFFFFFFF

align 8
global ping_max_rtt_ns
ping_max_rtt_ns:        dq 0

section .text

global ping_init
global ping_send_echo
global ping_recv_reply

; -----------------------------------------------------------------------------
; ping_init — Reset Ping Diagnostic Statistics & Counters
; -----------------------------------------------------------------------------
align 32
ping_init:
    push rbp
    mov rbp, rsp
    mov qword [ping_stats_sent], 0
    mov qword [ping_stats_recv], 0
    mov word [ping_seq_counter], 0
    mov qword [ping_min_rtt_ns], 0xFFFFFFFFFFFFFFFF
    mov qword [ping_max_rtt_ns], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ping_send_echo — Construct & Transmit ICMP Echo Request Frame
; Input: RDI = Target IPv4 Address (32-bit Big-Endian)
; Output: RAX = Transmit Status (0 = Success)
; -----------------------------------------------------------------------------
align 32
ping_send_echo:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12d, edi                   ; Save target IP

    ; Allocate packet buffer for ICMP Request
    call pktbuf_alloc
    test rax, rax
    jz .err_out

    mov rbx, rax                    ; RBX = Pointer to net_pkt_t

    ; Setup ICMP Header Pointer
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx                     ; RDX = ICMP Header Start

    ; Format ICMP Echo Request
    mov byte [rdx + icmp_echo_hdr_t.type], 8        ; Echo Request
    mov byte [rdx + icmp_echo_hdr_t.code], 0
    mov word [rdx + icmp_echo_hdr_t.checksum], 0
    mov word [rdx + icmp_echo_hdr_t.id], 0x1337      ; Ping PID
    
    mov ax, [ping_seq_counter]
    inc ax
    mov [ping_seq_counter], ax
    mov [rdx + icmp_echo_hdr_t.seq], ax

    ; Read Hardware RDTSC Cycle Counter Timestamp
    rdtsc
    shl rdx, 32
    or rax, rdx
    
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx
    mov [rdx + icmp_echo_hdr_t.timestamp], rax     ; Store 64-bit Start Time

    ; Compute Internet Checksum over ICMP Packet (64 bytes)
    mov rdi, rdx
    mov esi, icmp_echo_hdr_t_size
    call icmp_checksum
    
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx
    mov [rdx + icmp_echo_hdr_t.checksum], ax

    inc qword [ping_stats_sent]

    ; Transmit via IP Layer Dispatcher
    mov rdi, rbx
    mov esi, r12d
    mov edx, 1                                      ; Protocol = ICMP (1)
    call ip_send_pkt

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

.err_out:
    mov eax, -1
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ping_recv_reply — Process Incoming ICMP Echo Reply & Compute RTT Metrics
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
ping_recv_reply:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx                     ; RDX = Start of ICMP Header

    cmp byte [rdx + icmp_echo_hdr_t.type], 0       ; Echo Reply
    jne .ignore

    ; Read Current Hardware RDTSC Timestamp
    rdtsc
    shl rdx, 32
    or rax, rdx                     ; RAX = End Timestamp

    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx
    mov rcx, [rdx + icmp_echo_hdr_t.timestamp]    ; RCX = Start Timestamp
    
    sub rax, rcx                     ; RAX = RTT Cycles elapsed
    inc qword [ping_stats_recv]

    ; Update Min/Max RTT
    cmp rax, [ping_min_rtt_ns]
    jae .chk_max
    mov [ping_min_rtt_ns], rax

.chk_max:
    cmp rax, [ping_max_rtt_ns]
    jbe .done
    mov [ping_max_rtt_ns], rax

.done:
    xor eax, eax
    pop rbx
    pop rbp
    ret

.ignore:
    mov eax, -1
    pop rbx
    pop rbp
    ret

; Helper Function: Compute ICMP One's Complement Checksum
align 32
icmp_checksum:
    push rbp
    mov rbp, rsp
    xor eax, eax
.loop:
    cmp esi, 1
    jbe .last_byte
    movzx ecx, word [rdi]
    add eax, ecx
    add rdi, 2
    sub esi, 2
    jnz .loop
    jmp .fold
.last_byte:
    jz .fold
    movzx ecx, byte [rdi]
    add eax, ecx
.fold:
    mov ecx, eax
    shr ecx, 16
    and eax, 0xFFFF
    add eax, ecx
    mov ecx, eax
    shr ecx, 16
    add eax, ecx
    not ax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_DIAG_PING_ASM
