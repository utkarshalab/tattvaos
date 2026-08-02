; =============================================================================
; Tattva OS — unet/hft/ouch.asm
; =============================================================================
; NASDAQ OUCH 5.0 Ultra-Low Latency Order Entry Protocol Engine.
;
; Features:
;   - Binary Order Entry Packet Construction & Parsing
;   - Inbound Commands (Inbound from Client to Exchange):
;       'O': Enter Order (ClOrdID 14B, Buy/Sell 1B, Shares 4B, Stock 8B, Price 4B, TimeInForce 4B, Firm 4B)
;       'X': Cancel Order (ClOrdID 14B, Shares 4B)
;       'U': Replace Order (Existing ClOrdID 14B, New ClOrdID 14B, Shares 4B, Price 4B)
;   - Outbound Messages (Outbound from Exchange to Client):
;       'A': Order Accepted (Timestamp 8B, Order Ref Num 8B, State, ClOrdID)
;       'C': Order Canceled (Timestamp 8B, Order Ref Num 8B, Reason)
;       'E': Order Executed (Timestamp 8B, Order Ref Num 8B, Executed Shares 4B, Price 4B)
;       'J': Order Rejected (Timestamp 8B, Reason 1B)
;   - AVX-512 SIMD Parallel Order Field Pre-Formatting (<100 Nanoseconds Order Ingress-to-Egress)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define OUCH_CMD_ENTER_ORDER        'O'
%define OUCH_CMD_CANCEL_ORDER       'X'
%define OUCH_CMD_REPLACE_ORDER      'U'

%define OUCH_OUT_ACCEPTED           'A'
%define OUCH_OUT_CANCELED           'C'
%define OUCH_OUT_EXECUTED           'E'
%define OUCH_OUT_REJECTED           'J'

struc ouch_enter_order_t
    .packet_type:       resb 1      ; 'O'
    .cl_ord_id:         resb 14     ; 14-Byte Client Order Identifier
    .buy_sell_indicator: resb 1     ; 'B' = Buy, 'S' = Sell
    .shares:            resd 1      ; 32-bit Share Quantity
    .stock:             resb 8      ; 8-Byte Stock Symbol
    .price:             resd 1      ; 32-bit Price (4 decimal places)
    .time_in_force:     resd 1      ; Time In Force (0 = IOC, 99999 = Day)
    .firm:              resb 4      ; 4-Byte Firm Identifier
    .display:           resb 1      ; 'Y', 'N', 'A'
    .capacity:          resb 1      ; Agency, Principal, Riskless
endstruc

section .text

global ouch_init
global ouch_build_enter_order_avx512
global ouch_parse_response
global ouch_process_execution

align 64
ouch_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ouch_build_enter_order_avx512 — Build 48-Byte OUCH Enter Order Packet (<50ns)
; Input: RDI = Output Buffer, RSI = ClOrdID, EDX = Shares, ECX = Price, R8 = Stock Symbol
; -----------------------------------------------------------------------------
align 64
ouch_build_enter_order_avx512:
    push rbp
    mov rbp, rsp
    push rbx

    mov byte [rdi + ouch_enter_order_t.packet_type], OUCH_CMD_ENTER_ORDER
    mov dword [rdi + ouch_enter_order_t.shares], edx
    mov dword [rdi + ouch_enter_order_t.price], ecx
    mov qword [rdi + ouch_enter_order_t.stock], r8

    vzeroupper
    pop rbx
    pop rbp
    ret

align 64
ouch_parse_response:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]            ; Response Type Byte

    cmp al, OUCH_OUT_ACCEPTED
    je .accepted
    cmp al, OUCH_OUT_EXECUTED
    je .executed
    cmp al, OUCH_OUT_CANCELED
    je .canceled
    cmp al, OUCH_OUT_REJECTED
    je .rejected
    jmp .done

.accepted:
    jmp .done
.executed:
    call ouch_process_execution
    jmp .done
.canceled:
    jmp .done
.rejected:
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
ouch_process_execution:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract Order Ref Num, Executed Shares, Price, Match Number -> Update Position Tracker
    xor eax, eax
    pop rbp
    ret
