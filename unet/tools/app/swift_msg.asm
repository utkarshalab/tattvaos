%ifndef GUARD_UNET_TOOLS_APP_SWIFT_MSG_ASM
%define GUARD_UNET_TOOLS_APP_SWIFT_MSG_ASM
; =============================================================================
; Tattva OS — unet/tools/app/swift_msg.asm
; =============================================================================
; Command-Line SWIFT FIN MT103 / MT202 Message Generator & Parser (`swift-msg`).
;
; Features:
;   - SWIFT Block 1..5 Framing Generator
;   - Field :20: TRN, :32A: Value Date/CCY/Amount Validation
;
; Delegates:
;   - SWIFT Engine                      -> unet/fintech/swift.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global swift_msg_main


align 64
swift_msg_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Format & parse SWIFT FIN MT103 credit transfer message string
    call swift_parse_fin
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_SWIFT_MSG_ASM
