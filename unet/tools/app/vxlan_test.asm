%ifndef GUARD_UNET_TOOLS_APP_VXLAN_TEST_ASM
%define GUARD_UNET_TOOLS_APP_VXLAN_TEST_ASM
; =============================================================================
; Tattva OS — unet/tools/app/vxlan_test.asm
; =============================================================================
; VXLAN Tunnel Verification & VNI Ping Tool (`vxlan-test`).
;
; Features:
;   - UDP Port 4789 Header Encapsulation / Decapsulation Test
;   - Target VNI Verification & MTU Overhead Path Audit
;
; Delegates:
;   - VXLAN Engine                      -> unet/cloud/vxlan.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global vxlan_test_main


align 64
vxlan_test_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call vxlan_encap_packet
    call vxlan_decap_packet

    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_VXLAN_TEST_ASM
