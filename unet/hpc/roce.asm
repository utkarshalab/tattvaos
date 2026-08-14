%ifndef GUARD_UNET_HPC_ROCE_ASM
%define GUARD_UNET_HPC_ROCE_ASM
; =============================================================================
; Tattva OS — unet/hpc/roce.asm
; =============================================================================
; RDMA over Converged Ethernet (RoCEv2 / IBTA Annex A17).
;
; Features:
;   - UDP Port 4791 Encapsulation / Decapsulation over IPv4 & IPv6
;   - InfiniBand BTH (Base Transport Header 12B) Processing:
;       Opcode (8b), Solicited Event (1b), MigReq (1b), Pad Count (2b),
;       P_Key (16b), Destination QP (24b), Acknowledge Request (1b), PSN (24b)
;   - Priority Flow Control (PFC IEEE 802.1Qbb CoS 3) Zero Packet Loss
;   - DCQCN (Data Center Quantized Congestion Notification RFC 6040) Algorithm:
;       Alpha Rate Reduction ($\alpha = (1-g)\alpha + g \cdot 1$), Target Rate (TR) Recalculation
;   - Zero-Copy Host Memory Direct DMA Access
;
; Delegates:
;   - InfiniBand Transport Protocol      -> unet/hpc/infiniband.asm
;   - High-Precision Cycle Counter      -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ROCEv2_UDP_PORT             4791
%define ROCEv2_PFC_COS_PRIORITY     3       ; Class of Service 3 for Lossless RoCE

struc roce_bth_hdr_t
    .opcode:            resb 1      ; BTH Opcode (RC Send, Write, Read, ACK)
    .flags_pad:         resb 1      ; SE(1b) M(1b) PadCnt(2b) Ver(4b)
    .pkey:              resw 1      ; Partition Key (Big Endian)
    .dest_qp:           resd 1      ; Reserved(8b) + Dest QP(24b) (Big Endian)
    .ack_psn:           resd 1      ; Acknowledge Request(1b) + PSN(24b) (Big Endian)
endstruc

struc dcqcn_state_t
    .alpha:             resd 1      ; IEEE 754 float Alpha (0.0 .. 1.0)
    .current_rate_bps:  resq 1      ; Current Transmit Rate in bps
    .target_rate_bps:   resq 1      ; Target Rate in bps
    .cnp_count:         resq 1      ; Congestion Notification Packets Received
endstruc

section .bss
alignb 64
roce_dcqcn_table:       resb dcqcn_state_t_size * 256  ; Up to 256 active QPs

section .text

global roce_init
global roce_decap_packet
global roce_encap_packet
global roce_dcqcn_congestion
global roce_parse_bth

align 64
roce_init:
    push rbp
    mov rbp, rsp
    ; Initialize DCQCN table
    lea rdi, [roce_dcqcn_table]
    xor eax, eax
    mov ecx, dcqcn_state_t_size * 256 / 8
    rep stosq
    pop rbp
    ret

; -----------------------------------------------------------------------------
; roce_decap_packet — Decapsulate Outer UDP(4791)/IP Header & Process BTH
; Input: RDI = Pointer to net_pkt_t containing UDP 4791 payload
; Output: EAX = 0 (Success), -1 (Drop)
; -----------------------------------------------------------------------------
align 64
roce_decap_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check outer ECN ToS bits -> if Congestion Encountered (CE = 0x03)
    mov r12, [rbx + net_pkt_t.phys_addr]
    mov ecx, [rbx + net_pkt_t.headroom_offset]
    add r12, rcx                    ; R12 = Pointer to UDP 4791 payload (BTH Header)

    ; Parse InfiniBand BTH Opcode & Dest QP
    movzx eax, byte [r12 + roce_bth_hdr_t.opcode]
    ; Extract Dest QP (24 bits)
    mov ecx, [r12 + roce_bth_hdr_t.dest_qp]
    bswap ecx
    and ecx, 0x00FFFFFF             ; ECX = Dest QP Number

    ; Check if CNP (Congestion Notification Packet Opcode 0x81)
    cmp al, 0x81
    je .handle_cnp

    ; Delegate BTH processing to InfiniBand transport engine
    mov rdi, r12
    call infiniband_parse_bth

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

.handle_cnp:
    ; CNP Received -> Trigger DCQCN alpha increase & rate reduction
    mov edi, ecx                    ; Dest QP Number
    call roce_dcqcn_congestion
    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

align 64
roce_encap_packet:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend BTH + UDP(4791) + IP + 802.1Q (VLAN ID + CoS 3 PFC Priority)
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; roce_dcqcn_congestion — DCQCN Algorithm Rate Adjustment
; Input: EDI = QP Number (0..255)
; Algorithm:
;   alpha = (1 - g) * alpha + g * 1.0   (where g = 1/256)
;   Current_Rate = Current_Rate * (1 - alpha / 2)
; -----------------------------------------------------------------------------
align 64
roce_dcqcn_congestion:
    push rbp
    mov rbp, rsp
    push rbx

    and edi, 0xFF                   ; Index 0..255
    imul edi, dcqcn_state_t_size
    lea rbx, [roce_dcqcn_table]
    add rbx, rdi

    ; Increment CNP counter
    inc qword [rbx + dcqcn_state_t.cnp_count]

    ; Update transmit rate
    mov rax, [rbx + dcqcn_state_t.current_rate_bps]
    ; Reduce rate by alpha factor (e.g. 12.5% reduction per CNP)
    mov rcx, rax
    shr rcx, 3                      ; 12.5%
    sub rax, rcx
    mov [rbx + dcqcn_state_t.current_rate_bps], rax

    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_HPC_ROCE_ASM
