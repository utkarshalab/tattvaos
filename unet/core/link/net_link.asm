; =============================================================================
; Tattva OS — unet/core/link/net_link.asm
; =============================================================================
; Top-level wrapper for the modular zero-copy network link layer subsystem.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_NET_LINK_ASM
%define UNET_CORE_LINK_NET_LINK_ASM

[BITS 64]

; 1. Base Shared Include Declarations
%include "unet/core/link/net_ring.inc"
%include "unet/unet.inc"

; 2. Modular Subsystems
%include "unet/core/link/net_ring.asm"
%include "unet/core/link/ring.asm"
%include "unet/core/link/pci.asm"
%include "unet/core/link/loan.asm"
%include "unet/core/link/sbuf.asm"
%include "unet/core/link/recycle.asm"
%include "unet/core/link/rss.asm"

; -----------------------------------------------------------------------------
; net_link_transmit — Single seam between L2 (eth_output) and whatever NIC
; driver actually claimed the hardware. Only e1000 is wired up (see
; unet/drivers/e1000.asm's e1000_probe); a second driver would add its own
; "is this device present" flag and an else-if here rather than eth_output
; needing to know about drivers at all.
;
; net_link_transmit always takes ownership of the buffer, but does NOT
; always free it: on a successful hand-off, e1000_transmit stashes the
; pointer for e1000_tx_reclaim to free once the hardware confirms it has
; actually finished DMA'ing the frame out (see e1000_transmit's comment) —
; freeing it here instead would race the NIC. Only the failure paths (no
; link, ring full) free immediately, since nothing else owns the buffer then.
; Input: RDI = net_pkt_t* (headroom_offset/data_len cover the whole frame)
; Output: EAX = 0 on success, -1 if no NIC claimed the hardware / ring full
; -----------------------------------------------------------------------------
section .text
global net_link_transmit
align 64
net_link_transmit:
    push rbx
    mov rbx, rdi

    cmp byte [e1000_present], 0
    je .no_link

    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx                    ; RAX = frame start

    mov rdi, [e1000_bar0_virt]
    mov rsi, [e1000_tx_ring_virt]
    mov rdx, rax
    mov ecx, [rbx + net_pkt_t.data_len]
    mov r8, rbx
    call e1000_transmit
    test eax, eax
    jz .done                        ; queued: e1000_tx_reclaim owns the free now

    mov rdi, rbx
    call pktbuf_free
    mov eax, -1
    jmp .done

.no_link:
    mov rdi, rbx
    call pktbuf_free
    mov eax, -1
.done:
    pop rbx
    ret

%endif ; UNET_CORE_LINK_NET_LINK_ASM
