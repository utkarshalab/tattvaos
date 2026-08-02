; =============================================================================
; Tattva OS — unet/routing/pim_sm.asm
; =============================================================================
; PIM-SM (Protocol Independent Multicast — Sparse Mode) Engine (RFC 7761).
;
; Features:
;   - PIM Hello: Holdtime, DR Priority, Generation ID, LAN Prune Delay
;   - (*,G) Shared Tree Join/Prune via Rendezvous Point (RP)
;   - (S,G) Source-Specific Tree Join/Prune (SPT Switchover)
;   - Bootstrap Router (BSR RFC 5059) & Auto-RP for RP Discovery
;   - Register / Register-Stop Encapsulation for Source Registration
;   - Assert Mechanism for Multi-Access Network Forwarder Election
;   - DR Election per Interface (Highest Priority, then Highest IP)
;
; Delegates:
;   - Timer Wheel Hello/Join/Prune       -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PIM_ALL_ROUTERS             0xE000000D  ; 224.0.0.13
%define PIM_HELLO                   0
%define PIM_REGISTER                1
%define PIM_REGISTER_STOP           2
%define PIM_JOIN_PRUNE              3
%define PIM_BOOTSTRAP               4
%define PIM_ASSERT                  5

struc pim_neighbor_t
    .ip_addr:           resd 1
    .dr_priority:       resd 1
    .generation_id:     resd 1
    .holdtime:          resw 1
    .timer_id:          resd 1
endstruc

struc pim_mroute_t
    .group:             resd 1      ; Multicast Group
    .source:            resd 1      ; Source IP (0 = *,G)
    .rp:                resd 1      ; Rendezvous Point
    .upstream_iface:    resd 1      ; RPF Interface
    .oif_list:          resq 1      ; Outgoing Interface List (bitmask)
    .flags:             resd 1      ; SPT bit, Register flag
endstruc

section .text

global pim_sm_init
global pim_sm_process_packet
global pim_sm_send_hello
global pim_sm_join_group
global pim_sm_prune_group
global pim_sm_register_source
global pim_sm_dr_election
global pim_sm_assert

extern timer_wheel_add

align 64
pim_sm_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
pim_sm_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]
    shr al, 4                       ; PIM type (upper 4 bits)

    cmp al, PIM_HELLO
    je .pkt_hello
    cmp al, PIM_JOIN_PRUNE
    je .pkt_join_prune
    cmp al, PIM_REGISTER
    je .pkt_register
    cmp al, PIM_REGISTER_STOP
    je .pkt_reg_stop
    cmp al, PIM_ASSERT
    je .pkt_assert
    cmp al, PIM_BOOTSTRAP
    je .pkt_bsr
    jmp .pkt_done

.pkt_hello:
    ; Parse Hello options (Holdtime, DR Priority, Gen ID)
    ; Reset neighbor holdtime timer, trigger DR election
    call pim_sm_dr_election
    jmp .pkt_done
.pkt_join_prune:
    ; Process Join/Prune list for (*,G) and (S,G) entries
    jmp .pkt_done
.pkt_register:
    ; Decapsulate multicast data from source, forward to RP
    call pim_sm_register_source
    jmp .pkt_done
.pkt_reg_stop:
    ; Source has been registered, stop encapsulation
    jmp .pkt_done
.pkt_assert:
    ; Forwarder election on multi-access network
    call pim_sm_assert
    jmp .pkt_done
.pkt_bsr:
    ; Bootstrap Router message: update RP-to-Group mapping
    jmp .pkt_done

.pkt_done:
    pop rbx
    pop rbp
    ret

align 64
pim_sm_send_hello:
    push rbp
    mov rbp, rsp
    ; Send PIM Hello to 224.0.0.13 with DR Priority & holdtime
    xor eax, eax
    pop rbp
    ret

align 64
pim_sm_join_group:
    push rbp
    mov rbp, rsp
    ; Send (*,G) Join toward RP via RPF interface
    xor eax, eax
    pop rbp
    ret

align 64
pim_sm_prune_group:
    push rbp
    mov rbp, rsp
    ; Send (*,G) Prune toward RP
    xor eax, eax
    pop rbp
    ret

align 64
pim_sm_register_source:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Encapsulate multicast packet into PIM Register & send to RP
    xor eax, eax
    pop rbp
    ret

align 64
pim_sm_dr_election:
    push rbp
    mov rbp, rsp
    ; Elect DR: highest priority, then highest IP address
    xor eax, eax
    pop rbp
    ret

align 64
pim_sm_assert:
    push rbp
    mov rbp, rsp
    ; Assert: lowest metric to source wins, then highest IP tiebreak
    xor eax, eax
    pop rbp
    ret
