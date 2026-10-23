%ifndef GUARD_PLATFORM_X86_64_PLATFORM_ASM
%define GUARD_PLATFORM_X86_64_PLATFORM_ASM
; =============================================================================
; File     : platform/x86_64/platform.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: x86_64 platform-specific initialization and support code.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; platform_init — Initialize platform-specific hardware
; Input:  none
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global platform_init
platform_init:
    ret

; -----------------------------------------------------------------------------
; platform_halt — Halt the platform
; Input:  none
; Output: never returns
; -----------------------------------------------------------------------------
global platform_halt
platform_halt:
    cli
    hlt
    jmp platform_halt

%endif ; GUARD_PLATFORM_X86_64_PLATFORM_ASM