; =============================================================================
; lib/usb/tests/ukstub.asm — the kernel side of lib/usb/kernel.asm, for tests
; =============================================================================
; kstub.asm gives the console, page allocation and delays; this adds PCI
; configuration space and the mapping calls, each through a hook the test
; points at Python, then includes the USB stack and its kernel glue.
; =============================================================================

%include "lib/io/acpi/aml/tests/kstub.asm"

section .bss
alignb 8
global ukstub_cfg_read_fn
ukstub_cfg_read_fn:     resq 1      ; EDI = BDF, ESI = offset → EAX
global ukstub_cfg_write_fn
ukstub_cfg_write_fn:    resq 1      ; EDI = BDF, ESI = offset, EDX = value
global ukstub_range_fn
ukstub_range_fn:        resq 1      ; RDI = size → RAX = virtual range
global ukstub_map_fn
ukstub_map_fn:          resq 1      ; RDI = virtual, RSI = physical, RDX = flags
global ukstub_vmas
ukstub_vmas:            resd 1
global ukstub_ram
ukstub_ram:             resd 1      ; what phys_range_is_online_usable says
alignb 8
global ukstub_boot_ptr
ukstub_boot_ptr:        resq 1      ; what boot_file gives for any path
global ukstub_boot_len
ukstub_boot_len:        resq 1

section .text

; EDI = BDF, ESI = offset, EDX = width (4 here) → CF = 0, EAX
global kpci_cfg_read
kpci_cfg_read:
    sub rsp, 8
    call [rel ukstub_cfg_read_fn]
    add rsp, 8
    clc
    ret

; EDI = BDF, ESI = offset, EDX = width, ECX = value → CF = 0
global kpci_cfg_write
kpci_cfg_write:
    sub rsp, 8
    mov edx, ecx
    call [rel ukstub_cfg_write_fn]
    add rsp, 8
    clc
    ret

global virt_find_free_range
virt_find_free_range:
    sub rsp, 8
    call [rel ukstub_range_fn]
    add rsp, 8
    ret

global vma_create
vma_create:
    inc dword [rel ukstub_vmas]
    mov eax, 1
    ret

global virt_map
virt_map:
    sub rsp, 8
    call [rel ukstub_map_fn]
    add rsp, 8
    mov eax, 1
    ret

global phys_range_is_online_usable
phys_range_is_online_usable:
    mov eax, [rel ukstub_ram]
    ret

; RDI = path → RAX = bytes, RDX = size (0 when the test set none)
global boot_file
boot_file:
    mov rax, [rel ukstub_boot_ptr]
    mov rdx, [rel ukstub_boot_len]
    ret

%include "lib/usb/usb.asm"
%include "lib/usb/kernel.asm"
