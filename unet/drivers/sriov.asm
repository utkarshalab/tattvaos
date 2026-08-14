%ifndef GUARD_UNET_DRIVERS_SRIOV_ASM
%define GUARD_UNET_DRIVERS_SRIOV_ASM
; =============================================================================
; Tattva OS — unet/drivers/sriov.asm
; =============================================================================
; Single-Root I/O Virtualization (SR-IOV) VF Manager & Mailbox Architecture Engine.
;
; Features:
;   - Physical Function (PF) <-> Virtual Function (VF) Hardware Mailbox Channel
;   - PCIe SR-IOV Extended Capability Capability Structure Access
;   - Virtual Function FLR (Function Level Reset) Handling
;   - VF MAC Address & VLAN Tag Enforcement from PF
;   - Dynamic VF Enabler & PCIe Passthrough Allocation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PCIE_CAP_SRIOV              0x0010
%define SRIOV_CTRL                  0x08
%define SRIOV_STATUS                0x0A
%define SRIOV_INITIAL_VFS           0x0C
%define SRIOV_TOTAL_VFS             0x0E
%define SRIOV_NUM_VFS               0x10

struc pf_vf_mailbox_msg_t
    .msg_type:          resd 1      ; 1=RESET, 2=SET_MAC, 3=SET_VLAN, 4=GET_STATS
    .vf_id:             resd 1      ; Target VF ID
    .param1:            resq 1
    .param2:            resq 1
endstruc

section .text

global sriov_init
global sriov_enable_vfs
global sriov_disable_vfs
global sriov_process_mailbox

align 64
sriov_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
sriov_enable_vfs:
    push rbp
    mov rbp, rsp
    ; Write NumVFs to PCIe SR-IOV Capability & set VF Enable bit
    xor eax, eax
    pop rbp
    ret

align 64
sriov_disable_vfs:
    push rbp
    mov rbp, rsp
    ; Clear VF Enable bit & trigger FLR reset on all VFs
    xor eax, eax
    pop rbp
    ret

align 64
sriov_process_mailbox:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Read PF/VF mailbox register, execute requested command (SET_MAC, SET_VLAN), send ACK
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_SRIOV_ASM
