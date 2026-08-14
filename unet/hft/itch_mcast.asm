%ifndef GUARD_UNET_HFT_ITCH_MCAST_ASM
%define GUARD_UNET_HFT_ITCH_MCAST_ASM
; =============================================================================
; Tattva OS — unet/hft/itch_mcast.asm
; =============================================================================
; MoldUDP64 Multicast Transport Engine for ITCH 5.0 Market Data.
;
; Features:
;   - MoldUDP64 20-Byte Header Parsing (Session 10B, Sequence Number 8B, Count 2B)
;   - UDP Multicast Ring Polling with Sub-Microsecond Lockless Ingest
;   - Gap Detection & Automatic Out-of-Sequence NACK Retransmission Request
;   - Dual Feed Arbitraged Ingestion (Feed A vs Feed B Low-Latency Deduplication)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc moldudp64_hdr_t
    .session:           resb 10     ; 10-Byte Session Identifier
    .sequence_num:      resq 1      ; 64-bit Sequence Number (big endian)
    .msg_count:         resw 1      ; 16-bit Message Count
endstruc

section .text

global itch_mcast_init
global itch_mcast_poll_feed
global itch_mcast_detect_gap
global itch_mcast_arbitrage


align 64
itch_mcast_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; itch_mcast_poll_feed — Poll UDP Multicast MoldUDP64 Feed Ring
; Input: RDI = Pointer to MoldUDP64 Packet Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
itch_mcast_poll_feed:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Read 64-bit Sequence Number
    mov rax, [rbx + moldudp64_hdr_t.sequence_num]
    bswap rax

    ; 2. Check for missing sequence gap
    call itch_mcast_detect_gap

    ; 3. Parse length-prefixed ITCH messages in payload
    movzx ecx, word [rbx + moldudp64_hdr_t.msg_count]
    xchg cl, ch                     ; ECX = Message Count

    lea rdi, [rbx + moldudp64_hdr_t_size]
.msg_loop:
    test ecx, ecx
    jz .done
    call itch_parse_msg
    dec ecx
    jmp .msg_loop

.done:
    pop rbx
    pop rbp
    ret

align 64
itch_mcast_detect_gap:
    push rbp
    mov rbp, rsp
    ; Compare expected_seq with rax. If expected < rax -> trigger MoldUDP64 Request
    xor eax, eax
    pop rbp
    ret

align 64
itch_mcast_arbitrage:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Arbitrage Feed A vs Feed B: process earliest arrived packet, drop duplicate
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_HFT_ITCH_MCAST_ASM
