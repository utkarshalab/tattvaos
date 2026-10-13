%ifndef KERNEL_ARCH_X86_64_VTD_ASM
%define KERNEL_ARCH_X86_64_VTD_ASM
; =============================================================================
; Intel VT-d remapping-hardware capability discovery.
;
; This layer is intentionally read-only. It validates that every retained DRHD
; register window is inside the current identity map, reads VERSION/CAP/ECAP,
; and publishes a complete all-units capability snapshot. It never writes
; GCMD, IRTA, invalidation registers, or any other remapping-hardware state.
; =============================================================================

[BITS 64]

%include "kernel/arch/x86_64/dmar.asm"

VTD_VERSION_REG                 equ 0x00
VTD_CAP_REG                     equ 0x08
VTD_ECAP_REG                    equ 0x10

VTD_ECAP_C                      equ 1 << 0
VTD_ECAP_QI                     equ 1 << 1
VTD_ECAP_IR                     equ 1 << 3
VTD_ECAP_EIM                    equ 1 << 4
VTD_COMMON_FEATURE_MASK         equ VTD_ECAP_C | VTD_ECAP_QI | VTD_ECAP_IR | VTD_ECAP_EIM
VTD_INTERRUPT_REMAP_FEATURES    equ VTD_ECAP_QI | VTD_ECAP_IR

VTD_CAPABILITY_BYTES            equ 24
VTD_CAPABILITY_VERSION_OFF      equ 0
VTD_CAPABILITY_CAP_OFF          equ 8
VTD_CAPABILITY_ECAP_OFF         equ 16

VTD_PROBE_STATUS_OK             equ 0
VTD_PROBE_STATUS_ABSENT         equ 1
VTD_PROBE_STATUS_CONTRACT       equ 2
VTD_PROBE_STATUS_MAPPING        equ 3
VTD_PROBE_STATUS_REGISTERS      equ 4

section .text

; EDI=VERSION, RSI=CAP, RDX=ECAP.
; CF=0/EAX=normalized common-feature bits. CF=1 rejects impossible hardware.
global vtd_capabilities_decode
vtd_capabilities_decode:
    test edi, 0xFFFFFF00             ; VERSION bits 31:8 are reserved
    jnz .invalid
    test edi, 0xF0                   ; architecture major version must exist
    jz .invalid
    cmp rsi, -1                      ; conventional absent-MMIO readback
    je .invalid
    cmp rdx, -1
    je .invalid

    mov eax, edx
    and eax, VTD_COMMON_FEATURE_MASK
    test eax, VTD_ECAP_IR
    jz .without_interrupt_remapping
    test eax, VTD_ECAP_QI            ; IR implementations must provide QI
    jz .invalid
    clc
    ret

.without_interrupt_remapping:
    and eax, ~VTD_ECAP_EIM           ; EIM is meaningful only with IR
    clc
    ret

.invalid:
    xor eax, eax
    stc
    ret

; Probe every retained DRHD as one transaction.
; CF=0/EAX=1: raw capabilities retained (remapping readiness is separate).
; CF=0/EAX=0: no validated DMAR hardware units exist.
; CF=1/EAX=0: descriptor, mapping, or hardware-register validation failed.
global vtd_probe
vtd_probe:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov byte [rel vtd_probe_ready], 0
    mov byte [rel vtd_interrupt_remapping_ready], 0
    mov byte [rel vtd_extended_interrupt_mode_ready], 0
    mov dword [rel vtd_probe_status], VTD_PROBE_STATUS_OK
    mov dword [rel vtd_probe_count], 0
    mov dword [rel vtd_common_features], 0

    mov r12d, [rel smp_dmar_drhd_count]
    test r12d, r12d
    jz .absent
    cmp r12d, SMP_DMAR_MAX_DRHDS
    ja .contract_invalid

    lea r13, [rel smp_dmar_drhds]
    lea r14, [rel vtd_capabilities]
    mov r15d, VTD_COMMON_FEATURE_MASK
    xor ebx, ebx

.unit_loop:
    cmp ebx, r12d
    jae .units_complete
    mov r10, rbx
    imul r10, SMP_DMAR_DRHD_BYTES
    add r10, r13

    mov rax, [r10 + SMP_DMAR_DRHD_BASE_OFF]
    test rax, rax
    jz .contract_invalid
    movzx ecx, byte [r10 + SMP_DMAR_DRHD_REG_SIZE_OFF]
    cmp ecx, 15
    ja .contract_invalid
    mov r11, 4096
    shl r11, cl
    mov r9, r11
    dec r9
    test rax, r9
    jnz .contract_invalid
    mov r9, rax
    add r9, r11
    jc .mapping_invalid
    cmp r9, [rel phys_state + phys_state_t.direct_map_limit]
    ja .mapping_invalid

    ; These are the only remapping-hardware accesses in this layer.
    lfence
    mov edi, dword [rax + VTD_VERSION_REG]
    mov rsi, qword [rax + VTD_CAP_REG]
    mov rdx, qword [rax + VTD_ECAP_REG]
    lfence
    call vtd_capabilities_decode
    jc .registers_invalid
    and r15d, eax

    mov r11, rbx
    imul r11, VTD_CAPABILITY_BYTES
    add r11, r14
    mov [r11 + VTD_CAPABILITY_VERSION_OFF], edi
    mov [r11 + VTD_CAPABILITY_CAP_OFF], rsi
    mov [r11 + VTD_CAPABILITY_ECAP_OFF], rdx
    inc ebx
    jmp .unit_loop

.units_complete:
    mov [rel vtd_probe_count], r12d
    mov [rel vtd_common_features], r15d
    mov byte [rel vtd_probe_ready], 1
    test r15d, VTD_ECAP_EIM
    setnz byte [rel vtd_extended_interrupt_mode_ready]

    test byte [rel smp_dmar_flags], DMAR_FLAG_INTR_REMAP
    jz .unsupported
    mov eax, r15d
    and eax, VTD_INTERRUPT_REMAP_FEATURES
    cmp eax, VTD_INTERRUPT_REMAP_FEATURES
    jne .unsupported
    cmp byte [rel smp_x2apic_mode], 0
    je .remapping_ready
    cmp byte [rel vtd_extended_interrupt_mode_ready], 0
    je .x2apic_unsupported

.remapping_ready:
    mov byte [rel vtd_interrupt_remapping_ready], 1
    lea rsi, [rel msg_vtd_ready]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_vtd_ready_suffix]
    call uart_print_str
    jmp .probe_succeeded

.unsupported:
    lea rsi, [rel msg_vtd_unsupported]
    call uart_print_str
    jmp .probe_succeeded

.x2apic_unsupported:
    lea rsi, [rel msg_vtd_x2apic_unsupported]
    call uart_print_str

.probe_succeeded:
    mov eax, 1
    clc
    jmp .done

.absent:
    mov dword [rel vtd_probe_status], VTD_PROBE_STATUS_ABSENT
    lea rsi, [rel msg_vtd_absent]
    call uart_print_str
    xor eax, eax
    clc
    jmp .done

.contract_invalid:
    mov dword [rel vtd_probe_status], VTD_PROBE_STATUS_CONTRACT
    jmp .probe_rejected
.mapping_invalid:
    mov dword [rel vtd_probe_status], VTD_PROBE_STATUS_MAPPING
    jmp .probe_rejected
.registers_invalid:
    mov dword [rel vtd_probe_status], VTD_PROBE_STATUS_REGISTERS
.probe_rejected:
    lea rsi, [rel msg_vtd_rejected]
    call uart_print_str
    xor eax, eax
    stc

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
msg_vtd_ready:              db "VT-d: ", 0
msg_vtd_ready_suffix:       db " remapping units support interrupt remapping", 0x0D, 0x0A, 0
msg_vtd_absent:             db "VT-d: unavailable; interrupt remapping disabled", 0x0D, 0x0A, 0
msg_vtd_unsupported:        db "VT-d: interrupt remapping unsupported; disabled", 0x0D, 0x0A, 0
msg_vtd_x2apic_unsupported: db "VT-d: x2APIC interrupt format unsupported; remapping disabled", 0x0D, 0x0A, 0
msg_vtd_rejected:           db "VT-d: capability probe rejected; interrupt remapping disabled", 0x0D, 0x0A, 0

section .bss
alignb 8
global vtd_probe_ready
global vtd_interrupt_remapping_ready
global vtd_extended_interrupt_mode_ready
global vtd_probe_status
global vtd_probe_count
global vtd_common_features
global vtd_capabilities
vtd_probe_ready:                       resb 1
vtd_interrupt_remapping_ready:         resb 1
vtd_extended_interrupt_mode_ready:     resb 1
alignb 4
vtd_probe_status:                      resd 1
vtd_probe_count:                       resd 1
vtd_common_features:                   resd 1
alignb 8
vtd_capabilities:                      resb SMP_DMAR_MAX_DRHDS * VTD_CAPABILITY_BYTES

%endif ; KERNEL_ARCH_X86_64_VTD_ASM
