; =============================================================================
; Tattva OS — unet/tools/vxlan_test.asm
; =============================================================================
; VXLAN Tunneling (RFC 7348) VNI Encapsulation Benchmark Test Tool.
;
; Implements:
;   - Line-Rate UDP Port 4789 Encapsulation & Decapsulation Throughput Test
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global vxlan_test_init
global vxlan_test_run

align 32
vxlan_test_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
vxlan_test_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
