; =============================================================================
; lib/io/pci/caps.asm
; PCI Capability List scanning routine.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_CAPS_ASM
%define IO_PCI_CAPS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

section .text

;extern pci_config_read

; =============================================================================
; pci_find_cap — Search capability chain of a PCI function for target capability
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = Capability ID to look for (e.g. 0x05 for MSI, 0x11 for MSI-X)
; Out: RAX = Offset to capability header in config space, or 0 if not found
; RSO: RAX owned-out
; =============================================================================
IO_FUNC pci_find_cap
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     r9, rcx                 ; R9 = target Cap ID

    ; 1. Check if status register (offset 0x06) indicates capabilities exist (bit 4 = 1)
    push    rdi
    push    rsi
    push    rdx
    mov     rcx, 0x06               ; offset = 0x06
    mov     r8, 2                   ; size = 2 bytes
    call    pci_config_read
    pop     rdx
    pop     rsi
    pop     rdi

    test    ax, 0x0010              ; Capabilities list bit
    jz      .not_found              ; Capabilities list not supported

    ; 2. Read capability list pointer at offset 0x34 (byte)
    push    rdi
    push    rsi
    push    rdx
    mov     rcx, 0x34               ; offset = 0x34
    mov     r8, 1                   ; size = 1 byte
    call    pci_config_read
    pop     rdx
    pop     rsi
    pop     rdi

    and     rax, 0xFF               ; Mask byte
    mov     rbx, rax                ; RBX = current capability pointer

.scan_loop:
    test    rbx, rbx
    jz      .not_found              ; End of list (0x00)

    ; Read Cap ID (byte at current pointer)
    push    rdi
    push    rsi
    push    rdx
    mov     rcx, rbx                ; offset = capability offset
    mov     r8, 1                   ; size = 1 byte
    call    pci_config_read
    pop     rdx
    pop     rsi
    pop     rdi
    and     rax, 0xFF

    cmp     rax, r9                 ; Compare with target Cap ID
    je      .found                  ; Found it!

    ; Read Next pointer (byte at current pointer + 1)
    push    rdi
    push    rsi
    push    rdx
    lea     rcx, [rbx + 1]          ; offset = current pointer + 1
    mov     r8, 1                   ; size = 1 byte
    call    pci_config_read
    pop     rdx
    pop     rsi
    pop     rdi
    and     rax, 0xFF
    mov     rbx, rax                ; Move to next item
    jmp     .scan_loop

.found:
    mov     rax, rbx                ; Return current offset pointer
    jmp     .done

.not_found:
    xor     rax, rax                ; Return 0

.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC pci_find_cap

%endif ; IO_PCI_CAPS_ASM
