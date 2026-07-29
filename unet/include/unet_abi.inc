; =============================================================================
; Tattva OS — unet/include/unet_abi.inc
; =============================================================================
; System V x86-64 Register Calling Convention & ABI Interop Definitions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UNET_ABI_INC
%define UNET_ABI_INC

; Register Usage Guidelines:
;   RDI = Argument 1
;   RSI = Argument 2
;   RDX = Argument 3
;   RCX = Argument 4
;   R8  = Argument 5
;   R9  = Argument 6
;   RAX = Return Value / System Call Number
;   RBX, RBP, R12..R15 = Callee-Saved Registers

%endif ; UNET_ABI_INC
