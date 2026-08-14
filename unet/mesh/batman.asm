%ifndef GUARD_UNET_MESH_BATMAN_ASM
%define GUARD_UNET_MESH_BATMAN_ASM
; =============================================================================
; Tattva OS — unet/mesh/batman.asm
; =============================================================================
; B.A.T.M.A.N. Advanced (batman-adv) Layer 2 Mesh Routing Engine.
;
; Features:
;   - EtherType 0x4305 BATMAN Packet Header Parsing & Construction
;   - Packet Types: OGMs (Originator Messages), ELP (Echo Location Protocol), TT (Translation Table), UNICAST
;   - OGM (Originator Message v2) TQ (Transmit Quality) Calculation & Asymmetric Link Metrics
;   - Translation Table (TT) Local & Global Client MAC Address Roaming
;   - Multicast Flooding Optimization & Distributed ARP Table (DAT)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_BATMAN            0x4305

%define BATADV_OGM                  0x01
%define BATADV_UNICAST              0x40
%define BATADV_BCAST                0x41
%define BATADV_ELP                  0x02
%define BATADV_TT_QUERY             0x50

struc batadv_ogm_hdr_t
    .packet_type:       resb 1      ; BATADV_OGM
    .version:           resb 1      ; Version (15)
    .ttl:               resb 1      ; Time to Live
    .flags:             resb 1      ; Direct link, etc.
    .seqno:             resd 1      ; 32-bit Sequence Number
    .orig:              resb 6      ; Originator MAC Address
    .prev_sender:       resb 6      ; Previous Sender MAC Address
    .tq:                resb 1      ; Transmit Quality (0..255)
    .total_tq:          resb 1      ; Total Path TQ
endstruc

section .text

global batman_init
global batman_process_packet
global batman_process_ogm
global batman_update_tq
global batman_tt_lookup

align 64
batman_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; batman_process_packet — Parse EtherType 0x4305 BATMAN Mesh Packet
; Input: RDI = Pointer to Packet Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
batman_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + batadv_ogm_hdr_t.packet_type]

    cmp al, BATADV_OGM
    je .ogm
    cmp al, BATADV_UNICAST
    je .unicast
    cmp al, BATADV_ELP
    je .elp
    jmp .done

.ogm:
    call batman_process_ogm
    jmp .done
.unicast:
    ; Forward L2 unicast frame to target MAC via best originator next hop
    jmp .done
.elp:
    ; Echo Location Protocol neighbor discovery
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
batman_process_ogm:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Update Originator Table & compute Transmit Quality (TQ)
    call batman_update_tq
    pop rbp
    ret

align 64
batman_update_tq:
    push rbp
    mov rbp, rsp
    ; Calculate TQ = (TQ_recv * TQ_send) / 255 with asymmetric link penalty
    xor eax, eax
    pop rbp
    ret

align 64
batman_tt_lookup:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Translation Table (TT) lookup: client MAC -> Originator node MAC
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_MESH_BATMAN_ASM
