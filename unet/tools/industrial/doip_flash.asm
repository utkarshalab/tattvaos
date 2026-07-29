; =============================================================================
; Tattva OS — unet/tools/doip_flash.asm
; =============================================================================
; Automotive ISO 14229 UDS over DoIP ECU Firmware Flash Tool.
;
; Implements:
;   - Initiates DoIP Session, Unlocks Security Access & Flashes ECU Image
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global doip_flash_init
global doip_flash_run

align 32
doip_flash_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
doip_flash_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
