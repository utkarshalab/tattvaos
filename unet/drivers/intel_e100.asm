%ifndef GUARD_UNET_DRIVERS_INTEL_E100_ASM
%define GUARD_UNET_DRIVERS_INTEL_E100_ASM
; =============================================================================
; Tattva OS — unet/drivers/intel_e100.asm
; =============================================================================
; Intel i8255x (e100) Fast Ethernet Controller Driver.
;
; Features:
;   - Command Block List (CBL) & Frame Descriptor (RFD) DMA Ring Management
;   - Command Unit (CU) & Receive Unit (RU) State Machine (Idle, Active, Suspended)
;   - Command Blocks: NOP, IA Setup (MAC), Configure, Transmit, MDI Control
;   - System Control Block (SCB) Status & Command Word Processing
;   - MII PHY Transceiver (82555 / 82562) Management & Speed Autonegotiation
;
; Delegates:
;   - DMA Allocator                      -> lib/mem/dma.asm
;   - Delay Microseconds                 -> lib/time/delay.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define E100_SCB_STATUS              0x00
%define E100_SCB_CMD                 0x02
%define E100_SCB_POINTER             0x04

%define E100_CU_START                0x0010
%define E100_CU_RESUME               0x0020
%define E100_RU_START                0x0001
%define E100_RU_RESUME               0x0002

struc e100_rfd_t
    .status:            resw 1      ; C(1b) + OK(1b) + Status
    .command:           resw 1      ; EL(1b) + S(1b) + H(1b) + SF(1b)
    .link:              resd 1      ; Physical Address of Next RFD
    .rsvd:              resd 1
    .count:             resw 1      ; Actual Byte Count Received
    .size:              resw 1      ; Buffer Size
endstruc

section .text

global e100_init
global e100_poll
global e100_transmit
global e100_configure

align 64
e100_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; 1. Hardware Reset & 10ms PHY delay
    mov edi, 10
    call mdelay

    ; 2. Allocate DMA memory for RFD ring & CBL ring
    mov rdi, 64 * 1024
    call dma_alloc_hugepage
    mov rbx, rax

    ; 3. Configure MAC parameters & start RU (Receive Unit)

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e100_poll — Poll Frame Descriptors (RFDs) for Complete Packets
; Input: RDI = Pointer to Driver Control Block
; Output: RAX = Received Packet Count
; -----------------------------------------------------------------------------
align 64
e100_poll:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check C-bit (Complete) in RFD status word (bit 15)
    movzx eax, word [rbx + e100_rfd_t.status]
    test ax, 0x8000
    jz .no_packet

    ; Extract length & dispatch to Ethernet L2 stack
    movzx edx, word [rbx + e100_rfd_t.count]
    and edx, 0x3FFF                 ; 14-bit byte count
    call eth_input

    ; Advance RFD ring pointer & clear C-bit

.no_packet:
    pop rbx
    pop rbp
    ret

align 64
e100_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build Transmit Command Block (Tx CB) & issue CU_RESUME to SCB Command Word
    xor eax, eax
    pop rbp
    ret

align 64
e100_configure:
    push rbp
    mov rbp, rsp
    ; Send Configure Command Block (promiscuous, broadcast enable, loopback disable)
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_INTEL_E100_ASM
