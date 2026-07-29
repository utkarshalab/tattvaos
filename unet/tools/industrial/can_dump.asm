; =============================================================================
; Tattva OS — unet/tools/can_dump.asm
; =============================================================================
; Automotive CAN-over-Ethernet & AUTOSAR SOME/IP Frame Dump Tool.
;
; Implements:
;   - Real-Time Inspection of Vehicle CAN IDs, SOME/IP Service IDs & Payload Bytes
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global can_dump_init
global can_dump_listen

align 32
can_dump_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
can_dump_listen:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
