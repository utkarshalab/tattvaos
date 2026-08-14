; =============================================================================
; lib/io/pci/msix.asm
; PCI Express Message Signaled Interrupts Extended (MSI-X) configuration.
;
; Implements MSI-X capability structure scans and table entry programming.
; Enforces core-specific vector steering to LAPIC message addresses.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_MSIX_ASM
%define IO_PCI_MSIX_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

global pci_find_capability
global pci_configure_msix




; =============================================================================
; pci_find_capability — Find standard capability offset in PCI config space
; In : RDI = Bus
;      RSI = Device
;      RDX = Function
;      RCX = Capability ID to find (e.g. 0x11 for MSI-X, 0x10 for PCIe)
; Out: RAX = Offset (0x40-0xFF) or 0 if not found
; =============================================================================
IO_FUNC pci_find_capability
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; r12 = Bus
    mov     r13, rsi                ; r13 = Device
    mov     r14, rdx                ; r14 = Function
    mov     r15, rcx                ; r15 = Cap ID

    ; Check if Status register indicates capabilities list support (bit 4 of Status)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, 0x06               ; Status register (offset 0x06)
    mov     r8, 2
    call    pci_config_read
    test    ax, 0x0010              ; Capabilities list bit
    jz      .not_found

    ; Start reading from Capabilities Pointer register (offset 0x34)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, 0x34               ; Capabilities Pointer
    mov     r8, 1
    call    pci_config_read
    movzx   r9, al                  ; R9 = current capability offset (starts at offset)

.loop:
    test    r9, r9
    jz      .not_found
    and     r9, 0xFC                ; Align to dword boundary

    ; Read Cap ID (byte 0) and Next pointer (byte 1)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, r9
    mov     r8, 2
    call    pci_config_read         ; AL = Cap ID, AH = Next pointer

    movzx   ecx, al
    cmp     rcx, r15
    je      .found

    movzx   r9, ah                  ; Move to next capability pointer
    jmp     .loop

.found:
    mov     rax, r9
    jmp     .done

.not_found:
    xor     rax, rax

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_find_capability

; =============================================================================
; pci_configure_msix — Locate and program MSI-X vector redirect table
; In : RDI = Bus
;      RSI = Device
;      RDX = Function
;      RCX = Vector allocation index (0-255)
;      R8  = Target APIC ID (core target)
;      R9  = Slot index in MSI-X Table (typically 0 for single queue)
; Out: RAX = 0 on success, or negative error code (IO_ERR_NO_DEVICE/IO_ERR_PCI_BAR)
; =============================================================================
IO_FUNC pci_configure_msix
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; r12 = Bus
    mov     r13, rsi                ; r13 = Device
    mov     r14, rdx                ; r14 = Function
    mov     r15, rcx                ; r15 = Vector

    ; 1. Find MSI-X Capability (ID = 0x11)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, 0x11               ; MSI-X Capability ID
    call    pci_find_capability
    test    rax, rax
    jz      .err_no_msix
    mov     rbx, rax                ; RBX = cap offset

    ; 2. Read BIR and Table Offset (offset 4 inside capability structure)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 4]
    mov     r8, 4
    call    pci_config_read         ; EAX = BIR (lower 3 bits) & Table Offset (upper 29 bits)

    movzx   r10, al                 ; R10 = BIR low byte
    and     r10, 0x07               ; R10 = BAR index (0-5)
    and     eax, 0xFFFFFFF8         ; EAX = Table offset relative to BAR

    ; 3. Fetch BAR Physical Address
    push    rax                     ; Save table offset value
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [0x10 + r10 * 4]   ; Offset to selected BAR register
    mov     r8, 4
    call    pci_config_read         ; EAX = BAR physical base address
    pop     r11                     ; R11 = table offset

    test    eax, eax
    jz      .err_bad_bar            ; BAR is unmapped

    and     eax, 0xFFFFFFF0         ; Clear flags to retrieve raw physical base address
    add     rax, r11                ; RAX = physical address of MSI-X Table base

    ; 4. Locate target slot in Table Base (16 bytes per slot)
    ;    Slot size = 16 bytes. Offset = slot * 16
    imul    r9, 16                  ; R9 = slot offset
    add     rax, r9                 ; RAX = -> entry address

    ; Program Message Address (bytes 0-7): 0xFEE00000 | (target_apic_id << 12)
    mov     rsi, [rsp + 16]         ; Retrieve R8 (target APIC ID) from stack frame (pushed r8 is at rsp+16)
    shl     rsi, 12
    or      rsi, 0xFEE00000         ; MSI-X Address format
    mov     [rax], rsi              ; Write low address

    ; Program Message Data (bytes 8-11): Vector
    mov     [rax + 8], r15d         ; Write vector

    ; Program Vector Control (bytes 12-15): Unmask (0)
    mov     dword [rax + 12], 0     ; Clear mask bit to enable

    ; 5. Enable MSI-X in Message Control register (bit 15 of word offset 2)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 2]
    mov     r8, 2
    call    pci_config_read         ; AX = Control register
    or      ax, 0x8000              ; Set Bit 15 (MSI-X Enable)
    mov     rsi, rax

    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 2]
    mov     r8, 2
    call    pci_config_write

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bad_bar:
    mov     rax, IO_ERR_PCI_BAR
    jmp     .done

.err_no_msix:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_configure_msix

%endif ; IO_PCI_MSIX_ASM
