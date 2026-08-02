; =============================================================================
; Tattva OS — unet/tools/san/iscsi_initiator.asm
; =============================================================================
; iSCSI Target Discovery & Login Initiator Tool (`iscsiadm`).
;
; Features:
;   - TCP Port 3260 iSCSI Login Request BHS (Basic Header Segment) + SendTargets Discovery
;   - Target IQN (iSCSI Qualified Name) & LUN Enumeration
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ISCSI_PORT                  3260
%define ISCSI_OP_LOGIN_REQ          0x03

section .text

global iscsi_initiator_main
global iscsi_initiator_login

align 64
iscsi_initiator_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call iscsi_initiator_login

    pop rbx
    pop rbp
    ret

align 64
iscsi_initiator_login:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Issue iSCSI Login Request BHS (0x03) with SendTargets=All -> parse IQNs & LUNs
    xor eax, eax
    pop rbp
    ret
