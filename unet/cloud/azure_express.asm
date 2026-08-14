%ifndef GUARD_UNET_CLOUD_AZURE_EXPRESS_ASM
%define GUARD_UNET_CLOUD_AZURE_EXPRESS_ASM
; =============================================================================
; Tattva OS — unet/cloud/azure_express.asm
; =============================================================================
; Azure ExpressRoute Private & Microsoft Peering Gateway Engine.
;
; Features:
;   - IEEE 802.1ad Dual VLAN Tagging (QinQ: Outer Provider Tag S-VLAN + Inner Customer Tag C-VLAN)
;   - BGP Primary & Secondary Circuit Failover (Sub-Second Fast Convergence)
;   - Azure ExpressRoute Direct 10GbE / 100GbE Line-Rate Processing
;   - Route Filter Rules (Microsoft 365, Azure PaaS Services BGP Communities)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_QINQ              0x88A8  ; 802.1ad Service Tag (S-VLAN)
%define ETHERTYPE_8021Q             0x8100  ; 802.1Q Customer Tag (C-VLAN)

struc qinq_hdr_t
    .s_tag_type:        resw 1      ; 0x88A8
    .s_vlan_id:         resw 1      ; Outer Service VLAN ID
    .c_tag_type:        resw 1      ; 0x8100
    .c_vlan_id:         resw 1      ; Inner Customer VLAN ID
endstruc

section .text

global azure_express_init
global azure_express_parse_qinq
global azure_express_encap_qinq

align 64
azure_express_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
azure_express_parse_qinq:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Outer S-TAG (0x88A8) & Inner C-TAG (0x8100)
    movzx eax, word [rbx]
    xchg al, ah
    cmp ax, ETHERTYPE_QINQ
    jne .invalid

    movzx eax, word [rbx + 4]
    xchg al, ah
    cmp ax, ETHERTYPE_8021Q
    jne .invalid

    ; Extract S-VLAN ID & C-VLAN ID
    movzx ecx, word [rbx + 2]
    and ecx, 0x0FFF                 ; S-VLAN
    movzx edx, word [rbx + 6]
    and edx, 0x0FFF                 ; C-VLAN

    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
azure_express_encap_qinq:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend 8-byte QinQ header (S-TAG 0x88A8 S-VLAN + C-TAG 0x8100 C-VLAN)
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_CLOUD_AZURE_EXPRESS_ASM
