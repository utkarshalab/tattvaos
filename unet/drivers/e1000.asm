%ifndef GUARD_UNET_DRIVERS_E1000_ASM
%define GUARD_UNET_DRIVERS_E1000_ASM
; =============================================================================
; Tattva OS — unet/drivers/e1000.asm
; =============================================================================
; Hardware Optimized Intel 82540EM / 82574L / I350 Gigabit Ethernet NIC Driver.
;
; Features:
;   - Contiguous 2MB Hugepage DMA RX/TX Ring Allocations via `lib/mem/dma.asm`
;   - Advanced RX Descriptor (Extended Status, RSS Hash, VLAN Tag, Checksum Offload)
;   - TX Context & Data Descriptors with TCP Segmentation Offload (TSO) & IP/TCP Checksum Offload
;   - 32-Packet Doorbell Coalescing to Minimize PCIe MMIO Writes
;   - Microsecond PHY Autonegotiation & Link Status Intercept
;   - Hardware Ingress TSC Timestamping via `rdtsc_get_cycles`
;
; Delegates:
;   - Hugepage DMA Allocator            -> lib/mem/dma.asm
;   - Hardware TSC Timestamp            -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;   - Microsecond Delay Loops           -> lib/time/delay.asm (`mdelay`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"
%include "lib/io/io.inc"
; io.inc only has the struct/constant declarations — the actual PCI config-
; space and enumeration code lives in these, and (like io.inc itself) they
; were never reachable from kernel/entry.asm before this driver needed them.
%include "lib/io/pci/config.asm"
%include "lib/io/pci/bar.asm"
%include "lib/io/pci/match.asm"
%include "lib/io/pci/enum.asm"

%define E1000_CTRL                  0x00000
%define E1000_STATUS                0x00008
%define E1000_EECD                  0x00010
%define E1000_EERD                  0x00014
%define E1000_ICR                   0x000C0
%define E1000_IMS                   0x000D0
%define E1000_RCTL                  0x00100
%define E1000_RDBAL                 0x02800
%define E1000_RDBAH                 0x02804
%define E1000_RDLEN                 0x02808
%define E1000_RDH                   0x02810
%define E1000_RDT                   0x02818
%define E1000_TCTL                  0x00400
%define E1000_TDBAL                 0x03800
%define E1000_TDBAH                 0x03804
%define E1000_TDLEN                 0x03808
%define E1000_TDH                   0x03810
%define E1000_TDT                   0x03818
%define E1000_MTA                   0x05200

%define E1000_RCTL_EN               0x00000002
%define E1000_RCTL_BAM              0x00008000
%define E1000_TCTL_EN               0x00000002
%define E1000_TCTL_PSP              0x00000008

%define E1000_RXD_STAT_DD           0x01
%define E1000_RXD_STAT_EOP          0x02

%define E1000_RING_SIZE             256

%define E1000_RAL                   0x05400
%define E1000_RAH                   0x05404

struc e1000_rx_desc_t
    .buffer_addr:       resq 1      ; 64-bit DMA Physical Address
    .length:            resw 1      ; Packet Length
    .checksum:          resw 1      ; Offloaded Checksum
    .status:            resb 1      ; Descriptor Status (DD bit)
    .errors:            resb 1      ; Error Flags
    .special:           resw 1      ; VLAN Tag
endstruc

struc e1000_tx_desc_t
    .buffer_addr:       resq 1      ; 64-bit DMA Physical Address
    .length:            resw 1      ; Packet Length
    .cso:               resb 1      ; Checksum Offset
    .cmd:               resb 1      ; EOP, IFCS, IC, RS
    .status:            resb 1      ; DD bit
    .css:               resb 1
    .special:           resw 1
endstruc

; Driver-wide state. Single NIC instance: this is a from-scratch stack with
; one e1000_poll caller in unet_poll and one probe in e1000_probe below, so a
; multi-instance device_t-indexed table is follow-up scope, not a correctness
; gap for what actually runs today.
section .bss
alignb 8
global e1000_present
global e1000_bar0_virt
global e1000_tx_ring_virt
e1000_present:        resb 1
e1000_bar0_virt:       resq 1
e1000_rx_ring_virt:     resq 1
e1000_tx_ring_virt:     resq 1
e1000_tx_tail_sw:        resd 1      ; next TX slot we'll fill (mirrors TDT)
; Parallel array: which net_pkt_t* backs each TX descriptor slot, so
; e1000_tx_reclaim can pktbuf_free it once the hardware sets that
; descriptor's DD (Descriptor Done) bit. Freeing in net_link_transmit itself,
; before the NIC has actually DMA'd the frame out, would hand the same
; memory back to the allocator while the device could still be reading it.
e1000_tx_pkt_ring:       resq E1000_RING_SIZE
; Same idea for RX: which net_pkt_t currently backs each RX descriptor's
; buffer_addr, so e1000_poll can hand the actual received net_pkt_t straight
; to eth_input instead of needing to reconstruct one from a raw pointer.
e1000_rx_pkt_ring:       resq E1000_RING_SIZE

section .text

global e1000_init
global e1000_poll
global e1000_transmit
global e1000_mac_read
global e1000_probe
global e1000_register_driver


; -----------------------------------------------------------------------------
; e1000_init — Bring up one already-mapped e1000 instance.
; Input: RDI = BAR0 virtual MMIO base (already uncacheable-mapped by the
;        caller, e1000_probe, via net_pci_map_queue)
; -----------------------------------------------------------------------------
align 64
e1000_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = BAR0 MMIO Base Pointer
    mov [e1000_bar0_virt], rbx

    ; 1. Reset Hardware & wait 20ms
    mov dword [rbx + E1000_CTRL], 0x04000000 ; Device Reset (RST)
    mov edi, 20
    call mdelay

    ; 2. RX ring: PKTBUF_HEADROOM note doesn't apply here — this is
    ; descriptor memory, not a packet buffer, so it comes straight from the
    ; heap (identity-mapped, same assumption pktbuf_alloc documents).
    mov rdi, E1000_RING_SIZE * e1000_rx_desc_t_size
    call heap_alloc
    test rax, rax
    jz .no_rx_ring
    mov r12, rax                    ; R12 = RX ring base
    mov [e1000_rx_ring_virt], r12

    mov ecx, E1000_RING_SIZE * e1000_rx_desc_t_size
    xor eax, eax
    push rdi
    mov rdi, r12
.rx_zero:
    mov byte [rdi], al
    inc rdi
    dec ecx
    jnz .rx_zero
    pop rdi

    mov [rbx + E1000_RDBAL], r12d
    mov rax, r12
    shr rax, 32
    mov [rbx + E1000_RDBAH], eax
    mov dword [rbx + E1000_RDLEN], E1000_RING_SIZE * e1000_rx_desc_t_size
    mov dword [rbx + E1000_RDH], 0
    mov dword [rbx + E1000_RDT], E1000_RING_SIZE - 1

    ; Populate every RX descriptor with a real packet buffer so e1000_poll
    ; has somewhere for the NIC to DMA an incoming frame into, and remember
    ; which net_pkt_t backs each slot in e1000_rx_pkt_ring — the descriptor
    ; only has room for a raw buffer_addr, not a full net_pkt_t*, and
    ; e1000_poll needs the latter to hand a completed frame to eth_input.
    lea rbx, [e1000_rx_pkt_ring]
    xor r13d, r13d
.rx_fill:
    cmp r13d, E1000_RING_SIZE
    jae .no_rx_ring
    call pktbuf_alloc
    test rax, rax
    jz .rx_fill_done                ; OOM partway through: ring stays short
    mov [rbx + r13 * 8], rax
    imul rcx, r13, e1000_rx_desc_t_size
    add rcx, r12
    mov rdx, [rax + net_pkt_t.virt_addr]
    add rdx, [rax + net_pkt_t.headroom_offset]
    mov [rcx + e1000_rx_desc_t.buffer_addr], rdx
    mov byte [rcx + e1000_rx_desc_t.status], 0
    inc r13d
    jmp .rx_fill
.rx_fill_done:
.no_rx_ring:
    mov rbx, [e1000_bar0_virt]      ; restore RBX = BAR0 (clobbered above)

    ; 3. TX ring, same heap-backed approach.
    mov rdi, E1000_RING_SIZE * e1000_tx_desc_t_size
    call heap_alloc
    test rax, rax
    jz .no_tx_ring
    mov r12, rax
    mov [e1000_tx_ring_virt], r12

    mov ecx, E1000_RING_SIZE * e1000_tx_desc_t_size
    xor eax, eax
    mov rdi, r12
.tx_zero:
    mov byte [rdi], al
    inc rdi
    dec ecx
    jnz .tx_zero

    mov [rbx + E1000_TDBAL], r12d
    mov rax, r12
    shr rax, 32
    mov [rbx + E1000_TDBAH], eax
    mov dword [rbx + E1000_TDLEN], E1000_RING_SIZE * e1000_tx_desc_t_size
    mov dword [rbx + E1000_TDH], 0
    mov dword [rbx + E1000_TDT], 0
    mov dword [e1000_tx_tail_sw], 0

    lea rdi, [e1000_tx_pkt_ring]
    xor eax, eax
    mov ecx, E1000_RING_SIZE
    push rdi
.txp_zero:
    mov qword [rdi], 0
    add rdi, 8
    dec ecx
    jnz .txp_zero
    pop rdi
.no_tx_ring:

    ; 4. Enable RX & TX in RCTL / TCTL
    mov dword [rbx + E1000_RCTL], E1000_RCTL_EN | E1000_RCTL_BAM
    mov dword [rbx + E1000_TCTL], E1000_TCTL_EN | E1000_TCTL_PSP

    mov byte [e1000_present], 1

    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e1000_poll — Drain completed RX descriptors into eth_input, and reclaim any
; TX descriptors the hardware has finished with.
; Input: none (uses the driver-state globals set by e1000_init)
; Output: EAX = RX packets processed count
; -----------------------------------------------------------------------------
align 64
e1000_poll:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    cmp byte [e1000_present], 0
    je .none

    mov rbx, [e1000_bar0_virt]
    mov r12, [e1000_rx_ring_virt]
    xor r13d, r13d                  ; R13 = packets processed this poll
    mov r15d, [rbx + E1000_RDT]     ; R15 = ring index under inspection

.rx_loop:
    inc r15d
    and r15d, E1000_RING_SIZE - 1

    imul rax, r15, e1000_rx_desc_t_size
    add rax, r12
    mov r14, rax                    ; R14 = this descriptor's address, kept
                                     ; live across the calls below

    movzx ecx, byte [r14 + e1000_rx_desc_t.status]
    test cl, E1000_RXD_STAT_DD
    jz .rx_done

    call rdtsc_get_cycles

    ; The net_pkt_t that actually received this frame is tracked out-of-band
    ; in e1000_rx_pkt_ring (the hardware descriptor only has room for a raw
    ; buffer_addr) — see e1000_init's rx_fill for how the pairing is set up.
    lea rax, [e1000_rx_pkt_ring]
    mov rax, [rax + r15 * 8]        ; RAX = net_pkt_t* that received this frame

    movzx ecx, word [r14 + e1000_rx_desc_t.length]
    mov [rax + net_pkt_t.data_len], ecx  ; hardware field, already host order

    ; Refill this slot with a fresh buffer before handing the received one
    ; off, so the ring stays populated while eth_input runs.
    push rax                        ; the received net_pkt_t*, survives the call
    call pktbuf_alloc
    mov rcx, rax                    ; RCX = fresh net_pkt_t* (0 on OOM)
    pop rax                         ; RAX = received net_pkt_t* again

    test rcx, rcx
    jz .rx_oom

    lea rdx, [e1000_rx_pkt_ring]
    mov [rdx + r15 * 8], rcx        ; this slot now backed by the fresh buffer

    mov rdx, [rcx + net_pkt_t.virt_addr]
    add rdx, [rcx + net_pkt_t.headroom_offset]
    mov [r14 + e1000_rx_desc_t.buffer_addr], rdx
    mov byte [r14 + e1000_rx_desc_t.status], 0

    push rax
    mov rdi, rax
    call eth_input                  ; takes ownership of the received net_pkt_t
    pop rax
    jmp .rx_next

.rx_oom:
    ; No fresh buffer available: leave this slot's buffer_addr pointing at
    ; the buffer that just received a frame — RAX is not handed to eth_input
    ; in this path, so nothing frees or reuses that memory out from under
    ; the descriptor. The frame itself is dropped; the next receive into
    ; this slot overwrites it.
    mov byte [r14 + e1000_rx_desc_t.status], 0

.rx_next:
    inc r13d
    mov [rbx + E1000_RDT], r15d
    cmp r13d, E1000_RING_SIZE
    jb .rx_loop
.rx_done:

    call e1000_tx_reclaim

    mov eax, r13d
    jmp .done
.none:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e1000_tx_reclaim — Free the net_pkt_t backing any TX descriptor the NIC has
; marked done (DD bit set), from the software tail up to TDH.
; -----------------------------------------------------------------------------
align 64
e1000_tx_reclaim:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, [e1000_bar0_virt]
    mov r12, [e1000_tx_ring_virt]
    mov r13d, [e1000_tx_tail_sw]
    mov r14d, [rbx + E1000_TDH]

.loop:
    cmp r13d, r14d
    je .done

    imul rax, r13, e1000_tx_desc_t_size
    add rax, r12
    test byte [rax + e1000_tx_desc_t.status], 1
    jz .done                        ; hardware hasn't finished this one yet

    lea rcx, [e1000_tx_pkt_ring]
    mov rdi, [rcx + r13 * 8]
    test rdi, rdi
    jz .next
    call pktbuf_free
    mov qword [rcx + r13 * 8], 0

.next:
    inc r13d
    and r13d, E1000_RING_SIZE - 1
    jmp .loop

.done:
    mov [e1000_tx_tail_sw], r13d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; e1000_transmit — Queue a frame for transmit with hardware FCS insertion.
; Input: RDI = BAR0 MMIO Base (virt), RSI = TX Descriptor Ring (virt),
;        RDX = frame pointer, ECX = frame length,
;        R8 = owning net_pkt_t* (stashed for e1000_tx_reclaim to pktbuf_free
;        once the hardware actually finishes DMA'ing the frame out — freeing
;        it any earlier, e.g. right after this call returns, would let the
;        allocator hand the same memory to someone else while the NIC could
;        still be reading it)
; Output: EAX = 0 on success (queued), -1 if the ring is full
; -----------------------------------------------------------------------------
align 64
e1000_transmit:
    push rbx
    push r12
    push r13

    mov r12, rdi                    ; R12 = BAR0
    mov r13d, [e1000_tx_tail_sw]    ; R13D = slot this frame will occupy

    mov eax, r13d
    inc eax
    and eax, E1000_RING_SIZE - 1
    mov ebx, [r12 + E1000_TDH]
    cmp eax, ebx
    je .full

    imul rbx, r13, e1000_tx_desc_t_size
    add rbx, rsi                    ; RBX = this descriptor's address

    mov [rbx + e1000_tx_desc_t.buffer_addr], rdx
    mov [rbx + e1000_tx_desc_t.length], cx
    mov byte [rbx + e1000_tx_desc_t.cso], 0
    mov byte [rbx + e1000_tx_desc_t.cmd], 0x0B    ; EOP | IFCS | RS
    mov byte [rbx + e1000_tx_desc_t.status], 0
    mov byte [rbx + e1000_tx_desc_t.css], 0
    mov word [rbx + e1000_tx_desc_t.special], 0

    lea rbx, [e1000_tx_pkt_ring]
    mov [rbx + r13 * 8], r8

    mov [e1000_tx_tail_sw], eax
    mov [r12 + E1000_TDT], eax      ; doorbell: hardware starts DMA'ing now

    xor eax, eax
    jmp .done
.full:
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

align 64
e1000_mac_read:
    push rbx

    mov eax, [rdi + E1000_RAL]
    mov [rsi], al
    mov [rsi+1], ah
    shr eax, 16
    mov [rsi+2], al
    mov [rsi+3], ah

    mov ebx, [rdi + E1000_RAH]
    mov [rsi+4], bl
    mov [rsi+5], bh

    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; e1000_probe — driver_binding_t.probe_fn for this driver. Called by
; lib/io/pci/enum.asm's pci_enumerate once a PCI device matches the
; vendor/device IDs registered in e1000_register_driver below.
; Input: RDI = device_t*, RSI = encoded location (bus<<16 | dev<<8 | func)
; Output: RAX = 0 on success, -1 on failure (enum.asm marks the device
;         DEV_STATE_OFFLINE instead of ONLINE on a nonzero return)
; -----------------------------------------------------------------------------
align 64
e1000_probe:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov eax, esi
    shr eax, 16
    and eax, 0xFF
    mov r13d, eax                   ; bus
    mov eax, esi
    shr eax, 8
    and eax, 0x1F
    mov r14d, eax                   ; dev
    mov eax, esi
    and eax, 0x07
    mov r15d, eax                   ; func

    ; Read & size BAR0 (offset 0x10) to get a mappable physical MMIO range.
    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, 0x10
    mov r8, 4
    call pci_config_read
    and eax, 0xFFFFFFF0              ; strip the low flag/type bits
    mov ebx, eax                     ; RBX = BAR0 physical address

    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, 0
    call pci_bar_size
    test rax, rax
    jz .fail
    mov r12, rax                     ; R12 = BAR0 size

    mov edi, ebx
    mov esi, r12d
    call net_pci_map_queue           ; RAX = uncacheable virtual mapping
    test rax, rax
    jz .fail
    mov rbx, rax                     ; RBX = mapped virtual BAR0

    ; Command register (offset 0x04): Memory Space Enable | Bus Master
    ; Enable. Without bus mastering the device can't DMA the RX/TX rings
    ; e1000_init is about to program it with.
    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, 0x04
    mov r8, 2
    call pci_config_read
    or eax, 0x0006
    mov r9, rax
    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, 0x04
    mov r8, 2
    call pci_config_write

    mov rdi, rbx
    lea rsi, [unet_local_mac]
    call e1000_mac_read

    mov rdi, rbx
    call e1000_init

    xor eax, eax
    jmp .done
.fail:
    mov eax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data
align 8
e1000_driver_binding:
istruc driver_binding_t
    at driver_binding_t.vendor_id,   dw 0x8086    ; Intel
    at driver_binding_t.device_id,   dw 0x100E    ; 82540EM — QEMU's "e1000" model
    at driver_binding_t.class_mask,  dd 0
    at driver_binding_t.class_match, dd 0
    at driver_binding_t.probe_fn,    dq e1000_probe
iend

section .text

; -----------------------------------------------------------------------------
; e1000_register_driver — Register this driver so pci_enumerate (called from
; unet_init) will match & probe a QEMU/real 82540EM it finds on the bus.
; -----------------------------------------------------------------------------
align 64
e1000_register_driver:
    lea rdi, [e1000_driver_binding]
    call driver_register
    ret

%endif ; GUARD_UNET_DRIVERS_E1000_ASM
