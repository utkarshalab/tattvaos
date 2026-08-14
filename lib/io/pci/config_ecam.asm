; =============================================================================
; lib/io/pci/config_ecam.asm
; PCIe Enhanced Configuration Access Mechanism (ECAM) — MMIO config space.
;
; Provides pci_ecam_read and pci_ecam_write for accessing the full 4KB
; configuration space per function (offsets 0x000–0xFFF), required for
; extended PCI capabilities: AER (§13.4.4), ACS (§12.3), MSI-X, SR-IOV.
;
; ECAM address formula:
;   addr = ecam_virt_base + ((bus - start_bus) << 20) | (dev << 15) | (func << 12) | offset
;
; Prerequisites: acpi/mcfg.asm must have parsed the MCFG table and
; mcfg_map_ecam must have mapped the ECAM region into virtual space.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_CONFIG_ECAM_ASM
%define IO_PCI_CONFIG_ECAM_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .text


; =============================================================================
; pci_ecam_addr — Internal helper: compute ECAM MMIO address for a config offset
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = Register offset (0x000–0xFFF, 12-bit)
; Out: RAX = virtual MMIO address, or 0 if ECAM not available
; Clobbers: R8
; =============================================================================
pci_ecam_addr:
    mov     rax, [rel io_ecam_virt]
    test    rax, rax
    jz      .no_ecam                ; ECAM not mapped

    ; addr = base + ((bus - start_bus) << 20) | (dev << 15) | (func << 12) | offset
    movzx   r8, byte [rel io_ecam_start_bus]
    sub     rdi, r8                 ; bus - start_bus
    shl     rdi, 20                 ; << 20

    and     rsi, 0x1F
    shl     rsi, 15                 ; dev << 15
    or      rdi, rsi

    and     rdx, 0x07
    shl     rdx, 12                 ; func << 12
    or      rdi, rdx

    and     rcx, 0xFFF              ; offset mask
    or      rdi, rcx

    add     rax, rdi                ; RAX = final MMIO virtual address
    ret

.no_ecam:
    xor     rax, rax
    ret

; =============================================================================
; pci_ecam_read — Read from PCI extended config space via ECAM MMIO
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = Offset (0x000–0xFFF)
;      R8  = Size in bytes (1, 2, or 4)
; Out: RAX = Value read, or 0xFFFFFFFF on failure
; RSO: RAX owned-out
; =============================================================================
IO_FUNC pci_ecam_read
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8

    mov     rbx, r8                 ; RBX = size (save before addr clobbers R8)
    call    pci_ecam_addr
    test    rax, rax
    jz      .no_ecam

    ; Perform MMIO read based on size
    cmp     rbx, 1
    je      .read8
    cmp     rbx, 2
    je      .read16
    cmp     rbx, 4
    je      .read32

    ; Invalid size
    mov     rax, 0xFFFFFFFF
    jmp     .done

.read8:
    movzx   eax, byte [rax]
    jmp     .done

.read16:
    movzx   eax, word [rax]
    jmp     .done

.read32:
    mov     eax, [rax]
    jmp     .done

.no_ecam:
    mov     rax, 0xFFFFFFFF         ; Return all-ones (standard PCI "not present")

.done:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC pci_ecam_read

; =============================================================================
; pci_ecam_write — Write to PCI extended config space via ECAM MMIO
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = Offset (0x000–0xFFF)
;      R8  = Size in bytes (1, 2, or 4)
;      R9  = Value to write
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC pci_ecam_write
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     rbx, r8                 ; RBX = size
    mov     r8, r9                  ; R8 = value (save; pci_ecam_addr clobbers R8)
    call    pci_ecam_addr
    test    rax, rax
    jz      .no_ecam

    ; Perform MMIO write based on size
    cmp     rbx, 1
    je      .write8
    cmp     rbx, 2
    je      .write16
    cmp     rbx, 4
    je      .write32

    mov     rax, IO_ERR_BADARG
    jmp     .done

.write8:
    mov     [rax], r8b
    xor     rax, rax
    jmp     .done

.write16:
    mov     [rax], r8w
    xor     rax, rax
    jmp     .done

.write32:
    mov     [rax], r8d
    xor     rax, rax
    jmp     .done

.no_ecam:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC pci_ecam_write

%endif ; IO_PCI_CONFIG_ECAM_ASM