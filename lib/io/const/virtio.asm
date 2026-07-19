; =============================================================================
; lib/io/const/virtio.asm
; Virtio-spec constants, register offsets, status, and virtqueue flags.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CONST_VIRTIO_ASM
%define IO_CONST_VIRTIO_ASM

; Virtio Legacy PCI Register Offsets (relative to BAR0 base)
VIRTIO_PCI_HOST_FEATURES    equ 0x00    ; Host features register (32-bit, Read-only)
VIRTIO_PCI_GUEST_FEATURES   equ 0x04    ; Guest features register (32-bit, Write-only)
VIRTIO_PCI_QUEUE_PFN        equ 0x08    ; Queue Physical Frame Number (32-bit, Read/Write)
VIRTIO_PCI_QUEUE_NUM        equ 0x0C    ; Queue Size (16-bit, Read-only)
VIRTIO_PCI_QUEUE_SEL        equ 0x0E    ; Queue Select (16-bit, Write-only)
VIRTIO_PCI_QUEUE_NOTIFY     equ 0x10    ; Queue Notify (16-bit, Write-only)
VIRTIO_PCI_STATUS           equ 0x12    ; Device Status (8-bit, Read/Write)
VIRTIO_PCI_ISR              equ 0x13    ; Interrupt Status (8-bit, Read-only)

; Virtio Device Status Register Flags
VIRTIO_STATUS_ACKNOWLEDGE   equ 0x01    ; Guest recognizes the device
VIRTIO_STATUS_DRIVER        equ 0x02    ; Guest knows how to drive the device
VIRTIO_STATUS_DRIVER_OK     equ 0x04    ; Guest driver is ready and operational
VIRTIO_STATUS_FEATURES_OK   equ 0x08    ; Guest has completed feature negotiation
VIRTIO_STATUS_FAILED        equ 0x80    ; Guest gave up on the device

; Virtqueue Descriptor (vring_desc) Flag Bits
VRING_DESC_F_NEXT           equ 1       ; Descriptor chain continues in next field
VRING_DESC_F_WRITE          equ 2       ; Buffer is write-only by device (else read-only)
VRING_DESC_F_INDIRECT       equ 4       ; Buffer points to an indirect table of descriptors

; Virtio Block Device Opcodes (Request Type)
VIRTIO_BLK_T_IN             equ 0       ; Block read request
VIRTIO_BLK_T_OUT            equ 1       ; Block write request
VIRTIO_BLK_T_FLUSH          equ 4       ; Block flush cache request

%endif ; IO_CONST_VIRTIO_ASM
