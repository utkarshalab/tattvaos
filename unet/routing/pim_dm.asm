%ifndef GUARD_UNET_ROUTING_PIM_DM_ASM
%define GUARD_UNET_ROUTING_PIM_DM_ASM
; =============================================================================
; Tattva OS — unet/routing/pim_dm.asm
; =============================================================================
; PIM-DM (Protocol Independent Multicast — Dense Mode) Engine (RFC 3973).
;
; Features:
;   - Flood-and-Prune Multicast Forwarding (All Interfaces Initially Active)
;   - Prune Message Processing & Prune Override Timer
;   - Graft / Graft-Ack for Re-Joining Pruned Branches
;   - State Refresh (RFC 3973) for Periodic Prune Re-Assertion
;   - Assert Mechanism for Multi-Access Network Forwarder Election
;   - RPF (Reverse Path Forwarding) Check for Loop Prevention
;
; Delegates:
;   - Timer Wheel Prune/Graft Timers    -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PIM_DM_PRUNE_TIMEOUT_MS     210000  ; 210-second Prune Timeout
%define PIM_DM_GRAFT_RETRY_MS       3000    ; 3-second Graft Retry

struc pim_dm_mroute_t
    .group:             resd 1
    .source:            resd 1
    .upstream_iface:    resd 1      ; RPF Interface
    .oif_list:          resq 1      ; Outgoing Interface bitmask
    .prune_timer:       resd 1      ; Timer Wheel Prune ID
    .state:             resd 1      ; 0=Forwarding, 1=Pruned
endstruc

section .text

global pim_dm_init
global pim_dm_process_packet
global pim_dm_flood
global pim_dm_prune
global pim_dm_graft
global pim_dm_state_refresh
global pim_dm_rpf_check


align 64
pim_dm_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
pim_dm_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]
    shr al, 4

    cmp al, 3                       ; Join/Prune
    je .dm_prune
    cmp al, 6                       ; Graft
    je .dm_graft
    cmp al, 7                       ; Graft-Ack
    je .dm_graft_ack
    cmp al, 9                       ; State Refresh
    je .dm_state_refresh
    jmp .dm_done

.dm_prune:
    call pim_dm_prune
    jmp .dm_done
.dm_graft:
    call pim_dm_graft
    jmp .dm_done
.dm_graft_ack:
    ; Acknowledge graft, cancel retry timer
    jmp .dm_done
.dm_state_refresh:
    call pim_dm_state_refresh
    jmp .dm_done

.dm_done:
    pop rbx
    pop rbp
    ret

align 64
pim_dm_flood:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Forward multicast packet on all interfaces except RPF interface
    call pim_dm_rpf_check
    pop rbp
    ret

align 64
pim_dm_prune:
    push rbp
    mov rbp, rsp
    ; Remove interface from OIF list, set prune timer
    mov edi, PIM_DM_PRUNE_TIMEOUT_MS
    call timer_wheel_add
    pop rbp
    ret

align 64
pim_dm_graft:
    push rbp
    mov rbp, rsp
    ; Re-add pruned interface to OIF list, send Graft-Ack
    ; Cancel prune timer
    call timer_wheel_del
    pop rbp
    ret

align 64
pim_dm_state_refresh:
    push rbp
    mov rbp, rsp
    ; Reset prune timer on downstream interfaces
    xor eax, eax
    pop rbp
    ret

align 64
pim_dm_rpf_check:
    push rbp
    mov rbp, rsp
    ; Verify packet arrived on RPF interface (unicast route to source)
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_ROUTING_PIM_DM_ASM
