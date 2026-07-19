; =============================================================================
; lib/io/pci/acs.asm
; PCIe Access Control Services (ACS) security path validator.
;
; Scans downstream PCIe switch configuration capabilities to verify that
; Access Control Services (ACS) are present and enabled. This enforces isolation
; and prevents hardware-level DMA spoofing during peer-to-peer (P2P) transfers.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_ACS_ASM
%define IO_PCI_ACS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .text

extern pci_ecam_read

; =============================================================================
; pci_scan_acs — Scan extended capabilities of a device to verify ACS status
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
; Out: RAX = 1 if ACS is enabled (safe for P2P), 0 if disabled/unsafe
; =============================================================================
IO_FUNC pci_scan_acs
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; R12 = Bus
    mov     r13, rsi                ; R13 = Device
    mov     r14, rdx                ; R14 = Function

    ; PCIe Extended Capabilities list begins at offset 0x100
    mov     r9, 0x100               ; R9 = current register offset

.loop:
    test    r9, r9
    jz      .not_found              ; End of list (offset 0)
    cmp     r9, 0xFFF
    jae     .not_found              ; Exceeds extended config limit

    ; Read the 32-bit Extended Capability Header via ECAM MMIO
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, r9                 ; Register offset
    mov     r8, 4                   ; Size (4 bytes)
    call    pci_ecam_read
    cmp     eax, 0xFFFFFFFF
    je      .not_found              ; Device not present or unmapped

    movzx   ecx, ax                 ; ECX = Capability ID (lower 16 bits)
    cmp     cx, 0x000D              ; Extended Cap ID 0x000D is Access Control Services (ACS)
    je      .found_acs

    ; Move to next capability offset: header bits [31:20]
    shr     rax, 20
    and     rax, 0xFFF              ; Mask to 12 bits
    mov     r9, rax
    jmp     .loop

.found_acs:
    ; Read the ACS Control Register at offset +6 from capability base (2 bytes)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [r9 + 6]           ; Register offset = base + 6
    mov     r8, 2                   ; Size = 2 bytes
    call    pci_ecam_read

    ; Verify that Source Validation (bit 0), Translation Blocking (bit 1),
    ; and P2P Request Redirect (bit 2) are enabled (mask 0x07)
    and     rax, 0x07
    cmp     rax, 0x07
    jne     .disabled               ; Not all safety properties are active

    mov     rax, 1                  ; ACS enabled & validated
    jmp     .done

.not_found:
.disabled:
    xor     rax, rax                ; Return 0 (Unsafe / disabled)

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC pci_scan_acs

%endif ; IO_PCI_ACS_ASM
