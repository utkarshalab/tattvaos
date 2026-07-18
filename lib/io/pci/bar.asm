; =============================================================================
; lib/io/pci/bar.asm
; PCI Base Address Register (BAR) sizing and mapping helpers.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_BAR_ASM
%define IO_PCI_BAR_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .text

extern pci_config_read
extern pci_config_write

; =============================================================================
; pci_bar_size — Size a PCI Base Address Register (BAR)
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = BAR Index (0-5)
; Out: RAX = Size in bytes, or negative error code on failure
; RSO: RAX owned-out
; =============================================================================
IO_FUNC pci_bar_size
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     rbx, rcx                ; RBX = BAR index (0-5)

    ; Validate BAR index
    cmp     rbx, 5
    ja      .err_bad_idx

    ; Calculate register offset: 0x10 + BAR_index * 4
    mov     rcx, rbx
    shl     rcx, 2                  ; index * 4
    add     rcx, 0x10               ; RCX = register offset

    ; 1. Save original BAR value
    mov     r8, 4                   ; size = 4 bytes
    call    pci_config_read
    mov     r9, rax                 ; R9 = original BAR value

    ; 2. Write all 1s (0xFFFFFFFF) to configure sizing mode
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     r8, 4                   ; size = 4
    mov     r9, 0xFFFFFFFF          ; value = all 1s
    call    pci_config_write
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi

    ; 3. Read back sized mask
    mov     r8, 4
    call    pci_config_read
    mov     rbx, rax                ; RBX = sized mask

    ; 4. Restore original BAR value
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     r8, 4
    mov     r9, r9                  ; original BAR value
    call    pci_config_write
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi

    ; 5. Calculate size from mask
    ; Check if BAR is Memory Space (bit 0 == 0) or I/O Space (bit 0 == 1)
    test    bl, 0x01
    jnz     .io_space

    ; Memory BAR: mask bits [31:4]
    and     ebx, 0xFFFFFFF0
    test    ebx, ebx
    jz      .zero_size
    not     ebx
    inc     ebx                     ; size = ~(mask) + 1
    mov     rax, rbx
    jmp     .done

.io_space:
    ; I/O BAR: mask bits [31:2]
    and     ebx, 0xFFFFFFFC
    test    ebx, ebx
    jz      .zero_size
    not     ebx
    inc     ebx
    mov     rax, rbx
    jmp     .done

.zero_size:
    xor     rax, rax
    jmp     .done

.err_bad_idx:
    mov     rax, IO_ERR_BADARG
    jmp     .done

.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_bar_size

; =============================================================================
; pci_bar_map — Program a physical address mapping into a PCI BAR
; In : RDI = Bus (8-bit)
;      RSI = Device (5-bit)
;      RDX = Function (3-bit)
;      RCX = BAR Index (0-5)
;      R8  = Physical address to map (32-bit or low 32-bit of 64-bit BAR)
; Out: RAX = 0 on success, or negative error code on failure
; =============================================================================
IO_FUNC pci_bar_map
    push    rcx
    push    r8

    ; Validate index
    cmp     rcx, 5
    ja      .err_bad_idx

    ; Calculate register offset
    shl     rcx, 2
    add     rcx, 0x10               ; RCX = offset

    ; Write physical base address to configuration offset
    mov     r9, r8                  ; R9 = value to write
    mov     r8, 4                   ; size = 4 bytes
    call    pci_config_write

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bad_idx:
    mov     rax, IO_ERR_BADARG

.done:
    pop     r8
    pop     rcx
    ret
IO_ENDFUNC pci_bar_map

%endif ; IO_PCI_BAR_ASM
