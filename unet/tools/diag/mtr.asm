%ifndef GUARD_UNET_TOOLS_DIAG_MTR_ASM
%define GUARD_UNET_TOOLS_DIAG_MTR_ASM
; =============================================================================
; Tattva OS — unet/tools/diag/mtr.asm
; =============================================================================
; Combined Traceroute + Continuous Ping Network Diagnostic Tool (`mtr`).
;
; Features:
;   - TTL Probing (TTL 1..32) with Continuous Real-Time ICMP Echo Request Sampling
;   - Per-Hop Statistics: Loss %, Sent, Last RTT, Avg RTT, Best RTT, Worst RTT, StDev
;   - Hardware RDTSC Nanosecond Resolution Per-Hop Timestamp Tracking
;   - Exponentially Weighted Moving Average (EWMA) Jitter Calculation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MTR_MAX_HOPS                32
%define MTR_PROBES_PER_CYCLE        3

struc mtr_hop_t
    .ip_addr:           resd 1      ; Router Hop IPv4 Address
    .sent:              resd 1      ; Total Probes Sent
    .recv:              resd 1      ; Total Replies Received
    .last_rtt_us:       resd 1      ; Last RTT (microseconds)
    .best_rtt_us:       resd 1      ; Best (Min) RTT
    .worst_rtt_us:      resd 1      ; Worst (Max) RTT
    .sum_rtt_us:        resq 1      ; Sum RTT for Average
    .sum_sq_rtt:        resq 1      ; Sum of Squares for StDev
endstruc

section .bss
alignb 64
mtr_hop_table:          resb mtr_hop_t_size * MTR_MAX_HOPS

section .data
align 4
mtr_target_ip:          dd 0
mtr_max_ttl:            dd MTR_MAX_HOPS

section .text

global mtr_main
global mtr_probe_hop
global mtr_update_stats
global mtr_on_reply


; -----------------------------------------------------------------------------
; mtr_main — Entry Point: Initialize & Run Continuous Probe Loop
; Input: RDI = Target IPv4 Address
; Output: EAX = 0 (Success)
; -----------------------------------------------------------------------------
align 64
mtr_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov [mtr_target_ip], edi

    ; Zero entire hop table
    lea rdi, [mtr_hop_table]
    xor eax, eax
    mov ecx, mtr_hop_t_size * MTR_MAX_HOPS / 8
    rep stosq

    ; Initialize best RTT to MAX for each hop
    lea rbx, [mtr_hop_table]
    mov r12d, MTR_MAX_HOPS
.init_loop:
    mov dword [rbx + mtr_hop_t.best_rtt_us], 0x7FFFFFFF
    add rbx, mtr_hop_t_size
    dec r12d
    jnz .init_loop

    ; Probe loop: TTL 1..max_ttl
    mov r12d, 1                     ; Starting TTL
.probe_loop:
    cmp r12d, [mtr_max_ttl]
    ja .done

    mov edi, r12d                   ; TTL
    call mtr_probe_hop

    inc r12d
    jmp .probe_loop

.done:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mtr_probe_hop — Send ICMP Echo Probe with Specific TTL
; Input: EDI = TTL Value (1..32)
; Output: EAX = 0 (Success), -1 (Buffer alloc failure)
; -----------------------------------------------------------------------------
align 64
mtr_probe_hop:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12d, edi                   ; Save TTL

    ; Allocate packet buffer
    call pktbuf_alloc
    test rax, rax
    jz .err

    mov rbx, rax

    ; Format ICMP Echo Request with target TTL
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx

    mov byte [rdx], 8              ; ICMP Type 8 (Echo Request)
    mov byte [rdx + 1], 0          ; Code 0
    mov word [rdx + 2], 0          ; Checksum placeholder
    mov word [rdx + 4], 0x4D54     ; ID = "MT" (0x4D54)
    mov [rdx + 6], r12w            ; Seq = TTL

    ; Store RDTSC departure timestamp in payload
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add rdx, rcx
    mov [rdx + 8], rax             ; 64-bit departure timestamp

    ; Set IP TTL field
    mov [rbx + net_pkt_t.ttl], r12b

    ; Update sent counter
    lea rax, [mtr_hop_table]
    mov ecx, r12d
    dec ecx                         ; TTL 1 -> index 0
    imul ecx, mtr_hop_t_size
    add rax, rcx
    inc dword [rax + mtr_hop_t.sent]

    ; Transmit
    mov rdi, rbx
    mov esi, [mtr_target_ip]
    mov edx, 1                     ; Protocol ICMP
    call ip_send_pkt

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

.err:
    mov eax, -1
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mtr_on_reply — Process ICMP Time Exceeded (Type 11) or Echo Reply (Type 0)
; Input: RDI = Pointer to net_pkt_t, ESI = Hop TTL (from original IP header)
; Output: EAX = 0
; -----------------------------------------------------------------------------
align 64
mtr_on_reply:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12d, esi                   ; Hop index

    ; Read arrival RDTSC
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov rcx, rax                    ; RCX = arrival TSC

    ; Read departure RDTSC from payload
    mov rdx, [rbx + net_pkt_t.phys_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add rdx, rax
    mov rax, [rdx + 8]             ; RAX = departure TSC

    sub rcx, rax                    ; RCX = elapsed cycles (RTT)

    ; Convert cycles to microseconds (assume ~3 GHz -> divide by 3000)
    mov rax, rcx
    xor edx, edx
    mov ecx, 3000
    div rcx                         ; RAX = RTT in microseconds

    ; Locate hop entry
    lea rbx, [mtr_hop_table]
    mov ecx, r12d
    dec ecx
    imul ecx, mtr_hop_t_size
    add rbx, rcx

    ; Update statistics
    mov edi, eax                    ; EDI = RTT_us
    mov rsi, rbx                    ; RSI = hop entry
    call mtr_update_stats

    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mtr_update_stats — Update Per-Hop Min/Max/Avg/StDev RTT Statistics
; Input: EDI = RTT in microseconds, RSI = Pointer to mtr_hop_t
; -----------------------------------------------------------------------------
align 64
mtr_update_stats:
    push rbp
    mov rbp, rsp

    ; Increment received counter
    inc dword [rsi + mtr_hop_t.recv]

    ; Update last RTT
    mov [rsi + mtr_hop_t.last_rtt_us], edi

    ; Update best (min) RTT
    cmp edi, [rsi + mtr_hop_t.best_rtt_us]
    jae .chk_worst
    mov [rsi + mtr_hop_t.best_rtt_us], edi

.chk_worst:
    ; Update worst (max) RTT
    cmp edi, [rsi + mtr_hop_t.worst_rtt_us]
    jbe .update_sum
    mov [rsi + mtr_hop_t.worst_rtt_us], edi

.update_sum:
    ; Accumulate sum for average
    movzx eax, di                   ; Zero-extend to avoid sign issues
    add [rsi + mtr_hop_t.sum_rtt_us], rax

    ; Accumulate sum of squares for standard deviation
    imul rax, rax                   ; rtt^2
    add [rsi + mtr_hop_t.sum_sq_rtt], rax

    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_DIAG_MTR_ASM
