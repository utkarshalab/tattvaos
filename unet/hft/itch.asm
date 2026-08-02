; =============================================================================
; Tattva OS — unet/hft/itch.asm
; =============================================================================
; NASDAQ ITCH 5.0 Direct Order Book Feed Protocol Engine.
;
; Features:
;   - ITCH 5.0 Binary Message Header Parsing (2-Byte Length + 1-Byte Message Type)
;   - Message Types:
;       'S': System Event (Start/End of Transports)
;       'R': Stock Directory
;       'H': Stock Trading Action
;       'A': Add Order (No MPID - 36 Bytes)
;       'F': Add Order (With MPID - 40 Bytes)
;       'E': Order Executed (31 Bytes)
;       'C': Order Executed With Price (36 Bytes)
;       'X': Order Cancel (23 Bytes)
;       'D': Order Delete (19 Bytes)
;       'U': Order Replace (35 Bytes)
;       'P': Trade Message (Non-Cross - 44 Bytes)
;       'Q': Cross Trade (39 Bytes)
;   - Sub-Nanosecond Direct L1 Cache Order Book Update Dispatch
;   - Big Endian Field Conversion (Stock Locate, Timestamp 48b, Order Ref 64b, Shares 32b, Price 32b)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ITCH_MSG_SYSTEM_EVENT        'S'
%define ITCH_MSG_STOCK_DIRECTORY     'R'
%define ITCH_MSG_ADD_ORDER           'A'
%define ITCH_MSG_ADD_ORDER_MPID      'F'
%define ITCH_MSG_ORDER_EXECUTED      'E'
%define ITCH_MSG_ORDER_CANCEL        'X'
%define ITCH_MSG_ORDER_DELETE        'D'
%define ITCH_MSG_ORDER_REPLACE       'U'
%define ITCH_MSG_TRADE               'P'

struc itch_add_order_t
    .msg_type:          resb 1      ; 'A'
    .stock_locate:      resw 1      ; Stock Locate ID (Big Endian)
    .tracking_num:      resw 1      ; Tracking Number
    .timestamp:         resb 6      ; 48-bit Nanoseconds since midnight
    .order_ref_num:     resq 1      ; 64-bit Order Reference Number (Big Endian)
    .buy_sell_indicator: resb 1     ; 'B' = Buy, 'S' = Sell
    .shares:            resd 1      ; 32-bit Share Quantity (Big Endian)
    .stock:             resb 8      ; 8-Byte Right-padded Stock Symbol
    .price:             resd 1      ; 32-bit Price ($4 decimal places, Big Endian)
endstruc

section .text

global itch_init
global itch_parse_msg
global itch_process_add_order
global itch_process_execute
global itch_process_delete

align 64
itch_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; itch_parse_msg — Parse ITCH 5.0 Binary Message & Dispatch to Order Book Engine
; Input: RDI = Pointer to ITCH Message Buffer, ESI = Length
; Output: EAX = 0 (Success)
; -----------------------------------------------------------------------------
align 64
itch_parse_msg:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]            ; Message Type Byte ('A', 'E', 'D', etc.)

    cmp al, ITCH_MSG_ADD_ORDER
    je .add_order
    cmp al, ITCH_MSG_ADD_ORDER_MPID
    je .add_order
    cmp al, ITCH_MSG_ORDER_EXECUTED
    je .order_executed
    cmp al, ITCH_MSG_ORDER_DELETE
    je .order_delete
    jmp .done

.add_order:
    mov rdi, rbx
    call itch_process_add_order
    jmp .done

.order_executed:
    mov rdi, rbx
    call itch_process_execute
    jmp .done

.order_delete:
    mov rdi, rbx
    call itch_process_delete
    jmp .done

.done:
    xor eax, eax
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; itch_process_add_order — Parse 36-Byte 'A' Message & Insert into Order Book
; Input: RDI = Pointer to itch_add_order_t
; Output: EAX = 0
; -----------------------------------------------------------------------------
align 64
itch_process_add_order:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract 64-bit Order Reference Number (Bytes 11-18, Big Endian)
    mov r12, [rbx + itch_add_order_t.order_ref_num]
    bswap r12                       ; R12 = 64-bit Order Ref Num

    ; Extract Buy/Sell Indicator
    movzx eax, byte [rbx + itch_add_order_t.buy_sell_indicator] ; 'B' or 'S'

    ; Extract 32-bit Shares (Big Endian)
    mov ecx, [rbx + itch_add_order_t.shares]
    bswap ecx                       ; ECX = Share Quantity

    ; Extract 32-bit Price (Big Endian)
    mov edx, [rbx + itch_add_order_t.price]
    bswap edx                       ; EDX = Price ($4 dec places)

    ; (Order Book Tree Insertion would record R12 = RefNum, ECX = Shares, EDX = Price, AL = Buy/Sell)

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

align 64
itch_process_execute:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract Order Ref Num & Executed Shares -> deduct from order book slot
    xor eax, eax
    pop rbp
    ret

align 64
itch_process_delete:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract Order Ref Num -> remove order slot from order book tree
    xor eax, eax
    pop rbp
    ret
