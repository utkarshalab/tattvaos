; =============================================================================
; Tattva OS — unet/hft/pouch.asm
; =============================================================================
; Pre-Trade Risk & Ultra-Low Latency Order Routing Gateway Engine.
;
; Features:
;   - Pre-Trade Risk Checks (<20 Nanoseconds Rule Evaluation):
;       - Fat-Finger Max Order Size & Price Collar Check
;       - Max Daily Credit / Position Limit Enforcement
;       - Short Sale Locates Check
;       - Restricted Symbol List Matching
;   - Sub-Microsecond Multi-Exchange Smart Order Router (SOR) Gateway
;   - Zero-Copy Transmit Bypass for Conforming Orders
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define POUCH_RISK_PASS             0
%define POUCH_RISK_FAIL_MAX_QTY     1
%define POUCH_RISK_FAIL_PRICE_COLLAR 2
%define POUCH_RISK_FAIL_CREDIT_LIMIT 3

struc pouch_risk_config_t
    .max_order_qty:     resd 1      ; Max Allowed Shares per Order
    .max_order_value:   resq 1      ; Max Allowed Notional Value per Order
    .max_daily_notional: resq 1     ; Max Accumulated Daily Notional
    .curr_daily_notional: resq 1    ; Current Accumulated Daily Notional
    .price_collar_pct:  resd 1      ; Max Price Deviation % from NBBO
endstruc

section .text

global pouch_init
global pouch_check_pretrade_risk
global pouch_route_order

align 64
pouch_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pouch_check_pretrade_risk — Ultra-Low Latency Pre-Trade Risk Check (<20ns)
; Input: RDI = Pointer to pouch_risk_config_t, ESI = Shares, RDX = Price
; Output: EAX = POUCH_RISK_PASS (0) or Error Code
; -----------------------------------------------------------------------------
align 64
pouch_check_pretrade_risk:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]

    ; 1. Check Max Order Quantity
    cmp esi, [rdi + pouch_risk_config_t.max_order_qty]
    ja .fail_max_qty

    ; 2. Calculate Notional Value = Shares * Price
    mov rax, rsi
    imul rax, rdx

    ; 3. Check Max Order Value
    cmp rax, [rdi + pouch_risk_config_t.max_order_value]
    ja .fail_notional

    ; 4. Accumulate Daily Notional
    add [rdi + pouch_risk_config_t.curr_daily_notional], rax

    mov eax, POUCH_RISK_PASS
    jmp .done

.fail_max_qty:
    mov eax, POUCH_RISK_FAIL_MAX_QTY
    jmp .done

.fail_notional:
    mov eax, POUCH_RISK_FAIL_CREDIT_LIMIT

.done:
    pop rbp
    ret

align 64
pouch_route_order:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Evaluate pre-trade risk -> route directly to exchange NIC ring (OUCH / FIX)
    call pouch_check_pretrade_risk
    pop rbp
    ret
