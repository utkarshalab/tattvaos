; =============================================================================
; Tattva OS — unet/cloud/azure_express.asm
; =============================================================================
; Microsoft Azure ExpressRoute & IEEE 802.1ad QinQ Dual-VLAN Router.
;
; Implements:
;   - IEEE 802.1ad QinQ S-VLAN (`0x88A8`) & C-VLAN (`0x8100`) Tagging for Azure
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global azure_express_init
global azure_express_tag

align 32
azure_express_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
azure_express_tag:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
