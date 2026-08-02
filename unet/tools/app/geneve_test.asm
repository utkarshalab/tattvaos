; =============================================================================
; Tattva OS — unet/tools/app/geneve_test.asm
; =============================================================================
; GENEVE Tunnel Verification & TLV Options Tester (`geneve-test`).
;
; Features:
;   - UDP Port 6081 Header & TLV Options Injection Test
;   - Variable Length Option Field Validation
;
; Delegates:
;   - GENEVE Engine                     -> unet/cloud/geneve.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global geneve_test_main

extern geneve_encap_packet
extern geneve_decap_packet

align 64
geneve_test_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call geneve_encap_packet
    call geneve_decap_packet

    pop rbx
    pop rbp
    ret
