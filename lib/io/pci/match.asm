; =============================================================================
; lib/io/pci/match.asm
; Driver registration and PCI device matching driver.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_MATCH_ASM
%define IO_PCI_MATCH_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .bss
global global_driver_table
global_driver_table: resb driver_binding_t_size * 16 ; Supports up to 16 drivers

section .text

; =============================================================================
; driver_register — Register a driver binding descriptor in the global table
; In : RDI = -> driver_binding_t descriptor
; Out: RAX = 0 on success, or a negative error band code (IO_ERR_NOMEM)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC driver_register
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rsi, rdi                ; RSI = source driver binding pointer
    lea     rdi, [rel global_driver_table] ; RDI = destination base
    xor     rcx, rcx                ; RCX = index iterator

.loop:
    mov     rax, rcx
    imul    rax, driver_binding_t_size
    lea     rdx, [rdi + rax]        ; RDX = current slot pointer

    ; A slot is empty if probe_fn is NULL
    mov     rax, [rdx + driver_binding_t.probe_fn]
    test    rax, rax
    jz      .found_empty            ; Found a free slot

    inc     rcx
    cmp     rcx, 16
    jl      .loop

    ; Table is full
    mov     rax, IO_ERR_NOMEM
    jmp     .done

.found_empty:
    ; Copy driver_binding_t (20 bytes: 2 words + 2 dwords + 1 qword)
    mov     ax, [rsi + driver_binding_t.vendor_id]
    mov     [rdx + driver_binding_t.vendor_id], ax

    mov     ax, [rsi + driver_binding_t.device_id]
    mov     [rdx + driver_binding_t.device_id], ax

    mov     eax, [rsi + driver_binding_t.class_mask]
    mov     [rdx + driver_binding_t.class_mask], eax

    mov     eax, [rsi + driver_binding_t.class_match]
    mov     [rdx + driver_binding_t.class_match], eax

    mov     rax, [rsi + driver_binding_t.probe_fn]
    mov     [rdx + driver_binding_t.probe_fn], rax

    xor     rax, rax                ; Return 0 (Success)

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC driver_register

; =============================================================================
; pci_match_driver — Search driver table for a vendor/device/class match
; In : RDI = vendor_id (16-bit)
;      RSI = device_id (16-bit)
;      RDX = class_code (24-bit)
; Out: RAX = -> driver_binding_t, or 0 if no match found
; RSO: RAX owned-out
; =============================================================================
IO_FUNC pci_match_driver
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    lea     rbx, [rel global_driver_table]
    xor     rcx, rcx                ; Iterator index

.loop:
    mov     rax, rcx
    imul    rax, driver_binding_t_size
    lea     rax, [rbx + rax]        ; RAX = current driver_binding_t pointer

    ; If probe_fn is NULL, we've reached the end of registered entries
    mov     r8, [rax + driver_binding_t.probe_fn]
    test    r8, r8
    jz      .no_match

    ; 1. Match by Vendor/Device ID if they are not wildcard (0xFFFF)
    movzx   r8, word [rax + driver_binding_t.vendor_id]
    cmp     r8, 0xFFFF
    je      .match_class            ; Wildcard vendor, try class matching

    cmp     r8, rdi                 ; Compare vendor_id
    jne     .next

    movzx   r8, word [rax + driver_binding_t.device_id]
    cmp     r8, rsi                 ; Compare device_id
    je      .match_found            ; Match by exact IDs!

    jmp     .next

.match_class:
    ; 2. Match by Class Code
    mov     r8d, [rax + driver_binding_t.class_match]
    mov     r9d, [rax + driver_binding_t.class_mask]
    and     r9d, edx                ; Apply mask to device's class code
    cmp     r8d, r9d
    je      .match_found            ; Match by class code mask!

.next:
    inc     rcx
    cmp     rcx, 16
    jl      .loop

.no_match:
    xor     rax, rax                ; Return NULL
    jmp     .done

.match_found:
    ; RAX currently points to the matched driver_binding_t entry
    jmp     .done

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_match_driver

%endif ; IO_PCI_MATCH_ASM
