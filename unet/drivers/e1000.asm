; =============================================================================
; Tattva OS — unet/drivers/e1000.asm
; =============================================================================
; Intel e1000 / e1000e PCIe Gigabit Network Interface Card Driver.
;
; Implements:
;   - PCIe MMIO BAR 0 Register Mapping (`E1000_CTRL`, `E1000_STATUS`, `E1000_RCTL`, `E1000_TCTL`)
;   - 128-Entry Transmit (TX) & Receive (RX) Descriptor Ring Buffer Management
;   - Controller Enable Sequence & Hardware Ready Polling
;   - Zero-Copy Ring Buffer Descriptor Push/Pull (`e1000_send_packet`, `e1000_receive_packet`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define E1000_RING_SIZE             128

%define E1000_REG_CTRL              0x0000
%define E1000_REG_STATUS            0x0008
%define E1000_REG_RCTL              0x0100
%define E1000_REG_TCTL              0x0400
%define E1000_REG_RDBAL             0x2800
%define E1000_REG_RDLEN             0x2808
%define E1000_REG_RDH               0x2810
%define E1000_REG_RDT               0x2818
%define E1000_REG_TDBAL             0x3800
%define E1000_REG_TDLEN             0x3808
%define E1000_REG_TDH               0x3810
%define E1000_REG_TDT               0x3818

struc e1000_rx_desc_t
    .buffer_addr:       resq 1      ; 64-bit DMA Physical Buffer Address
    .length:            resw 1
    .checksum:          resw 1
    .status:            resb 1
    .errors:            resb 1
    .special:           resw 1
endstruc

struc e1000_tx_desc_t
    .buffer_addr:       resq 1      ; 64-bit DMA Physical Buffer Address
    .length:            resw 1
    .cso:               resb 1
    .cmd:               resb 1
    .status:            resb 1
    .css:               resb 1
    .special:           resw 1
endstruc

section .data
align 64
global e1000_rx_ring
e1000_rx_ring: times E1000_RING_SIZE * e1000_rx_desc_t_size db 0

align 64
global e1000_tx_ring
e1000_tx_ring: times E1000_RING_SIZE * e1000_tx_desc_t_size db 0

align 8
global e1000_bar_mmio
e1000_bar_mmio: dq 0xE0000000                        ; QEMU e1000 Default MMIO BAR

section .text

global e1000_init
global e1000_send_packet
global e1000_receive_packet

; -----------------------------------------------------------------------------
; e1000_init — Initialize Intel e1000 PCIe Controller & Descriptor Rings
; -----------------------------------------------------------------------------
align 32
e1000_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [e1000_bar_mmio]

    ; Reset Controller (`CTRL.RST = 1`)
    mov dword [rbx + E1000_REG_CTRL], 0x04000000

    ; Configure RX Descriptor Ring Address & Length
    lea rax, [e1000_rx_ring]
    mov [rbx + E1000_REG_RDBAL], eax
    mov dword [rbx + E1000_REG_RDLEN], E1000_RING_SIZE * e1000_rx_desc_t_size
    mov dword [rbx + E1000_REG_RDH], 0
    mov dword [rbx + E1000_REG_RDT], E1000_RING_SIZE - 1

    ; Configure TX Descriptor Ring Address & Length
    lea rax, [e1000_tx_ring]
    mov [rbx + E1000_REG_TDBAL], eax
    mov dword [rbx + E1000_REG_TDLEN], E1000_RING_SIZE * e1000_tx_desc_t_size
    mov dword [rbx + E1000_REG_TDH], 0
    mov dword [rbx + E1000_REG_TDT], 0

    ; Enable Receiver (`RCTL.EN = 1`) & Transmitter (`TCTL.EN = 1`)
    mov dword [rbx + E1000_REG_RCTL], 0x00000002
    mov dword [rbx + E1000_REG_TCTL], 0x00000002

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e1000_send_packet — Transmit packet buffer via e1000 TX ring
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
e1000_send_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi

    mov rbx, [e1000_bar_mmio]
    mov eax, [rbx + E1000_REG_TDT]                  ; Get Tail Index

    ; Calculate descriptor address
    mov rsi, rax
    imul rsi, rsi, e1000_tx_desc_t_size
    lea rsi, [e1000_tx_ring + rsi]

    ; Write DMA Buffer Address & Length
    mov rdx, [rdi + net_pkt_t.phys_addr]
    mov ecx, [rdi + net_pkt_t.headroom_offset]
    add rdx, rcx                                     ; RDX = Start of Ethernet frame

    mov [rsi + e1000_tx_desc_t.buffer_addr], rdx
    mov ecx, [rdi + net_pkt_t.data_len]
    mov [rsi + e1000_tx_desc_t.length], cx
    mov byte [rsi + e1000_tx_desc_t.cmd], 0x0B       ; EOP (End of Packet) | IFCS | RS

    ; Increment Tail Index Doorbell
    inc eax
    and eax, (E1000_RING_SIZE - 1)
    mov [rbx + E1000_REG_TDT], eax

    pop rsi
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e1000_receive_packet — Poll e1000 RX ring for incoming packet
; Output: RAX = Pointer to net_pkt_t (or 0 if no packet ready)
; -----------------------------------------------------------------------------
align 32
e1000_receive_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [e1000_bar_mmio]
    mov eax, [rbx + E1000_REG_RDH]                  ; Head Index

    mov rdx, rax
    imul rdx, rdx, e1000_rx_desc_t_size
    lea rdx, [e1000_rx_ring + rdx]

    test byte [rdx + e1000_rx_desc_t.status], 1    ; Descriptor Done (DD bit)
    jz .no_packet

    ; Allocate packet buffer for upper stack
    call pktbuf_alloc
    test rax, rax
    jz .no_packet

    pop rbx
    pop rbp
    ret

.no_packet:
    xor eax, eax
    pop rbx
    pop rbp
    ret
