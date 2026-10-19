; UTM Kernel - Task Manager Syscall Dispatcher
; Pure Assembly Implementation

%ifndef _UTM_SYSCALLS_ASM_
%define _UTM_ENTERPRISE_SYSCALLS_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_syscall_dispatch_table:
    dq sys_utm_get_proc_count      ; 0x100
    dq sys_utm_get_proc_list       ; 0x101
    dq sys_utm_get_proc_sample     ; 0x102
    dq sys_utm_get_proc_cmdline    ; 0x103
    dq sys_utm_get_proc_exe_path   ; 0x104
    dq sys_utm_get_proc_env        ; 0x105
    dq sys_utm_get_proc_fds        ; 0x106
    dq sys_utm_get_proc_threads    ; 0x107
    dq sys_utm_get_proc_children   ; 0x108
    dq sys_utm_get_proc_maps       ; 0x109
    dq sys_utm_unimplemented       ; 0x10A
    dq sys_utm_unimplemented       ; 0x10B
    dq sys_utm_unimplemented       ; 0x10C
    dq sys_utm_unimplemented       ; 0x10D
    dq sys_utm_unimplemented       ; 0x10E
    dq sys_utm_unimplemented       ; 0x10F
    dq sys_utm_get_sys_sample      ; 0x110
    dq sys_utm_get_cpu_topology    ; 0x111
    dq sys_utm_get_mem_info        ; 0x112
    dq sys_utm_get_disk_stats      ; 0x113
    dq sys_utm_get_net_stats       ; 0x114
    dq sys_utm_get_energy_stats    ; 0x115
    dq sys_utm_get_thermal_stats   ; 0x116
    dq sys_utm_get_fan_stats       ; 0x117
    dq sys_utm_get_gpu_stats       ; 0x118
    dq sys_utm_get_numa_info       ; 0x119
    dq sys_utm_get_disk_info       ; 0x11A
    dq sys_utm_get_net_info        ; 0x11B
    dq sys_utm_get_thermal_info    ; 0x11C
    dq sys_utm_get_gpu_info        ; 0x11D
    dq sys_utm_get_container_list  ; 0x11E
    dq sys_utm_get_container_sample; 0x11F
    dq sys_utm_get_cgroup_info     ; 0x120
    dq sys_utm_unimplemented       ; 0x121
    dq sys_utm_unimplemented       ; 0x122
    dq sys_utm_unimplemented       ; 0x123
    dq sys_utm_unimplemented       ; 0x124
    dq sys_utm_unimplemented       ; 0x125
    dq sys_utm_unimplemented       ; 0x126
    dq sys_utm_unimplemented       ; 0x127
    dq sys_utm_flight_start        ; 0x128
    dq sys_utm_flight_stop         ; 0x129
    dq sys_utm_flight_read         ; 0x12A
    dq sys_utm_flight_status       ; 0x12B
    dq sys_utm_unimplemented       ; 0x12C
    dq sys_utm_unimplemented       ; 0x12D
    dq sys_utm_unimplemented       ; 0x12E
    dq sys_utm_unimplemented       ; 0x12F
    dq sys_utm_proc_kill           ; 0x130
    dq sys_utm_proc_nice           ; 0x131
    dq sys_utm_proc_priority       ; 0x132
    dq sys_utm_proc_affinity       ; 0x133
    dq sys_utm_proc_suspend        ; 0x134
    dq sys_utm_proc_resume         ; 0x135
    dq sys_utm_proc_cgroup         ; 0x136
    dq sys_utm_alert_add           ; 0x138
    dq sys_utm_alert_remove        ; 0x139
    dq sys_utm_alert_list          ; 0x13A
    dq sys_utm_alert_ack           ; 0x13B
    dq sys_utm_power_cap           ; 0x13C
    dq sys_utm_thermal_throttle    ; 0x13D
    dq sys_utm_collector_register  ; 0x13E
    dq sys_utm_collector_unregister; 0x13F
    dq sys_utm_collector_overhead  ; 0x140
    dq sys_utm_auth_login          ; 0x148
    dq sys_utm_auth_logout         ; 0x149
    dq sys_utm_auth_check          ; 0x14A
    dq sys_utm_audit_read          ; 0x14B
    dq sys_utm_metrics_export      ; 0x150

section .text

global utm_syscall_handler

extern utm_proc_table
extern utm_proc_entry_size_val
extern utm_proc_get_by_pid
extern utm_cpu_get_stats
extern utm_mem_fill_system_sample
extern utm_disk_fill_system_sample
extern utm_net_fill_system_sample
extern utm_energy_fill_system_sample
extern utm_thermal_fill_system_sample
extern utm_gpu_fill_system_sample
extern utm_numa_fill_system_sample
extern utm_disk_get_device_info
extern utm_net_get_interface_info
extern utm_flight_rec_start
extern utm_flight_rec_stop
extern utm_flight_rec_read
extern utm_flight_rec_status
extern utm_alert_add_rule
extern utm_alert_remove_rule
global utm_alert_check
extern utm_alert_ack
extern utm_get_monotonic_ns
extern utm_get_uptime_ns

utm_syscall_handler:
    sub rax, SYSCALL_UTM_BASE
    cmp rax, 0xFF
    ja .invalid
    
    mov r10, [utm_syscall_dispatch_table + rax*8]
    jmp r10

.invalid:
    mov rax, UTM_ERR_INVAL
    ret

sys_utm_get_proc_count:
    mov rcx, MAX_PROCESSES
    mov rdi, utm_proc_table
    xor rax, rax
.count_loop:
    cmp byte [rdi + ProcessEntry.state], PROC_STATE_DEAD
    je .count_next
    cmp byte [rdi + ProcessEntry.state], 0
    je .count_next
    inc rax
.count_next:
    add rdi, PROC_ENTRY_SIZE
    loop .count_loop
    ret

sys_utm_get_proc_list:
    mov r8, rdi
    mov r9, rsi
    mov rcx, MAX_PROCESSES
    mov rdi, utm_proc_table
    xor rax, rax
.list_loop:
    cmp byte [rdi + ProcessEntry.state], PROC_STATE_DEAD
    je .list_next
    cmp byte [rdi + ProcessEntry.state], 0
    je .list_next
    
    cmp rax, r9
    jae .list_done
    
    mov rsi, rdi
    add rsi, ProcessEntry.identity
    mov rdi, r8
    mov rcx, PROC_IDENTITY_SIZE / 8
    rep movsq
    mov r8, rdi
    
    inc rax
.list_next:
    add rdi, PROC_ENTRY_SIZE
    loop .list_loop
.list_done:
    ret

sys_utm_get_proc_sample:
    call utm_proc_get_by_pid
    cmp rax, -1
    je .proc_not_found
    
    test rdx, rdx
    jz .proc_skip_verify
    cmp rdx, [rsi + ProcessEntry.identity + ProcessIdentity.create_tick]
    jne .pid_reused
.proc_skip_verify:
    
    call utm_proc_fill_sample
    ret

.proc_not_found:
    mov rax, UTM_ERR_NOPROC
    ret

.pid_reused:
    mov rax, UTM_ERR_INVAL
    ret

utm_proc_fill_sample:
    mov rdi, rsi
    mov rcx, PROC_SAMPLE_SIZE / 8
    xor rax, rax
    rep stosq
    
    mov rdi, utm_proc_table
    mov rcx, rax
    xor rdx, rdx
    mov rax, rcx
    mov r8, PROC_ENTRY_SIZE
    mul r8
    add rdi, rax
    add rdi, ProcessEntry.identity
    mov rsi, rsi
    mov rcx, PROC_IDENTITY_SIZE / 8
    rep movsq
    
    ret

sys_utm_get_proc_cmdline:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_proc_exe_path:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_proc_env:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_proc_fds:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_proc_threads:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_proc_children:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_proc_maps:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_sys_sample:
    call utm_cpu_get_stats
    call utm_mem_fill_system_sample
    call utm_disk_fill_system_sample
    call utm_net_fill_system_sample
    call utm_energy_fill_system_sample
    call utm_thermal_fill_system_sample
    call utm_gpu_fill_system_sample
    call utm_numa_fill_system_sample
    
    call utm_get_monotonic_ns
    mov [rdi + SystemSample.timestamp_ns], rax
    
    call utm_get_uptime_ns
    mov [rdi + SystemSample.uptime_ns], rax
    
    xor rax, rax
    ret

sys_utm_get_cpu_topology:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_mem_info:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_disk_stats:
    call utm_disk_fill_system_sample
    xor rax, rax
    ret

sys_utm_get_net_stats:
    call utm_net_fill_system_sample
    xor rax, rax
    ret

sys_utm_get_energy_stats:
    call utm_energy_fill_system_sample
    xor rax, rax
    ret

sys_utm_get_thermal_stats:
    call utm_thermal_fill_system_sample
    xor rax, rax
    ret

sys_utm_get_fan_stats:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_gpu_stats:
    call utm_gpu_fill_system_sample
    xor rax, rax
    ret

sys_utm_get_numa_info:
    call utm_numa_fill_system_sample
    xor rax, rax
    ret

sys_utm_get_disk_info:
    call utm_disk_get_device_info
    xor rax, rax
    ret

sys_utm_get_net_info:
    call utm_net_get_interface_info
    xor rax, rax
    ret

sys_utm_get_thermal_info:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_gpu_info:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_container_list:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_container_sample:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_get_cgroup_info:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_flight_start:
    call utm_flight_rec_start
    xor rax, rax
    ret

sys_utm_flight_stop:
    call utm_flight_rec_stop
    xor rax, rax
    ret

sys_utm_flight_read:
    call utm_flight_rec_read
    ret

sys_utm_flight_status:
    call utm_flight_rec_status
    xor rax, rax
    ret

sys_utm_proc_kill:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_proc_nice:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_proc_priority:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_proc_affinity:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_proc_suspend:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_proc_resume:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_proc_cgroup:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_alert_add:
    call utm_alert_add_rule
    ret

sys_utm_alert_remove:
    call utm_alert_remove_rule
    ret

sys_utm_alert_list:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_alert_ack:
    call utm_alert_ack
    ret

sys_utm_power_cap:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_thermal_throttle:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_collector_register:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_collector_unregister:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_collector_overhead:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_auth_login:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_auth_logout:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_auth_check:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_audit_read:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_metrics_export:
    mov rax, UTM_ERR_NOTSUPP
    ret

sys_utm_unimplemented:
    mov rax, UTM_ERR_NOTSUPP
    ret

utm_get_monotonic_ns:
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov rcx, 3000000000
    div rcx
    ret

utm_get_uptime_ns:
    call utm_get_monotonic_ns
    ret

%endif