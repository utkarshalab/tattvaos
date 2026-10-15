%ifndef GUARD_UNET_CORE_L4_TCP_ECN_ASM
%define GUARD_UNET_CORE_L4_TCP_ECN_ASM
; =============================================================================
; Tattva OS — unet/core/l4/tcp_ecn.asm
; =============================================================================
; ECN (Explicit Congestion Notification) Support (RFC 3168, RFC 8311)
;
; ECN allows end-to-end notification of network congestion without dropping packets.
; Uses 2 bits in IP header (ECT) and 2 bits in TCP header (ECE, CWR).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ECN_ENABLED            1

; IP Header ECN bits (in TOS/DSCP field, bits 0-1)
%define IP_ECN_NOT_ECT         0b00      ; Non-ECN-Capable Transport
%define IP_ECN_ECT_0           0b10      ; ECN-Capable Transport (0)
%define IP_ECN_ECT_1           0b01      ; ECN-Capable Transport (1)
%define IP_ECN_CE              0b11      ; Congestion Experienced

; TCP ECN flags (in TCP header flags field)
%define TCP_ECN_ECE            0x40      ; ECN-Echo
%define TCP_ECN_CWR            0x80      ; Congestion Window Reduced

; ECN State Machine
%define ECN_STATE_DISABLED     0
%define ECN_STATE_REQUESTED    1
%define ECN_STATE_NEGOTIATED   2
%define ECN_STATE_DISABLED_PEER 3

struc ecn_state_t
    .state:          resb 1      ; ECN state machine
    .ecn_flags:      resb 1      ; ECN flags for outgoing packets
    .ce_count:       resd 1      ; CE marks received
    .ece_sent:       resd 1      ; ECE signals sent
    .cwr_sent:       resd 1      ; CWR signals sent
    .pad:            resb 3
endstruc

section .text

global tcp_ecn_init
global tcp_ecn_syn_sent
global tcp_ecn_syn_rcvd
global tcp_ecn_established
global tcp_ecn_process_ce
global tcp_ecn_process_ece
global tcp_ecn_process_cwr
global tcp_ecn_set_flags
global tcp_ecn_get_flags

; -----------------------------------------------------------------------------
; tcp_ecn_init — Initialize ECN state for a connection
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_ecn_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; Initialize ECN state
    mov byte [rbx + tcb_t.ecn_state], ECN_STATE_REQUESTED
    mov byte [rbx + tcb_t.ecn_flags], 0
    mov dword [rbx + tcb_t.ce_count], 0
    mov dword [rbx + tcb_t.ece_sent], 0
    mov dword [rbx + tcb_t.cwr_sent], 0

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_syn_sent — Process ECN in outgoing SYN (active open)
; Input: RDI = tcb_t*, RSI = tcp_hdr_t* (being built)
; -----------------------------------------------------------------------------
align 64
tcp_ecn_syn_sent:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    ; Check if ECN is enabled
    test byte [rbx + tcb_t.ecn_flags], 1
    jz .done

    ; Set ECT(0) in IP header (done at IP layer)
    ; Set ECE and CWR in SYN to indicate ECN capability
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    and al, 0x3F
    or al, (TCP_ECN_ECE | TCP_ECN_CWR) >> 8
    rol ax, 8
    mov [r12 + tcp_hdr_t.data_offset_flags], ax

    ; Update state
    mov byte [rbx + tcb_t.ecn_state], ECN_STATE_REQUESTED

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_syn_rcvd — Process ECN in SYN-ACK (passive open)
; Input: RDI = tcb_t*, RSI = tcp_hdr_t* (incoming SYN), RDX = tcp_hdr_t* (outgoing SYN-ACK)
; -----------------------------------------------------------------------------
align 64
tcp_ecn_syn_rcvd:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi            ; incoming SYN
    mov r13, rdx            ; outgoing SYN-ACK

    ; Check if peer supports ECN (ECE and CWR set in SYN)
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    and al, (TCP_ECN_ECE | TCP_ECN_CWR) >> 8
    cmp al, (TCP_ECN_ECE | TCP_ECN_CWR) >> 8
    jne .no_ecn

    ; Peer supports ECN - negotiate
    ; Set ECT(0) in IP header for SYN-ACK
    ; Set ECE and CWR in SYN-ACK
    movzx eax, word [r13 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    and al, 0x3F
    or al, (TCP_ECN_ECE | TCP_ECN_CWR) >> 8
    rol ax, 8
    mov [r13 + tcp_hdr_t.data_offset_flags], ax

    ; Update state
    mov byte [rbx + tcb_t.ecn_state], ECN_STATE_NEGOTIATED
    jmp .done

.no_ecn:
    mov byte [rbx + tcb_t.ecn_state], ECN_STATE_DISABLED_PEER

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_established — Process ECN in incoming packet (ESTABLISHED)
; Input: RDI = tcb_t*, RSI = tcp_hdr_t* (incoming), RDX = ip_hdr_t* (incoming)
; -----------------------------------------------------------------------------
align 64
tcp_ecn_established:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi            ; TCP header
    mov r13, rdx            ; IP header

    ; Check ECN state
    cmp byte [rbx + tcb_t.ecn_state], ECN_STATE_NEGOTIATED
    jne .done

    ; Check IP ECN field for CE (Congestion Experienced)
    movzx eax, byte [r13 + ipv4_header_t.tos]
    and al, 0x03            ; ECN bits
    cmp al, IP_ECN_CE
    je .congestion_experienced

    ; Check TCP ECE flag
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    test al, TCP_ECN_ECE >> 8
    jz .check_cwr

    ; Peer sent ECE - reduce congestion window
    call tcp_ecn_process_ece
    jmp .done

.check_cwr:
    ; Check TCP CWR flag
    test al, TCP_ECN_CWR >> 8
    jz .done

    ; Peer sent CWR - they reduced cwnd
    call tcp_ecn_process_cwr

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.congestion_experienced:
    ; CE mark received - process as congestion signal
    call tcp_ecn_process_ce
    jmp .done

; -----------------------------------------------------------------------------
; tcp_ecn_process_ce — Process Congestion Experienced mark
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_ecn_process_ce:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    ; Increment CE counter
    inc dword [rbx + tcb_t.ce_count]

    ; Reduce congestion window (same as loss)
    mov eax, [rbx + tcb_t.cwnd]
    mov r12d, eax
    shr r12d, 1             ; cwnd = cwnd / 2
    cmp r12d, 2
    jge .set_cwnd
    mov r12d, 2

.set_cwnd:
    mov dword [rbx + tcb_t.cwnd], r12d
    mov dword [rbx + tcb_t.ssthresh], r12d

    ; Set ECE in next outgoing packet
    or byte [rbx + tcb_t.ecn_flags], 0x01  ; ECE pending

    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_process_ece — Process ECE from peer
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_ecn_process_ece:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    inc dword [rbx + tcb_t.ece_sent]

    ; Reduce congestion window
    mov eax, [rbx + tcb_t.cwnd]
    mov r12d, eax
    shr r12d, 1
    cmp r12d, 2
    jge .set_cwnd
    mov r12d, 2

.set_cwnd:
    mov dword [rbx + tcb_t.cwnd], r12d
    mov dword [rbx + tcb_t.ssthresh], r12d

    ; Set CWR in next outgoing packet
    or byte [rbx + tcb_t.ecn_flags], 0x02  ; CWR pending

    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_process_cwr — Process CWR from peer
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_ecn_process_cwr:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    inc dword [rbx + tcb_t.cwr_sent]

    ; Peer has reduced their window - clear ECE pending
    and byte [rbx + tcb_t.ecn_flags], ~0x01

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_set_flags — Set ECN flags for outgoing packet
; Input: RDI = tcb_t*, RSI = tcp_hdr_t* (being built)
; -----------------------------------------------------------------------------
align 64
tcp_ecn_set_flags:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    ; Check ECN state
    cmp byte [rbx + tcb_t.ecn_state], ECN_STATE_NEGOTIATED
    jne .done

    ; Set IP ECN field (ECT(0))
    ; Done at IP layer

    ; Set TCP ECE flag if pending
    test byte [rbx + tcb_t.ecn_flags], 0x01
    jz .check_cwr
    ; Set ECE
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    or al, TCP_ECN_ECE >> 8
    rol ax, 8
    mov [r12 + tcp_hdr_t.data_offset_flags], ax
    ; Clear ECE pending
    and byte [rbx + tcb_t.ecn_flags], ~0x01
    jmp .done

.check_cwr:
    ; Check CWR pending
    test byte [rbx + tcb_t.ecn_flags], 0x02
    jz .done
    ; Set CWR
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    or al, TCP_ECN_CWR >> 8
    rol ax, 8
    mov [r12 + tcp_hdr_t.data_offset_flags], ax
    ; Clear CWR pending
    and byte [rbx + tcb_t.ecn_flags], ~0x02

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_ecn_get_flags — Get ECN flags for outgoing packet
; Input: RDI = tcb_t*
; Output: AL = IP ECN field, AH = TCP ECN flags
; -----------------------------------------------------------------------------
align 64
tcp_ecn_get_flags:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    xor eax, eax

    cmp byte [rbx + tcb_t.ecn_state], ECN_STATE_NEGOTIATED
    jne .done

    ; IP ECN field: ECT(0) = 0b10
    mov al, IP_ECN_ECT_0

    ; TCP flags
    mov ah, 0
    test byte [rbx + tcb_t.ecn_flags], 0x01
    jz .check_cwr
    or ah, TCP_ECN_ECE >> 8

.check_cwr:
    test byte [rbx + tcb_t.ecn_flags], 0x02
    jz .done
    or ah, TCP_ECN_CWR >> 8

.done:
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_ECN_ASM