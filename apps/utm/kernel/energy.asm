; UTM Kernel - Energy/Power Monitoring
; Pure Assembly Implementation

%ifndef _UTM_ENERGY_ASM_
%define _UTM_ENTERPRISE_ENERGY_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_energy_lock dq 0

MSR_RAPL_POWER_UNIT   equ 0x606
MSR_PKG_ENERGY_STATUS equ 0x611

section .bss
align 64
global utm_energy_state
utm_energy_state:
    resb ENERGY_STATE_SIZE

section .text

global utm_energy_init
global utm_energy_read_rapl
global utm_energy_convert_to_uj
global utm_energy_update_power
global utm_energy_probe_battery
global utm_energy_read_battery
global utm_energy_fill_system_sample
global utm_energy_estimate_process

extern utm_get_monotonic_ns

utm_energy_init:
    mov eax, 6
    cpuid
    test eax, 1
    jz .no_rapl
    
    mov byte [utm_energy_state + EnergyState.rapl_available], 1
    
    mov ecx, MSR_RAPL_POWER_UNIT
    rdmsr
    and eax, 0xF
    mov [utm_energy_state + EnergyState.power_units], al
    
    mov eax, edx
    shr eax, 8
    and eax, 0x1F
    mov [utm_energy_state + EnergyState.energy_units], al
    
    mov eax, edx
    shr eax, 16
    and eax, 0xF
    mov [utm_energy_state + EnergyState.time_units], al
    
    call utm_energy_read_rapl
    
.no_rapl:
    call utm_energy_probe_battery
    ret

utm_energy_read_rapl:
    cmp byte [utm_energy_state + EnergyState.rapl_available], 0
    je .done
    
    mov ecx, MSR_PKG_ENERGY_STATUS
    rdmsr
    call utm_energy_convert_to_uj
    mov [utm_energy_state + EnergyState.pkg_energy_uj], rax
    
.done:
    ret

utm_energy_convert_to_uj:
    mov ecx, [utm_energy_state + EnergyState.energy_units]
    mov r8, 1000000
    mul r8
    shr rax, cl
    ret

utm_energy_update_power:
    ret

utm_energy_probe_battery:
    ret

utm_energy_read_battery:
    ret

utm_energy_fill_system_sample:
    mov rax, [utm_energy_state + EnergyState.pkg_power_uv]
    mov [rdi + SystemSample.pkg_power_uv], rax
    
    mov rax, [utm_energy_state + EnergyState.dram_power_uv]
    mov [rdi + SystemSample.dram_power_uv], rax
    
    mov rax, [utm_energy_state + EnergyState.pp1_power_uv]
    mov [rdi + SystemSample.gpu_power_uv], rax
    
    mov rax, [utm_energy_state + EnergyState.pkg_energy_uj]
    mov [rdi + SystemSample.pkg_energy_uj], rax
    
    mov rax, [utm_energy_state + EnergyState.dram_energy_uj]
    mov [rdi + SystemSample.dram_energy_uj], rax
    
    ret

utm_energy_estimate_process:
    ret

%endif