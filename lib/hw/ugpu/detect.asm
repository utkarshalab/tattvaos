; =============================================================================
; Tattva OS — lib/hw/ugpu/detect.asm
; =============================================================================
; GPU inventory: scans PCI configuration space for class 0x03 (Display
; Controller) devices and records their identity + PCIe capability offset.
;
; lib/io/pci is not wired into the single kernel translation unit yet (only
; lib/hw/ucpu/{mtrr,pat}.asm and now this lib/hw tree are), so this uses its
; own minimal legacy CF8/CFC config-space reader rather than depending on
; lib/io/pci/config.asm. hw_pci_cfg_read32 is deliberately generic — see
; ucxl/cxl.asm, which reuses it instead of duplicating the CF8/CFC protocol
; a third time.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UGPU_DETECT_ASM
%define LIB_HW_UGPU_DETECT_ASM

[BITS 64]

UGPU_MAX_DEVICES equ 8
HW_PCI_CAP_ID_PCIE equ 0x10

struc ugpu_device_t
    .bus            resd 1
    .device         resd 1
    .function       resd 1
    .vendor_id      resd 1
    .device_id      resd 1
    .pcie_cap_off   resd 1      ; 0 if the device has no PCIe capability
endstruc

section .bss
global ugpu_devices
global ugpu_device_count
ugpu_devices:       resb ugpu_device_t_size * UGPU_MAX_DEVICES
ugpu_device_count:  resq 1

section .text

; -----------------------------------------------------------------------------
; hw_pci_cfg_read32 — legacy CF8/CFC PCI configuration space dword read
; Input:
;   RDI = bus (0-255), RSI = device (0-31), RDX = function (0-7)
;   RCX = dword-aligned offset (0-252; low 2 bits are masked off)
; Output:
;   RAX = 32-bit value at that offset
; Clobbers: RAX, RCX, RDX, R8
; -----------------------------------------------------------------------------
global hw_pci_cfg_read32
hw_pci_cfg_read32:
    mov eax, edi
    shl eax, 16                     ; bus << 16
    mov r8d, esi
    shl r8d, 11                     ; device << 11
    or eax, r8d
    mov r8d, edx
    shl r8d, 8                      ; function << 8
    or eax, r8d
    and ecx, 0xFC
    or eax, ecx                     ; dword-aligned offset
    or eax, 0x80000000              ; enable bit

    mov dx, 0x0CF8
    out dx, eax

    mov dx, 0x0CFC
    in eax, dx
    ret

; -----------------------------------------------------------------------------
; ugpu_detect_init — scans all PCI bus/device/function slots for class 0x03
; (Display Controller) devices
; Input:  none
; Output: RAX = number of GPU devices recorded (capped at UGPU_MAX_DEVICES)
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8, R12-R15
; -----------------------------------------------------------------------------
global ugpu_detect_init
ugpu_detect_init:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov qword [rel ugpu_device_count], 0

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
    and ebx, 0xFFFF                  ; EBX = vendor_id
    cmp ebx, 0xFFFF
    je .next_func                    ; no device in this slot

    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, 0x08
    call hw_pci_cfg_read32           ; class/subclass/prog_if/revision
    shr eax, 24                      ; EAX = base class code
    cmp al, 0x03                     ; Display Controller
    jne .next_func

    mov rax, [rel ugpu_device_count]
    cmp rax, UGPU_MAX_DEVICES
    jae .next_func
    imul rax, ugpu_device_t_size
    lea r15, [rel ugpu_devices + rax]

    mov [r15 + ugpu_device_t.bus], r12d
    mov [r15 + ugpu_device_t.device], r13d
    mov [r15 + ugpu_device_t.function], r14d
    mov eax, ebx                     ; EBX still holds the vendor:device dword
    and eax, 0xFFFF
    mov [r15 + ugpu_device_t.vendor_id], eax
    mov eax, ebx
    shr eax, 16
    mov [r15 + ugpu_device_t.device_id], eax
    mov dword [r15 + ugpu_device_t.pcie_cap_off], 0

    ; Walk the capability list (pointer at offset 0x34) for PCIe (ID 0x10).
    ; Bounded to 48 hops (PCI config space is 256 bytes = at most 64 dword
    ; slots) so a malformed/cyclic list can't hang boot.
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, 0x34
    call hw_pci_cfg_read32
    and eax, 0xFF                    ; EAX = capabilities pointer
    mov ebx, 48                      ; EBX = hop budget

.cap_walk:
    test eax, eax
    jz .cap_done
    cmp eax, 0xFF
    je .cap_done
    dec ebx
    jz .cap_done

    mov ecx, eax                     ; ECX = this capability's byte offset
    push rcx
    and ecx, 0xFC
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call hw_pci_cfg_read32            ; [7:0]=cap ID, [15:8]=next pointer
    pop rcx

    mov edx, eax
    and edx, 0xFF                    ; cap ID
    cmp edx, HW_PCI_CAP_ID_PCIE
    jne .cap_next
    mov [r15 + ugpu_device_t.pcie_cap_off], ecx
    jmp .cap_done

.cap_next:
    shr eax, 8
    and eax, 0xFF                    ; next pointer
    jmp .cap_walk

.cap_done:
    inc qword [rel ugpu_device_count]

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

    mov rax, [rel ugpu_device_count]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UGPU_DETECT_ASM
