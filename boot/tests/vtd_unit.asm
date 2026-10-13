; Native hostile-input checks for kernel/arch/x86_64/vtd.asm.
[BITS 64]
default rel

phys_state_t.direct_map_limit equ 0

%include "kernel/arch/x86_64/vtd.asm"

section .text
global _start
_start:
    ; Decode a complete, internally consistent interrupt-remapping feature set.
    mov edi, 0x10
    mov esi, 0x1234
    mov edx, VTD_COMMON_FEATURE_MASK
    call vtd_capabilities_decode
    jc fail_decode_valid
    cmp eax, VTD_COMMON_FEATURE_MASK
    jne fail_decode_valid

    ; EIM is not published when interrupt remapping itself is absent.
    mov edi, 0x70
    xor esi, esi
    mov edx, VTD_ECAP_QI | VTD_ECAP_EIM
    call vtd_capabilities_decode
    jc fail_decode_normalize
    cmp eax, VTD_ECAP_QI
    jne fail_decode_normalize

    xor edi, edi
    xor esi, esi
    xor edx, edx
    call vtd_capabilities_decode
    jnc fail_decode_zero_version

    mov edi, 0x110
    xor esi, esi
    xor edx, edx
    call vtd_capabilities_decode
    jnc fail_decode_reserved_version

    mov edi, 0x10
    xor esi, esi
    mov edx, VTD_ECAP_IR
    call vtd_capabilities_decode
    jnc fail_decode_ir_without_qi

    mov edi, 0x10
    mov rsi, -1
    xor edx, edx
    call vtd_capabilities_decode
    jnc fail_decode_absent_cap

    mov edi, 0x10
    xor esi, esi
    mov rdx, -1
    call vtd_capabilities_decode
    jnc fail_decode_absent_ecap

    ; Two mapped units with common QI/IR/EIM support are publishable in x2APIC.
    call reset_valid_probe
    call vtd_probe
    jc fail_probe_valid
    cmp eax, 1
    jne fail_probe_valid
    cmp byte [rel vtd_probe_ready], 1
    jne fail_probe_valid
    cmp byte [rel vtd_interrupt_remapping_ready], 1
    jne fail_probe_valid
    cmp byte [rel vtd_extended_interrupt_mode_ready], 1
    jne fail_probe_valid
    cmp dword [rel vtd_probe_count], 2
    jne fail_probe_valid
    cmp dword [rel vtd_common_features], VTD_COMMON_FEATURE_MASK
    jne fail_probe_valid
    cmp dword [rel vtd_capabilities + VTD_CAPABILITY_VERSION_OFF], 0x10
    jne fail_probe_valid
    cmp qword [rel vtd_capabilities + VTD_CAPABILITY_CAP_OFF], 0x1234
    jne fail_probe_valid
    cmp qword [rel vtd_capabilities + VTD_CAPABILITY_ECAP_OFF], VTD_COMMON_FEATURE_MASK
    jne fail_probe_valid
    cmp dword [rel fake_mmio0 + VTD_VERSION_REG], 0x10
    jne fail_probe_wrote_mmio
    cmp qword [rel fake_mmio0 + VTD_CAP_REG], 0x1234
    jne fail_probe_wrote_mmio
    cmp qword [rel fake_mmio0 + VTD_ECAP_REG], VTD_COMMON_FEATURE_MASK
    jne fail_probe_wrote_mmio

    ; x2APIC needs common EIM support before interrupt remapping is ready.
    call reset_valid_probe
    mov qword [rel fake_mmio1 + VTD_ECAP_REG], VTD_ECAP_QI | VTD_ECAP_IR
    call vtd_probe
    jc fail_probe_x2apic_eim
    cmp byte [rel vtd_probe_ready], 1
    jne fail_probe_x2apic_eim
    cmp byte [rel vtd_interrupt_remapping_ready], 0
    jne fail_probe_x2apic_eim
    cmp byte [rel vtd_extended_interrupt_mode_ready], 0
    jne fail_probe_x2apic_eim

    ; The same units are sufficient for the 8-bit xAPIC destination format.
    mov byte [rel smp_x2apic_mode], 0
    call vtd_probe
    jc fail_probe_xapic
    cmp byte [rel vtd_interrupt_remapping_ready], 1
    jne fail_probe_xapic

    ; Firmware policy remains authoritative even when hardware supports IR.
    call reset_valid_probe
    mov byte [rel smp_dmar_flags], 0
    call vtd_probe
    jc fail_probe_policy
    cmp byte [rel vtd_probe_ready], 1
    jne fail_probe_policy
    cmp byte [rel vtd_interrupt_remapping_ready], 0
    jne fail_probe_policy

    ; An incomplete mapping rejects the whole snapshot and publishes no count.
    call reset_valid_probe
    lea rax, [rel fake_mmio1]
    mov [rel phys_state], rax
    call vtd_probe
    jnc fail_probe_mapping
    cmp eax, 0
    jne fail_probe_mapping
    cmp byte [rel vtd_probe_ready], 0
    jne fail_probe_mapping
    cmp dword [rel vtd_probe_count], 0
    jne fail_probe_mapping
    cmp dword [rel vtd_probe_status], VTD_PROBE_STATUS_MAPPING
    jne fail_probe_mapping

    ; Invalid register contents also discard earlier, otherwise-valid units.
    call reset_valid_probe
    mov dword [rel fake_mmio1 + VTD_VERSION_REG], 0
    call vtd_probe
    jnc fail_probe_registers
    cmp byte [rel vtd_probe_ready], 0
    jne fail_probe_registers
    cmp dword [rel vtd_probe_count], 0
    jne fail_probe_registers
    cmp dword [rel vtd_probe_status], VTD_PROBE_STATUS_REGISTERS
    jne fail_probe_registers

    ; A corrupt producer count is rejected before indexing the descriptor array.
    call reset_valid_probe
    mov dword [rel smp_dmar_drhd_count], SMP_DMAR_MAX_DRHDS + 1
    call vtd_probe
    jnc fail_probe_contract
    cmp dword [rel vtd_probe_status], VTD_PROBE_STATUS_CONTRACT
    jne fail_probe_contract

    ; Absence is a clean, explicitly unpublished state rather than an error.
    call reset_valid_probe
    mov dword [rel smp_dmar_drhd_count], 0
    call vtd_probe
    jc fail_probe_absent
    test eax, eax
    jnz fail_probe_absent
    cmp byte [rel vtd_probe_ready], 0
    jne fail_probe_absent
    cmp dword [rel vtd_probe_status], VTD_PROBE_STATUS_ABSENT
    jne fail_probe_absent

    xor edi, edi
    jmp exit

fail_decode_valid:            mov edi, 1
                              jmp exit
fail_decode_normalize:        mov edi, 2
                              jmp exit
fail_decode_zero_version:     mov edi, 3
                              jmp exit
fail_decode_reserved_version: mov edi, 4
                              jmp exit
fail_decode_ir_without_qi:    mov edi, 5
                              jmp exit
fail_decode_absent_cap:       mov edi, 6
                              jmp exit
fail_decode_absent_ecap:      mov edi, 7
                              jmp exit
fail_probe_valid:             mov edi, 8
                              jmp exit
fail_probe_wrote_mmio:        mov edi, 9
                              jmp exit
fail_probe_x2apic_eim:        mov edi, 10
                              jmp exit
fail_probe_xapic:             mov edi, 11
                              jmp exit
fail_probe_policy:            mov edi, 12
                              jmp exit
fail_probe_mapping:           mov edi, 13
                              jmp exit
fail_probe_registers:         mov edi, 14
                              jmp exit
fail_probe_contract:          mov edi, 15
                              jmp exit
fail_probe_absent:            mov edi, 16

exit:
    mov eax, 60
    syscall

reset_valid_probe:
    mov dword [rel smp_dmar_drhd_count], 2
    mov byte [rel smp_dmar_flags], DMAR_FLAG_INTR_REMAP
    mov byte [rel smp_x2apic_mode], 1
    lea rax, [rel fake_mmio0]
    mov [rel smp_dmar_drhds + SMP_DMAR_DRHD_BASE_OFF], rax
    lea rax, [rel fake_mmio1]
    mov [rel smp_dmar_drhds + SMP_DMAR_DRHD_BYTES + SMP_DMAR_DRHD_BASE_OFF], rax
    lea rax, [rel fake_mmio1 + 4096]
    mov [rel phys_state], rax
    mov dword [rel fake_mmio0 + VTD_VERSION_REG], 0x10
    mov qword [rel fake_mmio0 + VTD_CAP_REG], 0x1234
    mov qword [rel fake_mmio0 + VTD_ECAP_REG], VTD_COMMON_FEATURE_MASK
    mov dword [rel fake_mmio1 + VTD_VERSION_REG], 0x20
    mov qword [rel fake_mmio1 + VTD_CAP_REG], 0x5678
    mov qword [rel fake_mmio1 + VTD_ECAP_REG], VTD_COMMON_FEATURE_MASK
    ret

uart_print_str:
uart_print_dec:
    ret

section .data
align 8
phys_state:                 dq 0
smp_dmar_drhd_count:        dd 0
smp_dmar_flags:             db 0
smp_x2apic_mode:            db 0
align 8
smp_dmar_drhds:
    dq 0
    dd 0, 0, 0
    dw 0
    db 0, 0
    dq 0
    dd 0, 0, 0
    dw 0
    db 0, 0
    times (SMP_DMAR_MAX_DRHDS - 2) * SMP_DMAR_DRHD_BYTES db 0

align 4096
fake_mmio0:
    dd 0x10, 0
    dq 0x1234
    dq VTD_COMMON_FEATURE_MASK
    times 4096 - ($ - fake_mmio0) db 0xA5

align 4096
fake_mmio1:
    dd 0x20, 0
    dq 0x5678
    dq VTD_COMMON_FEATURE_MASK
    times 4096 - ($ - fake_mmio1) db 0x5A
