; =============================================================================
; lib/io/const/pci.asm
; PCI / PCIe configuration space offsets, classes, and constants.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CONST_PCI_ASM
%define IO_CONST_PCI_ASM

; PCI Configuration Space Registers (offsets)
PCI_REG_VENDOR_ID   equ 0x00        ; Vendor ID (16-bit)
PCI_REG_DEVICE_ID   equ 0x02        ; Device ID (16-bit)
PCI_REG_COMMAND     equ 0x04        ; Command (16-bit)
PCI_REG_STATUS      equ 0x06        ; Status (16-bit)
PCI_REG_REVISION    equ 0x08        ; Revision ID (8-bit)
PCI_REG_PROG_IF     equ 0x09        ; Programming Interface (8-bit)
PCI_REG_SUBCLASS    equ 0x0A        ; Subclass Code (8-bit)
PCI_REG_CLASS       equ 0x0B        ; Class Code (8-bit)
PCI_REG_CACHE_LINE  equ 0x0C        ; Cache Line Size (8-bit)
PCI_REG_LATENCY     equ 0x0D        ; Latency Timer (8-bit)
PCI_REG_HEADER_TYPE equ 0x0E        ; Header Type (8-bit)
PCI_REG_BIST        equ 0x0F        ; Built-in Self Test (8-bit)
PCI_REG_BAR0        equ 0x10        ; Base Address Register 0 (32-bit)
PCI_REG_BAR1        equ 0x14        ; Base Address Register 1 (32-bit)
PCI_REG_BAR2        equ 0x18        ; Base Address Register 2 (32-bit)
PCI_REG_BAR3        equ 0x1C        ; Base Address Register 3 (32-bit)
PCI_REG_BAR4        equ 0x20        ; Base Address Register 4 (32-bit)
PCI_REG_BAR5        equ 0x24        ; Base Address Register 5 (32-bit)
PCI_REG_CAP_PTR     equ 0x34        ; Capabilities Pointer (8-bit)
PCI_REG_INT_LINE    equ 0x3C        ; Interrupt Line (8-bit)
PCI_REG_INT_PIN     equ 0x3D        ; Interrupt Pin (8-bit)

; PCI Command Register Flags
PCI_CMD_IO_SPACE    equ 0x0001      ; Enable response in I/O space
PCI_CMD_MEM_SPACE   equ 0x0002      ; Enable response in Memory space
PCI_CMD_BUS_MASTER  equ 0x0004      ; Enable bus mastering

; PCI Header Types
PCI_HEADER_TYPE_DEV equ 0x00        ; Standard PCI device header
PCI_HEADER_TYPE_BRG equ 0x01        ; PCI-to-PCI bridge header
PCI_HEADER_TYPE_MF  equ 0x80        ; Multi-function flag bit in Header Type

; PCI Capabilities IDs
PCI_CAP_ID_PM       equ 0x01        ; Power Management
PCI_CAP_ID_AGP      equ 0x02        ; Accelerated Graphics Port
PCI_CAP_ID_VPD      equ 0x03        ; Vital Product Data
PCI_CAP_ID_SLOT_ID  equ 0x04        ; Slot Identification
PCI_CAP_ID_MSI      equ 0x05        ; Message Signaled Interrupts
PCI_CAP_ID_CHSWP    equ 0x06        ; CompactPCI Hot Swap
PCI_CAP_ID_PCIX     equ 0x07        ; PCI-X
PCI_CAP_ID_HT       equ 0x08        ; HyperTransport
PCI_CAP_ID_VNDR     equ 0x09        ; Vendor Specific
PCI_CAP_ID_DBG      equ 0x0A        ; Debug port
PCI_CAP_ID_CCRC     equ 0x0B        ; CompactPCI Central Resource Control
PCI_CAP_ID_SHPC     equ 0x0C        ; PCI Standard Hot-Plug Controller
PCI_CAP_ID_SSVID    equ 0x0D        ; Bridge subsystem vendor/device ID
PCI_CAP_ID_AGP3     equ 0x0E        ; AGP 8x
PCI_CAP_ID_SECDEV   equ 0x0F        ; Secure Device
PCI_CAP_ID_PCIE     equ 0x10        ; PCI Express Capability
PCI_CAP_ID_MSIX     equ 0x11        ; MSI-X Capability

%endif ; IO_CONST_PCI_ASM
