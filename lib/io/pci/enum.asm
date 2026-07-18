; =============================================================================
; lib/io/pci/enum.asm
; PCI device enumeration scan loop.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_ENUM_ASM
%define IO_PCI_ENUM_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .bss
global global_device_table
global_device_table: resb device_t_size * 16 ; Supports up to 16 active devices
global_device_count: resq 1

section .text

extern pci_config_read
extern pci_match_driver
extern console_milestone

; =============================================================================
; pci_enumerate — Walks PCI buses to detect and probe compatible devices
; In : None
; Out: RAX = Number of successfully matched and probed devices
; RSO: RAX owned-out
; =============================================================================
IO_FUNC pci_enumerate
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    xor     r12, r12                ; R12 = bus iterator (0-7 for early bring-up)
    xor     r13, r13                ; R13 = device iterator (0-31)
    xor     r14, r14                ; R14 = function iterator (0-7)
    xor     r15, r15                ; R15 = count of matched devices

.bus_loop:
    xor     r13, r13
.dev_loop:
    xor     r14, r14
.func_loop:
    ; Read vendor_id at offset 0x00 (word)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, 0x00
    mov     r8, 2
    call    pci_config_read
    and     rax, 0xFFFF
    cmp     rax, 0xFFFF             ; Device not present
    je      .next_func

    mov     rbx, rax                ; RBX = Vendor ID

    ; Read device_id at offset 0x02 (word)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, 0x02
    mov     r8, 2
    call    pci_config_read
    and     rax, 0xFFFF
    mov     rsi, rax                ; RSI = Device ID (for match call)
    mov     rdi, rbx                ; RDI = Vendor ID

    ; Read class code at offset 0x09 (3 bytes: class, subclass, prog_if)
    push    rdi
    push    rsi
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, 0x09
    mov     r8, 3
    call    pci_config_read
    and     rax, 0xFFFFFF           ; RAX = class code
    mov     rdx, rax                ; RDX = class code (for match call)
    pop     rsi
    pop     rdi

    ; Search driver table for a compatible match
    call    pci_match_driver
    test    rax, rax
    jz      .next_func              ; No matching driver registered

    ; Found driver! Allocate device slot from global_device_table
    mov     r9, [rel global_device_count]
    cmp     r9, 16                  ; Limit to table size
    jae     .next_func

    ; Calculate slot pointer: global_device_table + count * device_t_size
    lea     rbx, [rel global_device_table]
    imul    r9, device_t_size
    add     rbx, r9                 ; RBX = device_t *

    ; Populate basic fields
    mov     qword [rbx + device_t.state], DEV_STATE_PROBE

    ; Call probe function: probe_fn(device_t *dev, pci_dev_t (bus<<16|dev<<8|func))
    ; Setup args
    mov     rdi, rbx                ; RDI = dev
    mov     rsi, r12
    shl     rsi, 16
    mov     rcx, r13
    shl     rcx, 8
    or      rsi, rcx
    or      rsi, r14                ; RSI = encoded pci location

    ; Extract probe function address
    mov     rcx, [rax + driver_binding_t.probe_fn]
    push    rax
    call    rcx                     ; Call probe
    pop     rcx

    test    rax, rax
    jnz     .probe_failed           ; Non-zero return indicates probe failure

    ; Device is active
    mov     qword [rbx + device_t.state], DEV_STATE_ONLINE
    inc     qword [rel global_device_count]
    inc     r15                     ; Increment count of matched/active devices
    jmp     .next_func

.probe_failed:
    mov     qword [rbx + device_t.state], DEV_STATE_OFFLINE

.next_func:
    inc     r14
    cmp     r14, 8
    jl      .func_loop

    inc     r13
    cmp     r13, 32
    jl      .dev_loop

    inc     r12
    cmp     r12, 8                  ; Scan first 8 buses
    jl      .bus_loop

    mov     rax, r15                ; Return matched count

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
IO_ENDFUNC pci_enumerate

%endif ; IO_PCI_ENUM_ASM
