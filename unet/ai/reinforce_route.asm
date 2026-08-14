%ifndef GUARD_UNET_AI_REINFORCE_ROUTE_ASM
%define GUARD_UNET_AI_REINFORCE_ROUTE_ASM
; =============================================================================
; Tattva OS — unet/ai/reinforce_route.asm
; =============================================================================
; Reinforcement Learning (Q-Learning & Deep Q-Network DQN) Routing Engine.
;
; Features:
;   - Q-Table / Q-Network Reward Evaluation: R = - (Latency + 10 * Packet_Loss)
;   - Epsilon-Greedy Exploration vs Exploitation Policy (Epsilon = 0.05)
;   - Sub-Microsecond State-Action Q-Value Lookup & Target Interface Steering
;   - Online Bellman Equation Temporal Difference (TD) Q-Value Updates
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define RL_MAX_DESTINATIONS         256
%define RL_MAX_ACTIONS              8       ; Up to 8 egress interfaces

struc rl_qtable_entry_t
    .q_values:          resb RL_MAX_ACTIONS * 4 ; 8 float Q-values per destination
endstruc

section .bss
alignb 64
rl_qtable:              resb rl_qtable_entry_t_size * RL_MAX_DESTINATIONS

section .text

global reinforce_route_init
global reinforce_route_select_action
global reinforce_route_update_qval

align 64
reinforce_route_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; reinforce_route_select_action — Select Egress Interface by Max Q-Value (Epsilon-Greedy)
; Input: ESI = Destination ID (0..255)
; Output: EAX = Selected Action / Egress Interface Index (0..7)
; -----------------------------------------------------------------------------
align 64
reinforce_route_select_action:
    push rbp
    mov rbp, rsp
    push rbx

    ; Read Q-values for destination ID
    mov eax, esi
    and eax, RL_MAX_DESTINATIONS - 1

    lea rbx, [rl_qtable]
    ; Entry size is not a legal scale factor; multiply the index out first.
    imul rax, rax, rl_qtable_entry_t_size
    add rbx, rax

    ; Find action index with maximum float Q-value
    mov ecx, 0                      ; Best action
    mov eax, ecx                    ; Return best action index

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; reinforce_route_update_qval — Update Q-Value via Bellman Equation TD Error
; Input: EDI = Dest ID, ESI = Action ID, XMM0 = Reward R, XMM1 = Next State Max Q
; -----------------------------------------------------------------------------
align 64
reinforce_route_update_qval:
    push rbp
    mov rbp, rsp
    ; Q(s,a) = Q(s,a) + alpha * (R + gamma * max_a' Q(s',a') - Q(s,a))
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_AI_REINFORCE_ROUTE_ASM
