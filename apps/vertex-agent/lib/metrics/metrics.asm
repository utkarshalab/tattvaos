%ifndef GUARD_VERTEX_METRICS_ASM
%define GUARD_VERTEX_METRICS_ASM
; =============================================================================
; vertex-agent — Metrics Collector
; =============================================================================
; Collects container/pod/node metrics for CRI stats API
; Uses umetric (native) + unet + uxfs + sched counters
; Exposes via kubelet /stats/summary compatible format
; =============================================================================

[BITS 64]

%include "obs/umetric/umetric.inc"
%include "net/unet/unet.inc"
%include "storage/uxfs/uxfs.inc"
%include "kernel/sched/sched.inc"
%include "lib/ulib/vec.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_metrics_init — Initialize metrics collector
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_metrics_init
vertex_metrics_init:
    push rbx
    push r12

    ; Register umetric metrics
    call vertex_metrics_register

    ; Initialize collection state
    mov rdi, 1024
    call vec_create
    test rax, rax
    jz .fail
    mov [metrics_cache], rax

    pop r12
    pop rbx
    mov rax, 1
    ret

.fail:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_register — Register all metrics with umetric
; -----------------------------------------------------------------------------
vertex_metrics_register:
    push rbx
    push r12

    ; Container CPU
    mov rdi, metric_container_cpu_seconds_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container CPU time in seconds"
    call umetric_register

    ; Container Memory
    mov rdi, metric_container_memory_usage_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Container memory usage in bytes"
    call umetric_register

    mov rdi, metric_container_memory_limit_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Container memory limit in bytes"
    call umetric_register

    mov rdi, metric_container_memory_rss_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Container RSS memory in bytes"
    call umetric_register

    mov rdi, metric_container_memory_cache_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Container cache memory in bytes"
    call umetric_register

    ; Container Network
    mov rdi, metric_container_network_rx_bytes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container network receive bytes"
    call umetric_register

    mov rdi, metric_container_network_tx_bytes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container network transmit bytes"
    call umetric_register

    mov rdi, metric_container_network_rx_packets_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container network receive packets"
    call umetric_register

    mov rdi, metric_container_network_tx_packets_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container network transmit packets"
    call umetric_register

    mov rdi, metric_container_network_rx_errors_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container network receive errors"
    call umetric_register

    mov rdi, metric_container_network_tx_errors_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container network transmit errors"
    call umetric_register

    ; Container Filesystem
    mov rdi, metric_container_fs_reads_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container filesystem reads"
    call umetric_register

    mov rdi, metric_container_fs_writes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container filesystem writes"
    call umetric_register

    mov rdi, metric_container_fs_read_bytes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container filesystem read bytes"
    call umetric_register

    mov rdi, metric_container_fs_write_bytes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Container filesystem write bytes"
    call umetric_register

    mov rdi, metric_container_fs_usage_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Container filesystem usage bytes"
    call umetric_register

    mov rdi, metric_container_fs_limit_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Container filesystem limit bytes"
    call umetric_register

    mov rdi, metric_container_fs_inodes_usage
    mov rsi, METRIC_GAUGE
    mov rdx, "Container filesystem inodes usage"
    call umetric_register

    mov rdi, metric_container_fs_inodes_limit
    mov rsi, METRIC_GAUGE
    mov rdx, "Container filesystem inodes limit"
    call umetric_register

    ; Pod-level (aggregated)
    mov rdi, metric_pod_cpu_seconds_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Pod CPU time in seconds"
    call umetric_register

    mov rdi, metric_pod_memory_usage_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Pod memory usage in bytes"
    call umetric_register

    mov rdi, metric_pod_network_rx_bytes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Pod network receive bytes"
    call umetric_register

    mov rdi, metric_pod_network_tx_bytes_total
    mov rsi, METRIC_COUNTER
    mov rdx, "Pod network transmit bytes"
    call umetric_register

    ; Node-level
    mov rdi, metric_node_cpu_capacity_cores
    mov rsi, METRIC_GAUGE
    mov rdx, "Node CPU capacity in cores"
    call umetric_register

    mov rdi, metric_node_memory_capacity_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Node memory capacity in bytes"
    call umetric_register

    mov rdi, metric_node_pods_capacity
    mov rsi, METRIC_GAUGE
    mov rdx, "Node pods capacity"
    call umetric_register

    mov rdi, metric_node_cpu_usage_cores
    mov rsi, METRIC_GAUGE
    mov rdx, "Node CPU usage in cores"
    call umetric_register

    mov rdi, metric_node_memory_usage_bytes
    mov rsi, METRIC_GAUGE
    mov rdx, "Node memory usage in bytes"
    call umetric_register

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_collect — Main collection routine (called periodically)
; -----------------------------------------------------------------------------
global vertex_metrics_collect
vertex_metrics_collect:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Collect container metrics
    call vertex_metrics_collect_containers

    ; 2. Aggregate to pod metrics
    call vertex_metrics_aggregate_pods

    ; 3. Collect node metrics
    call vertex_metrics_collect_node

    ; 4. Update cache for CRI stats API
    call vertex_metrics_update_cache

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_collect_containers — Per-container metrics
; -----------------------------------------------------------------------------
vertex_metrics_collect_containers:
    push rbx
    push r12
    push r13

    mov rdi, [container_map]
    call map_iter_begin

.iter:
    call map_iter_next
    test rax, rax
    jz .done

    mov rbx, rax      ; container_state

    ; Skip if not running
    cmp dword [rbx + container_state.status], CONTAINER_RUNNING
    jne .iter

    ; Get container ID for labels
    mov r12, [rbx + container_state.container_id]
    mov r13, [rbx + container_state.pod_sandbox_id]

    ; CPU: from sched fiber ticks
    mov rdi, [rbx + container_state.fiber_handle]
    call sched_fiber_get_ticks
    ; Convert to seconds, update counter
    mov rdi, metric_container_cpu_seconds_total
    mov rsi, r12
    mov rdx, r13
    call umetric_counter_add

    ; Memory: from mm arena
    mov rdi, [rbx + container_state.fiber_handle]
    call mm_fiber_get_arena_usage
    mov rdi, metric_container_memory_usage_bytes
    mov rsi, r12
    mov rdx, r13
    call umetric_gauge_set

    ; Memory limit
    mov rax, [rbx + container_state.mem_limit_bytes]
    mov rdi, metric_container_memory_limit_bytes
    mov rsi, r12
    mov rdx, r13
    call umetric_gauge_set

    ; Network: from unet netns counters
    mov rdi, [rbx + container_state.netns_handle]
    call unet_namespace_get_counters
    ; Update network metrics
    call vertex_metrics_update_network

    ; Filesystem: from uxfs mount stats
    mov rdi, [rbx + container_state.mntns_handle]
    call uxfs_mount_get_stats
    call vertex_metrics_update_fs

    jmp .iter

.done:
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_aggregate_pods — Sum container metrics to pod level
; -----------------------------------------------------------------------------
vertex_metrics_aggregate_pods:
    push rbx
    push r12
    push r13

    ; Iterate pod sandboxes
    mov rdi, [sandbox_map]
    call map_iter_begin

.iter:
    call map_iter_next
    test rax, rax
    jz .done

    mov rbx, rax      ; sandbox_state
    mov r12, [rbx + sandbox_state.sandbox_id]

    ; Find all containers in this pod
    call vertex_metrics_find_pod_containers
    ; Sum their metrics
    call vertex_metrics_sum_container_metrics

    ; Update pod metrics
    mov rdi, metric_pod_cpu_seconds_total
    mov rsi, r12
    xor rdx, rdx      ; no namespace for pod
    call umetric_gauge_set

    jmp .iter

.done:
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_collect_node — Node-level metrics
; -----------------------------------------------------------------------------
vertex_metrics_collect_node:
    push rbx
    push r12

    ; CPU capacity
    mov rax, [smp_total_cores]
    cvtsi2sd xmm0, rax
    mov rdi, metric_node_cpu_capacity_cores
    call umetric_gauge_set_f64

    ; CPU usage (sum of all fiber ticks across cores)
    call sched_total_ticks
    ; Convert to cores
    mov rdi, metric_node_cpu_usage_cores
    call umetric_gauge_set_f64

    ; Memory capacity
    mov rax, [phys_total_memory]
    mov rdi, metric_node_memory_capacity_bytes
    call umetric_gauge_set

    ; Memory usage
    mov rax, [phys_used_memory]
    mov rdi, metric_node_memory_usage_bytes
    call umetric_gauge_set

    ; Pods capacity
    mov eax, [node_max_pods]
    cvtsi2sd xmm0, rax
    mov rdi, metric_node_pods_capacity
    call umetric_gauge_set_f64

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_get_stats — Get stats for CRI ContainerStats/ListContainerStats
; Inputs: RDI = container_id (or 0 for all), RSI = output buffer
; Returns: RAX = stats pointer (BXP)
; -----------------------------------------------------------------------------
global vertex_metrics_get_stats
vertex_metrics_get_stats:
    push rbx
    push r12
    push r13

    mov r12, rdi      ; container_id (0 = all)
    mov r13, rsi      ; output

    test r12, r12
    jz .all_containers

    ; Single container
    call vertex_metrics_build_container_stats
    jmp .done

.all_containers:
    ; All containers
    call vertex_metrics_build_all_stats

.done:
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_metrics_get_summary — Get node summary for kubelet /stats/summary
; Inputs: RDI = output buffer
; Returns: RAX = summary pointer (BXP)
; -----------------------------------------------------------------------------
global vertex_metrics_get_summary
vertex_metrics_get_summary:
    push rbx
    push r12

    mov r12, rdi

    ; Build summary: node + pods + containers
    call vertex_metrics_build_summary

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Background collector fiber
; -----------------------------------------------------------------------------
vertex_metrics_collector_fiber:
.loop:
    mov rdi, 10000000000      ; 10 seconds
    call mono_sleep_ns
    call vertex_metrics_collect
    jmp .loop


; -----------------------------------------------------------------------------
; Metric name constants
; -----------------------------------------------------------------------------
section .data
align 8

metric_container_cpu_seconds_total:          db "container_cpu_seconds_total", 0
metric_container_memory_usage_bytes:         db "container_memory_usage_bytes", 0
metric_container_memory_limit_bytes:         db "container_memory_limit_bytes", 0
metric_container_memory_rss_bytes:           db "container_memory_rss_bytes", 0
metric_container_memory_cache_bytes:         db "container_memory_cache_bytes", 0

metric_container_network_rx_bytes_total:     db "container_network_receive_bytes_total", 0
metric_container_network_tx_bytes_total:     db "container_network_transmit_bytes_total", 0
metric_container_network_rx_packets_total:   db "container_network_receive_packets_total", 0
metric_container_network_tx_packets_total:   db "container_network_transmit_packets_total", 0
metric_container_network_rx_errors_total:    db "container_network_receive_errors_total", 0
metric_container_network_tx_errors_total:    db "container_network_transmit_errors_total", 0

metric_container_fs_reads_total:             db "container_fs_reads_total", 0
metric_container_fs_writes_total:            db "container_fs_writes_total", 0
metric_container_fs_read_bytes_total:        db "container_fs_read_bytes_total", 0
metric_container_fs_write_bytes_total:       db "container_fs_write_bytes_total", 0
metric_container_fs_usage_bytes:             db "container_fs_usage_bytes", 0
metric_container_fs_limit_bytes:             db "container_fs_limit_bytes", 0
metric_container_fs_inodes_usage:            db "container_fs_inodes_usage", 0
metric_container_fs_inodes_limit:            db "container_fs_inodes_limit", 0

metric_pod_cpu_seconds_total:                db "pod_cpu_seconds_total", 0
metric_pod_memory_usage_bytes:               db "pod_memory_usage_bytes", 0
metric_pod_network_rx_bytes_total:           db "pod_network_receive_bytes_total", 0
metric_pod_network_tx_bytes_total:           db "pod_network_transmit_bytes_total", 0

metric_node_cpu_capacity_cores:              db "node_cpu_capacity_cores", 0
metric_node_memory_capacity_bytes:           db "node_memory_capacity_bytes", 0
metric_node_pods_capacity:                   db "node_pods_capacity", 0
metric_node_cpu_usage_cores:                 db "node_cpu_usage_cores", 0
metric_node_memory_usage_bytes:              db "node_memory_usage_bytes", 0

metrics_cache:                               dq 0

%endif ; GUARD_VERTEX_METRICS_ASM