; =============================================================================
; lib/io/pci/config.asm
; PCI Configuration Space Read/Write routines using legacy I/O ports.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_CONFIG_ASM
%define IO_PCI_CONFIG_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

; Legacy PCI Ports
PCI_CONFIG_ADDR     equ 0xCF8
PCI_CONFIG_DATA     equ 0xCFC

section .text

;extern port_in8
;extern port_out8

; These low-level port helpers are defined in portio.asm but we can use direct in/out or call port_in/out
; To make it faster and self-contained, we can write in/out directly or call them. Let's call our port routines.
;extern port_in8
;extern port_out8

; =============================================================================
; pci_config_read — Read from PCI configuration space
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = Offset (8-bit)
;      R8  = Size in bytes (1, 2, or 4)
; Out: RAX = Value read (or 0xFFFFFFFF on bad size)
; RSO: RAX owned-out
; =============================================================================
IO_FUNC pci_config_read
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8

    ; 1. Construct the 32-bit address to write to 0xCF8:
    ; bit 31: Enable bit (1)
    ; bits 30-24: Reserved (0)
    ; bits 23-16: Bus number
    ; bits 15-11: Device number
    ; bits 10-8: Function number
    ; bits 7-2: Register offset (double-word aligned)
    ; bits 1-0: 0
    mov     rax, 1
    shl     rax, 31                 ; Set Enable bit

    and     rdi, 0xFF
    shl     rdi, 16
    or      rax, rdi                ; Set Bus

    and     rsi, 0x1F
    shl     rsi, 11
    or      rax, rsi                ; Set Device

    and     rdx, 0x07
    shl     rdx, 8
    or      rax, rdx                ; Set Function

    mov     rbx, rcx
    and     rbx, 0xFC               ; Align offset to 4-byte boundary
    or      rax, rbx                ; Set Offset

    ; 2. Write address to PCI_CONFIG_ADDR (0xCF8)
    push    rax
    mov     rdi, PCI_CONFIG_ADDR
    mov     rsi, rax
    ; We write 32 bits. Let's do a direct out to 0xCF8.
    ; Out port 0xCF8, EAX
    mov     rdx, PCI_CONFIG_ADDR
    out     dx, eax
    pop     rax

    ; 3. Read data from PCI_CONFIG_DATA (0xCFC) + offset remainder
    mov     rax, rcx
    and     rax, 3                  ; RAX = offset remainder (0, 1, 2, or 3)
    mov     rdx, PCI_CONFIG_DATA
    add     rdx, rax                ; DX = targeted port address

    ; Perform read based on size
    cmp     r8, 1
    je      .read8
    cmp     r8, 2
    je      .read16
    cmp     r8, 4
    je      .read32

    ; Invalid size
    mov     rax, 0xFFFFFFFF
    jmp     .done

.read8:
    xor     rax, rax
    in      al, dx                  ; Read 8-bit byte
    jmp     .done

.read16:
    xor     rax, rax
    in      ax, dx                  ; Read 16-bit word
    jmp     .done

.read32:
    in      eax, dx                 ; Read 32-bit double-word

.done:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC pci_config_read

; =============================================================================
; pci_config_write — Write to PCI configuration space
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = Offset (8-bit)
;      R8  = Size in bytes (1, 2, or 4)
;      R9  = Value to write (32-bit)
; Out: None
; =============================================================================
IO_FUNC pci_config_write
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8

    ; 1. Construct Address
    mov     rax, 1
    shl     rax, 31
 
    and     rdi, 0xFF
    shl     rdi, 16
    or      rax, rdi

    and     rsi, 0x1F
    shl     rsi, 11
    or      rax, rsi

    and     rdx, 0x07
    shl     rdx, 8
    or      rax, rdx

    mov     rbx, rcx
    and     rbx, 0xFC
    or      rax, rbx

    ; 2. Write address
    mov     rdx, PCI_CONFIG_ADDR
    out     dx, eax

    ; 3. Write data to PCI_CONFIG_DATA + offset remainder
    mov     rax, rcx
    and     rax, 3
    mov     rdx, PCI_CONFIG_DATA
    add     rdx, rax

    ; Perform write
    mov     rax, r9                 ; Value to write
    cmp     r8, 1
    je      .write8
    cmp     r8, 2
    je      .write16
    cmp     r8, 4
    je      .write32
    jmp     .done

.write8:
    out     dx, al
    jmp     .done

.write16:
    out     dx, ax
    jmp     .done

.write32:
    out     dx, eax

.done:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
IO_ENDFUNC pci_config_write

%endif ; IO_PCI_CONFIG_ASM
