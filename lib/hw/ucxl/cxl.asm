; =============================================================================
; Tattva OS — lib/hw/ucxl/cxl.asm
; =============================================================================
; CXL memory device enumeration: scans PCI configuration space for class
; 0x05 / subclass 0x02 (CXL Memory Device, CXL 2.0's PCI-SIG class code
; assignment) devices.
;
; lib/mem/virt/cxl/cxl_t1.asm already exists, but it has no real device
; discovery behind it — cxl_t1_init just sets a hardcoded bandwidth
; constant (64000 MB/s, "PCIe Gen5 x16") and an active flag, unconditionally.
; This is the missing discovery step: real PCI identity for whatever CXL
; memory devices are actually present.
;
; Scope limit: the CXL DVSEC (Designated Vendor-Specific Extended
; Capability, vendor ID 0x1E98) that would give the real Register Locator
; and device-type (Type 1/2/3) breakdown lives in PCIe Extended
; Configuration Space (offset >= 0x100), which the legacy CF8/CFC
; mechanism this file uses cannot address — CF8/CFC only reaches the first
; 256 bytes. Reaching it needs ECAM (MMIO-based, from the ACPI MCFG
; table), which lib/hw doesn't have yet (lib/io/acpi/mcfg.asm implements
; it but isn't wired into the kernel translation unit). Class-code
; detection also only catches CXL Type 3 (memory expander) devices — Type
; 1/2 accelerators don't get a distinguishing class code, only the DVSEC
; tells them apart, which is exactly what's out of reach here.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UCXL_CXL_ASM
%define LIB_HW_UCXL_CXL_ASM

%include "lib/hw/ugpu/detect.asm"

[BITS 64]

UCXL_MAX_DEVICES equ 8
HW_PCI_CLASS_MEMORY_CONTROLLER equ 0x05
HW_PCI_SUBCLASS_CXL_MEMORY     equ 0x02

struc ucxl_device_t
    .bus            resd 1
    .device         resd 1
    .function       resd 1
    .vendor_id      resd 1
    .device_id      resd 1
endstruc

section .bss
global ucxl_devices
global ucxl_device_count
ucxl_devices:       resb ucxl_device_t_size * UCXL_MAX_DEVICES
ucxl_device_count:  resq 1

section .text

; -----------------------------------------------------------------------------
; ucxl_detect_init — scans PCI for class 0x05/subclass 0x02 (CXL Type 3
; memory device) functions
; Input:  none
; Output: RAX = number of CXL devices recorded (capped at UCXL_MAX_DEVICES)
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8, R12-R15
; -----------------------------------------------------------------------------
global ucxl_detect_init
ucxl_detect_init:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov qword [rel ucxl_device_count], 0

    xor r12, r12                    ; R12 = bus
.bus_loop:
    xor r13, r13                    ; R13 = device
.dev_loop:
    xor r14, r14                    ; R14 = function
.func_loop:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, 0x00
    call hw_pci_cfg_read32           ; EAX = device_id:vendor_id
    mov ebx, eax
    and ebx, 0xFFFF
    cmp ebx, 0xFFFF
    je .next_func                    ; no device in this slot

    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, 0x08
    call hw_pci_cfg_read32           ; class/subclass/prog_if/revision
    mov r15d, eax
    shr r15d, 24                     ; R15D = base class
    cmp r15b, HW_PCI_CLASS_MEMORY_CONTROLLER
    jne .next_func
    mov r15d, eax
    shr r15d, 16                     ; R15B (low byte) = subclass
    cmp r15b, HW_PCI_SUBCLASS_CXL_MEMORY
    jne .next_func

    mov rax, [rel ucxl_device_count]
    cmp rax, UCXL_MAX_DEVICES
    jae .next_func
    imul rax, ucxl_device_t_size
    lea r15, [rel ucxl_devices + rax]

    mov [r15 + ucxl_device_t.bus], r12d
    mov [r15 + ucxl_device_t.device], r13d
    mov [r15 + ucxl_device_t.function], r14d
    mov eax, ebx
    and eax, 0xFFFF
    mov [r15 + ucxl_device_t.vendor_id], eax
    mov eax, ebx
    shr eax, 16
    mov [r15 + ucxl_device_t.device_id], eax

    inc qword [rel ucxl_device_count]

.next_func:
    inc r14
    cmp r14, 8
    jl .func_loop

    inc r13
    cmp r13, 32
    jl .dev_loop

    inc r12
    cmp r12, 256
    jl .bus_loop

    mov rax, [rel ucxl_device_count]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UCXL_CXL_ASM
