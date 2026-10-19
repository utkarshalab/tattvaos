; UTM Task Manager - Shared Data Structures
; Pure Assembly Implementation

%ifndef _UTM_STRUCTURES_INC_
%define _UTM_ENTERPRISE_STRUCTURES_INC_

%include "constants.inc"

struc ProcessIdentity
    .pid            resq 1
    .create_time    resq 1
    .create_tick    resq 1
    .exe_hash_low   resq 1
    .exe_hash_high  resq 1
    .cmdline_hash_low   resq 1
    .cmdline_hash_high resq 1
    .ppid           resq 1
    .uid            resd 1
    .gid            resd 1
    .cgroup_id      resq 1
    .namespace_id   resq 1
    .container_id   resq 1
    .pad            resq 1
endstruc

%define PROC_IDENTITY_SIZE  (ProcessIdentity_size)

struc ProcessEntry
    .identity       resb PROC_IDENTITY_SIZE
    .kernel_stack   resq 1
    .user_stack     resq 1
    .page_table     resq 1
    .state          resb 1
    .flags          resb 1
    .sched_policy   resb 1
    .nice           resb 1
    .cpu_affinity   resq 4
    .parent_tidx    resd 1
    .child_list     resd 1
    .sibling_next   resd 1
    .thread_list    resd 1
    .fd_table       resq 1
    .vm_map         resq 1
    .signal_mask    resq 2
    .pending_sigs   resq 2
    .exit_code      resd 1
    .exit_signal    resd 1
    .start_time_ns  resq 1
    .total_cpu_ns   resq 1
    .last_sched_ns  resq 1
    .pad            resq 4
endstruc

%define PROC_ENTRY_SIZE  (ProcessEntry_size)

struc ThreadEntry
    .proc_index     resd 1
    .cpu_user_ns    resq 1
    .cpu_kernel_ns  resq 1
    .last_mode      resb 1
    .pad            resb 7
    .affinity       resq 4
    .priority       resd 1
    .policy         resb 1
    .pad2           resb 3
endstruc

%define THREAD_ENTRY_SIZE  (ThreadEntry_size)

struc PerCpuStats
    .cpu_id         resd 1
    .is_p_core      resb 1
    .is_active      resb 1
    .pad            resw 1
    .freq_mhz       resd 1
    .max_freq_mhz   resd 1
    .min_freq_mhz   resd 1
    .current_pstate resb 1
    .current_cstate resb 1
    .pad2           resw 1
    .numa_node      resd 1
    .user_ns        resq 1
    .kernel_ns      resq 1
    .idle_ns        resq 1
    .iowait_ns      resq 1
    .irq_ns         resq 1
    .softirq_ns     resq 1
    .steal_ns       resq 1
    .guest_ns       resq 1
    .ctx_switches   resq 1
    .migrations     resq 1
    .last_update_ns resq 1
endstruc

%define PER_CPU_STATS_SIZE  (PerCpuStats_size)

struc NumaNodeStats
    .node_id        resd 1
    .memory_total   resq 1
    .memory_free    resq 1
    .memory_used    resq 1
    .memory_cached  resq 1
    .memory_local_hits  resq 1
    .memory_remote_hits resq 1
    .interleave_hits    resq 1
    .pad            resq 3
endstruc

%define NUMA_NODE_STATS_SIZE  (NumaNodeStats_size)

struc ProcessSample
    .identity       resb PROC_IDENTITY_SIZE
    .cpu_user_ns    resq 1
    .cpu_kernel_ns  resq 1
    .cpu_total_ns   resq 1
    .cpu_percent    resd 1
    .cpu_delta_ns   resq 1
    .core_affinity  resq 4
    .last_core      resd 1
    .migrations     resd 1
    .mem_rss        resq 1
    .mem_vms        resq 1
    .mem_shared     resq 1
    .mem_private    resq 1
    .mem_swap       resq 1
    .mem_peak_rss   resq 1
    .page_faults_min resq 1
    .page_faults_maj resq 1
    .dio_read_bytes resq 1
    .dio_write_bytes resq 1
    .dio_read_ops   resq 1
    .dio_write_ops  resq 1
    .dio_cancelled  resq 1
    .net_rx_bytes   resq 1
    .net_tx_bytes   resq 1
    .net_rx_packets resq 1
    .net_tx_packets resq 1
    .net_rx_errors  resq 1
    .net_tx_errors  resq 1
    .energy_uj      resq 1
    .cpu_energy_uj  resq 1
    .mem_energy_uj  resq 1
    .io_energy_uj   resq 1
    .state          resb 1
    .nice           resb 1
    .sched_policy   resb 1
    .pad_state      resb 1
    .num_threads    resd 1
    .num_fds        resd 1
    .timestamp_ns   resq 1
    .sample_seq     resq 1
endstruc

%define PROC_SAMPLE_SIZE  (ProcessSample_size)

struc ContainerSample
    .container_id   resq 1
    .name           resb 64
    .image          resb 128
    .state          resb 1
    .cpu_percent    resd 1
    .mem_usage      resq 1
    .mem_limit      resq 1
    .mem_max        resq 1
    .net_rx_bytes   resq 1
    .net_tx_bytes   resq 1
    .blk_read_bytes resq 1
    .blk_write_bytes resq 1
    .pid_count      resd 1
    .pad            resb 12
endstruc

%define CONTAINER_SAMPLE_SIZE  (ContainerSample_size)

struc SystemSample
    .timestamp_ns   resq 1
    .sample_seq     resq 1
    .uptime_ns      resq 1
    .cpu_total_percent resd 1
    .cpu_user_percent  resd 1
    .cpu_kernel_percent resd 1
    .cpu_idle_percent  resd 1
    .cpu_iowait_percent resd 1
    .cpu_irq_percent   resd 1
    .cpu_softirq_percent resd 1
    .cpu_steal_percent resd 1
    .cpu_guest_percent resd 1
    .cpu_per_core      resd MAX_CPUS
    .cpu_freq_mhz      resd MAX_CPUS
    .cpu_idle_ns       resq MAX_CPUS
    .p_core_mask       resq 4
    .e_core_mask       resq 4
    .cpu_load_1m       resd 1
    .cpu_load_5m       resd 1
    .cpu_load_15m      resd 1
    .nr_running        resd 1
    .nr_uninterruptible resd 1
    .mem_total        resq 1
    .mem_free         resq 1
    .mem_available    resq 1
    .mem_used         resq 1
    .mem_cached       resq 1
    .mem_buffers      resq 1
    .mem_shared       resq 1
    .mem_slab         resq 1
    .mem_swap_total   resq 1
    .mem_swap_free    resq 1
    .mem_swap_used    resq 1
    .mem_committed    resq 1
    .mem_compressed   resq 1
    .mem_page_faults  resq 1
    .mem_maj_faults   resq 1
    .mem_pageins      resq 1
    .mem_pageouts     resq 1
    .mem_swapins      resq 1
    .mem_swapouts     resq 1
    .mem_anon         resq 1
    .mem_file         resq 1
    .mem_shmem        resq 1
    .numa_nodes       resd 1
    .numa_stats       resb MAX_NUMA_NODES * NUMA_NODE_STATS_SIZE
    .disk_read_bytes  resq MAX_DISKS
    .disk_write_bytes resq MAX_DISKS
    .disk_read_ops    resq MAX_DISKS
    .disk_write_ops   resq MAX_DISKS
    .disk_read_lat_ns resq MAX_DISKS
    .disk_write_lat_ns resq MAX_DISKS
    .disk_util_pct    resd MAX_DISKS
    .disk_queue_depth resd MAX_DISKS
    .net_rx_bytes     resq MAX_NET_IFACES
    .net_tx_bytes     resq MAX_NET_IFACES
    .net_rx_packets   resq MAX_NET_IFACES
    .net_tx_packets   resq MAX_NET_IFACES
    .net_rx_errors    resq MAX_NET_IFACES
    .net_tx_errors    resq MAX_NET_IFACES
    .net_rx_dropped   resq MAX_NET_IFACES
    .net_tx_dropped   resq MAX_NET_IFACES
    .net_speed_bps    resq MAX_NET_IFACES
    .pkg_power_uv     resq 1
    .dram_power_uv    resq 1
    .gpu_power_uv     resq 1
    .pkg_energy_uj    resq 1
    .dram_energy_uj   resq 1
    .gpu_count        resd 1
    .gpu_util_pct     resd MAX_GPUS
    .gpu_mem_used     resq MAX_GPUS
    .gpu_mem_total    resq MAX_GPUS
    .gpu_temp_c       resd MAX_GPUS
    .gpu_power_w      resd MAX_GPUS
    .temp_millicelsius resd MAX_THERMAL_ZONES
    .temp_critical     resd MAX_THERMAL_ZONES
    .thermal_pressure  resb 1
    .fan_rpm           resd 8
    .pad_thermal       resb 3
    .container_count  resd 1
endstruc

%define SYS_SAMPLE_SIZE  (SystemSample_size)

struc RingBufferHeader
    .magic          resq 1
    .version        resd 1
    .record_size    resd 1
    .capacity       resq 1
    .head           resq 1
    .tail           resq 1
    .count          resq 1
    .overruns       resq 1
    .flags          resq 1
    .pad            resq 1
endstruc

%define RING_HEADER_SIZE  (RingBufferHeader_size)

struc FlightRecorderHeader
    .magic          resq 1
    .version        resd 1
    .record_size    resd 1
    .capacity       resq 1
    .head           resq 1
    .tail           resq 1
    .count          resq 1
    .start_time_ns  resq 1
    .end_time_ns    resq 1
    .flags          resq 1
    .trigger_reason resd 1
    .overruns       resq 1
    .pad            resq 1
endstruc

%define FLIGHT_HEADER_SIZE  (FlightRecorderHeader_size)

struc DiskDeviceInfo
    .name           resb 64
    .model          resb 64
    .serial         resb 32
    .firmware       resb 32
    .size_bytes     resq 1
    .sector_size    resd 1
    .physical_sector resd 1
    .rotation_rate  resd 1
    .interface      resb 1
    .numa_node      resd 1
    .flags          resd 1
    .pad            resb 12
endstruc

%define DISK_DEVICE_INFO_SIZE (DiskDeviceInfo_size)

struc NetInterfaceInfo
    .name           resb 32
    .mac_addr       resb 6
    .pad_mac        resb 2
    .mtu            resd 1
    .speed_bps      resq 1
    .duplex         resb 1
    .link_up        resb 1
    .numa_node      resd 1
    .driver_name    resb 32
    .flags          resd 1
    .pad            resb 12
endstruc

%define NET_IFACE_INFO_SIZE (NetInterfaceInfo_size)

struc ThermalZoneInfo
    .name           resb 32
    .temp_millicelsius resd 1
    .trip_passive   resd 1
    .trip_active    resd 1
    .trip_hot       resd 1
    .trip_critical  resd 1
    .type           resb 1
    .pad            resb 3
endstruc

%define THERMAL_ZONE_INFO_SIZE (ThermalZoneInfo_size)

struc GpuInfo
    .gpu_id         resd 1
    .vendor         resd 1
    .name           resb 64
    .driver_version resb 64
    .cuda_version   resb 32
    .vbios_version  resb 32
    .total_memory   resq 1
    .pci_bus_id     resb 16
    .pad            resb 4
endstruc

%define GPU_INFO_SIZE (GpuInfo_size)

struc AggregatedStats
    .window_ns      resq 1
    .sample_count   resq 1
    .start_ns       resq 1
    .end_ns         resq 1
    .cpu_min        resd 1
    .cpu_max        resd 1
    .cpu_avg        resd 1
    .cpu_sum        resq 1
    .cpu_sum_sq     resq 1
    .mem_min        resq 1
    .mem_max        resq 1
    .mem_avg        resq 1
    .disk_read_max  resq 1
    .disk_write_max resq 1
    .net_rx_max     resq 1
    .net_tx_max     resq 1
    .temp_max       resd 1
    .power_max_uv   resq 1
endstruc

%define AGG_STATS_SIZE  (AggregatedStats_size)

struc AlertRule
    .rule_id        resq 1
    .name           resb 64
    .metric         resb 32
    .threshold      resq 1
    .operator       resb 1
    .severity       resb 1
    .enabled        resb 1
    .pad            resb 5
    .duration_ns    resq 1
    .last_triggered resq 1
    .trigger_count  resq 1
endstruc

%define ALERT_RULE_SIZE  (AlertRule_size)

struc AlertEvent
    .event_id       resq 1
    .rule_id        resq 1
    .timestamp_ns   resq 1
    .severity       resb 1
    .metric         resb 32
    .current_value  resq 1
    .threshold      resq 1
    .message        resb 256
    .resolved       resb 1
    .resolved_at    resq 1
    .pad            resb 7
endstruc

%define ALERT_EVENT_SIZE  (AlertEvent_size)

struc AuditEntry
    .entry_id       resq 1
    .timestamp_ns   resq 1
    .user_id        resd 1
    .action         resd 1
    .target_type    resb 1
    .target_id      resq 1
    .result         resd 1
    .details        resb 256
    .source_ip      resb 16
    .pad            resb 6
endstruc

%define AUDIT_ENTRY_SIZE  (AuditEntry_size)

struc GlobalDiskStats
    .read_bytes       resq MAX_DISKS
    .write_bytes      resq MAX_DISKS
    .read_ops         resq MAX_DISKS
    .write_ops        resq MAX_DISKS
    .read_latency_ns  resq MAX_DISKS
    .write_latency_ns resq MAX_DISKS
    .flush_ops        resq MAX_DISKS
    .discard_ops      resq MAX_DISKS
    .discard_bytes    resq MAX_DISKS
    .queue_depth      resd MAX_DISKS
    .util_sum         resq MAX_DISKS
    .last_update_ns   resq MAX_DISKS
    .device_info      resb MAX_DISKS * DISK_DEVICE_INFO_SIZE
endstruc

%define GLOBAL_DISK_STATS_SIZE (GlobalDiskStats_size)

struc GlobalNetStats
    .rx_bytes       resq MAX_NET_IFACES
    .tx_bytes       resq MAX_NET_IFACES
    .rx_packets     resq MAX_NET_IFACES
    .tx_packets     resq MAX_NET_IFACES
    .rx_errors      resq MAX_NET_IFACES
    .tx_errors      resq MAX_NET_IFACES
    .rx_dropped     resq MAX_NET_IFACES
    .tx_dropped     resq MAX_NET_IFACES
    .rx_fifo_err    resq MAX_NET_IFACES
    .tx_fifo_err    resq MAX_NET_IFACES
    .rx_frame_err   resq MAX_NET_IFACES
    .tx_carrier_err resq MAX_NET_IFACES
    .rx_compressed  resq MAX_NET_IFACES
    .tx_compressed  resq MAX_NET_IFACES
    .rx_multicast   resq MAX_NET_IFACES
    .collisions     resq MAX_NET_IFACES
    .speed_bps      resq MAX_NET_IFACES
    .duplex         resb MAX_NET_IFACES
    .link_up        resb MAX_NET_IFACES
    .pad            resw MAX_NET_IFACES
    .iface_info     resb MAX_NET_IFACES * NET_IFACE_INFO_SIZE
endstruc

%define GLOBAL_NET_STATS_SIZE (GlobalNetStats_size)

struc GlobalThermalState
    .zone_count           resd 1
    .zone_info            resb MAX_THERMAL_ZONES * THERMAL_ZONE_INFO_SIZE
    .temps_millicelsius   resd MAX_THERMAL_ZONES
    .trip_passive         resd MAX_THERMAL_ZONES
    .trip_active          resd MAX_THERMAL_ZONES
    .trip_hot             resd MAX_THERMAL_ZONES
    .trip_critical        resd MAX_THERMAL_ZONES
    .pressure             resb 1
    .fan_count            resd 1
    .fan_rpm              resd 8
    .fan_target_rpm       resd 8
    .last_update_ns       resq 1
endstruc

%define GLOBAL_THERMAL_STATE_SIZE (GlobalThermalState_size)

struc EnergyState
    .rapl_available       resb 1
    .power_units          resb 1
    .energy_units         resb 1
    .time_units           resb 1
    .pad1                 resb 4
    .pkg_energy_uj        resq 1
    .dram_energy_uj       resq 1
    .pp0_energy_uj        resq 1
    .pp1_energy_uj        resq 1
    .pkg_power_uv         resq 1
    .dram_power_uv        resq 1
    .pp0_power_uv         resq 1
    .pp1_power_uv         resq 1
    .last_read_ns         resq 1
    .pkg_delta_uj         resq 1
    .dram_delta_uj        resq 1
    .pp0_delta_uj         resq 1
    .pp1_delta_uj         resq 1
    .battery_present      resb 1
    .pad2                 resb 7
    .battery_capacity_uvh resq 1
    .battery_charge_uvh   resq 1
    .battery_voltage_uv   resq 1
    .battery_current_ua   resq 1
    .battery_status       resb 1
    .pad3                 resb 7
endstruc

%define ENERGY_STATE_SIZE (EnergyState_size)

struc GlobalGpuState
    .gpu_count        resd 1
    .gpu_info         resb MAX_GPUS * GPU_INFO_SIZE
    .gpu_util         resd MAX_GPUS
    .gpu_mem_used     resq MAX_GPUS
    .gpu_mem_total    resq MAX_GPUS
    .gpu_temp         resd MAX_GPUS
    .gpu_power        resd MAX_GPUS
endstruc

%define GLOBAL_GPU_STATE_SIZE (GlobalGpuState_size)

%endif