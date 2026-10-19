; UTM Kernel - Thermal Monitoring
; Pure Assembly Implementation

%ifndef _UTM_ENTERPRISE_THERMAL_ASM_
%define _UTM_ENTERPRISE_THERMAL_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_thermal_lock dq 0

section .bss
align 64
global utm_thermal_state
utm_thermal_state:
    resb GLOBAL_THERMAL_STATE_SIZE

section .text

global utm_thermal_init
global utm_thermal_detect_zones
global utm_thermal_detect_fans
global utm_thermal_read_all
global utm_thermal_read_intel_msr
global utm_thermal_read_acpi
global utm_thermal_read_hwmon
global utm_thermal_read_ipmi
global utm_thermal_read_fans
global utm_thermal_calculate_pressure
global utm_thermal_fill_system_sample
global utm_thermal_get_zone_info

extern utm_get_monotonic_ns

utm_thermal_init:
    mov rdi, utm_thermal_state
    mov rcx, GLOBAL_THERMAL_STATE_SIZE / 8
    xor rax, rax
    rep stosq
    
    call utm_thermal_detect_zones
    call utm_thermal_detect_fans
    ret

utm_thermal_detect_zones:
    ret

utm_thermal_detect_fans:
    mov dword [utm_thermal_state + GlobalThermalState.fan_count], 0
    ret

utm_thermal_read_all:
    call utm_thermal_read_intel_msr
    call utm_thermal_read_acpi
    call utm_thermal_read_hwmon
    call utm_thermal_read_ipmi
    call utm_thermal_read_fans
    call utm_thermal_calculate_pressure
    
    call utm_get_monotonic_ns
    mov [utm_thermal_state + GlobalThermalState.last_update_ns], rax
    ret

utm_thermal_read_intel_msr:
    mov ecx, 0x1A2
    rdmsr
    shr eax, 16
    and eax, 0xFF
    mov r8d, eax
    
    mov ecx, 0x1B1
    rdmsr
    and eax, 0xFFFF
    sub r8d, eax
    imul r8d, 1000
    mov [utm_thermal_state + GlobalThermalState.temps_millicelsius], r8d
    ret

utm_thermal_read_acpi:
    ret

utm_thermal_read_hwmon:
    ret

utm_thermal_read_ipmi:
    ret

utm_thermal_read_fans:
    ret

utm_thermal_calculate_pressure:
    mov rcx, [utm_thermal_state + GlobalThermalState.zone_count]
    test rcx, rcx
    jz .done
    mov rdi, utm_thermal_state + GlobalThermalState.temps_millicelsius
    mov rsi, utm_thermal_state + GlobalThermalState.trip_critical
    mov r8, utm_thermal_state + GlobalThermalState.trip_active
    mov r9, utm_thermal_state + GlobalThermalState.trip_passive
    xor rax, rax
    
.pressure_loop:
    mov edx, [rdi]
    mov ecx, [rsi]
    cmp edx, ecx
    jge .critical
    mov ecx, [r8]
    cmp edx, ecx
    jge .serious
    mov ecx, [r9]
    cmp edx, ecx
    jge .fair
    jmp .next
    
.critical:
    mov al, 3
    jmp .done
.serious:
    cmp al, 2
    jl .set_serious
    jmp .next
.set_serious:
    mov al, 2
    jmp .next
.fair:
    cmp al, 1
    jl .set_fair
    jmp .next
.set_fair:
    mov al, 1
    
.next:
    add rdi, 4
    add rsi, 4
    add r8, 4
    add r9, 4
    loop .pressure_loop
    
.done:
    mov [utm_thermal_state + GlobalThermalState.pressure], al
    ret

utm_thermal_fill_system_sample:
    mov rcx, MAX_THERMAL_ZONES
    mov rsi, utm_thermal_state + GlobalThermalState.temps_millicelsius
    add rdi, SystemSample.temp_millicelsius
    rep movsd
    
    mov al, [utm_thermal_state + GlobalThermalState.pressure]
    mov [rdi + SystemSample.thermal_pressure - SystemSample.temp_millicelsius], al
    
    mov rcx, 8
    mov rsi, utm_thermal_state + GlobalThermalState.fan_rpm
    add rdi, SystemSample.fan_rpm - SystemSample.temp_millicelsius
    rep movsd
    ret

utm_thermal_get_zone_info:
    ret

%endif