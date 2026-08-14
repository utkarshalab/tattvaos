; =============================================================================
; lib/io/pci/ext_tag.asm
; PCIe Extended Tag Field configuration controller.
;
; Enables 8-bit transaction tags (expanding from 5-bit) inside PCIe devices
; to allow up to 256 concurrent outstanding transactions without bus queue stalls.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_EXT_TAG_ASM
%define IO_PCI_EXT_TAG_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

global pci_enable_extended_tags



; =============================================================================
; pci_enable_extended_tags — Enable 8-bit transaction tags inside PCIe Device Control
; In : RDI = Bus
;      RSI = Device
;      RDX = Function
; Out: RAX = 0 on success, or negative error code (IO_ERR_NO_DEVICE)
; =============================================================================
IO_FUNC pci_enable_extended_tags
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; r12 = Bus
    mov     r13, rsi                ; r13 = Device
    mov     r14, rdx                ; r14 = Function

    ; 1. Locate PCIe Capability structure (ID = 0x10)
    mov     rcx, 0x10               ; PCIe Capability ID
    call    pci_find_capability
    test    rax, rax
    jz      .err_no_pcie
    mov     rbx, rax                ; RBX = PCIe capability base offset

    ; 2. Read Device Control Register (offset +8 inside capability block)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 8]
    mov     r8, 2                   ; Read 2 bytes
    call    pci_config_read         ; AX = Device Control

    ; 3. Set bit 8 (Extended Tag Field Enable)
    or      ax, 0x0100              ; Enable Extended Tags (bit 8)
    mov     rsi, rax

    ; Write updated Device Control back to the configuration space
    mov     rdi, r12
    mov     rsi, rax                ; (RSI is already loaded)
    mov     rdx, r14
    lea     rcx, [rbx + 8]
    mov     r8, 2
    call    pci_config_write

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_no_pcie:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_enable_extended_tags

%endif ; IO_PCI_EXT_TAG_ASM
