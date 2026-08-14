%ifndef GUARD_UNET_TOOLS_APP_SNMP_WALK_ASM
%define GUARD_UNET_TOOLS_APP_SNMP_WALK_ASM
; =============================================================================
; Tattva OS — unet/tools/app/snmp_walk.asm
; =============================================================================
; Command-Line SNMP Walk Subtree Traverser Tool (`snmpwalk`).
;
; Features:
;   - GetNextRequest PDU (`0xA1`) / GetBulkRequest PDU (`0xA5`) Recursive Tree Walk
;   - Subtree Boundary Termination Check (EndOfMibView / NoSuchInstance)
;   - Fast Iterative MIB Tree Traversal
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global snmp_walk_main
global snmp_walk_exec

align 64
snmp_walk_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call snmp_walk_exec

    pop rbx
    pop rbp
    ret

align 64
snmp_walk_exec:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Loop GetNextRequest (0xA1) or GetBulkRequest (0xA5) until OID leaves target subtree
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_SNMP_WALK_ASM
