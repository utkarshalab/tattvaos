; =============================================================================
; Tattva OS — lib/mem/virt/ras_ecc.asm
; =============================================================================
; ECC Memory Error Detection — Subfeature 38.1.
;
; Implements handlers for tracking and reporting correctable (single-bit) and
; uncorrectable (double-bit) physical RAM errors. Correctable errors are logged
; for failure prediction, while uncorrectable errors trigger system recovery
; or shutdown paths.
;
; API:
;   ras_ecc_init()                  — Zeros all ECC telemetry counters.
;   ras_ecc_report(addr, type)      — Report ECC event (1 = Single, 2 = Double).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RAS_ECC_ASM
%define LIB_MEM_VIRT_RAS_ECC_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
ECC_ERR_SINGLE_BIT      equ 1       ; Correctable
ECC_ERR_DOUBLE_BIT      equ 2       ; Uncorrectable

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; ras_ecc_init — Initialize ECC statistics
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global ras_ecc_init
ras_ecc_init:
    mov  qword [sys_ras_ecc_single_bit_errors], 0
    mov  qword [sys_ras_ecc_double_bit_errors], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; ras_ecc_report — Record an ECC memory error event
; Input:
;   RDI = Physical address where error occurred
;   RSI = Error type (1 = Single-bit, 2 = Double-bit)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global ras_ecc_report
ras_ecc_report:
    test rdi, rdi
    jz   .fail

    cmp  rsi, ECC_ERR_SINGLE_BIT
    je   .handle_single
    cmp  rsi, ECC_ERR_DOUBLE_BIT
    je   .handle_double
    jmp  .fail

.handle_single:
    inc  qword [sys_ras_ecc_single_bit_errors]
    
    ; Also log to DIMM statistics per address
    push rdi
    call ras_dimm_log_error
    pop  rdi

    mov  rax, 1
    ret

.handle_double:
    inc  qword [sys_ras_ecc_double_bit_errors]
    
    ; Uncorrectable: triggers MCE handling logic immediately
    mov  rsi, 1                     ; indicate uncorrectable hardware error
    call ras_mce_handler
    
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_ras_ecc_single_bit_errors
sys_ras_ecc_single_bit_errors:  dq 0

align 8
global sys_ras_ecc_double_bit_errors
sys_ras_ecc_double_bit_errors:  dq 0

section .text

%endif ; LIB_MEM_VIRT_RAS_ECC_ASM
