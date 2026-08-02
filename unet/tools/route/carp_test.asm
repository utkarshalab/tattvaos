; =============================================================================
; Tattva OS — unet/tools/route/carp_test.asm
; =============================================================================
; CARP Redundancy Failover Diagnostic Tool (`carp-test`).
;
; Features:
;   - CARP AdvBase / AdvSkew Modulation & Manual Master Failover Trigger
;
; Delegates:
;   - CARP Subsystem                    -> unet/ha/carp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global carp_test_main

extern carp_send_advertisement

align 64
carp_test_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Inject CARP advertisement with AdvSkew=254 to force master failover to peer node
    call carp_send_advertisement
    pop rbp
    ret
