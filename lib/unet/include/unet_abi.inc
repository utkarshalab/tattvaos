; =============================================================================
; Tattva OS — unet/include/unet_abi.inc
; =============================================================================
; System V x86-64 Register Calling Convention & ABI Interop Definitions.
;
; Features:
;   - System V x86-64 ABI Register Rules (RDI, RSI, RDX, RCX, R8, R9)
;   - Stack Alignment Requirements (16-Byte Boundary Enforcement)
;   - Vector Register Usage (YMM/ZMM Volatile vs Non-Volatile)
;   - C-to-Assembly Foreign Function Interface (FFI) Return Conventions
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UNET_ABI_INC
%define UNET_ABI_INC

; -----------------------------------------------------------------------------
; System V x86-64 Argument Register Mapping
; -----------------------------------------------------------------------------
; RDI = Argument 1
; RSI = Argument 2
; RDX = Argument 3
; RCX = Argument 4
; R8  = Argument 5
; R9  = Argument 6
; RAX = Return Value / Syscall Number
; RDX:RAX = 128-Bit Return Value
;
; Callee-Saved (Preserved across calls):
;   RBX, RBP, R12, R13, R14, R15
; Caller-Saved (Scratch / Volatile):
;   RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11, XMM0..XMM15, YMM0..YMM15, ZMM0..ZMM31
; -----------------------------------------------------------------------------

%macro ALIGN_STACK_16 0
    mov r11, rsp
    and rsp, -16
    push r11
%endmacro

%macro RESTORE_STACK_16 0
    pop rsp
%endmacro

%endif ; UNET_ABI_INC
