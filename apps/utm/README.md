# UTM Enterprise - Utakarsha Task Manager Enterprise Edition
> Enterprise-grade, pure-assembly task manager and system observability platform.
> Version 2.0

## Overview

UTM Enterprise is a native, pure-x86_64 assembly task manager and system observability
platform designed for enterprise datacenter production environments. Unlike consumer-grade
task managers (Windows Task Manager, htop, btop), UTM Enterprise is built entirely in
assembly language with no C runtime, no Electron, no web views, and no interpreted languages.

## Key Features

### Core Monitoring
- **Process & Thread Tracking** - Full process hierarchy with PID reuse protection
- **CPU Accounting** - Per-core, per-thread, P-state/C-state tracking
- **Memory Statistics** - RSS, VMS, swap, page faults, NUMA locality
- **Disk I/O** - Per-device read/write bytes, ops, latency, queue depth
- **Network I/O** - Per-interface packets, bytes, errors, dropped
- **Energy/Power** - Intel RAPL, AMD SMR, battery monitoring
- **Thermal** - CPU/GPU/package temperatures, fan speeds, thermal pressure
- **GPU Metrics** - NVIDIA NVML, AMD ROCm, Intel GPU monitoring

### Enterprise Features
- **Container Awareness** - Docker, containerd, Kubernetes integration
- **cgroup v1/v2** - Hierarchy tracking and resource attribution
- **NUMA Support** - Multi-node memory locality tracking
- **Heterogeneous CPUs** - P-core/E-core distinction
- **Flight Recorder** - Circular buffer at 60Hz with post-mortem replay
- **Alerting Engine** - Threshold-based with escalation
- **RBAC** - Read-only, Operator, Admin, Superuser roles
- **Audit Logging** - All actions logged with user, timestamp, target
- **Mutual TLS** - Secure API and remote connections
- **Prometheus/OpenMetrics** - Standard metrics export
- **REST API** - Programmable access to all metrics
- **CLI** - Interactive command-line interface
- **Text UI** - Phosphor-themed terminal interface

### Performance Targets
| Metric | Target |
|--------|--------|
| Collector CPU overhead | < 0.1% at 60Hz |
| Per-sample latency | < 500ns worst-case |
| Ring buffer throughput | > 1M records/sec |
| Memory footprint | < 2 MB daemon |
| API latency (p99) | < 1ms |

## Build

```bash
cd utm_enterprise_v2
./build.sh build        # Build all components
./build.sh install /opt/utm   # Install to rootfs
```

## Run

```bash
# Collector daemon (requires kernel with syscall handlers at 0x100+)
/opt/utm/usr/bin/utm-collector

# Text UI
/opt/utm/usr/bin/utm-ui

# REST API
/opt/utm/usr/bin/utm-api

# CLI
/opt/utm/usr/bin/utm_cli version
/opt/utm/usr/bin/utm_cli list
/opt/utm/usr/bin/utm_cli sample
```

## Architecture

See `ARCHITECTURE.md` for complete architecture documentation.

## Kernel Integration

To integrate UTM Enterprise with your kernel:

1. Register syscall handler at 0x100+
2. Call accounting hooks from scheduler:
   - `utm_cpu_account_thread_tick()` on each tick
   - `cpu_account_idle()` in idle loop
   - `mem_account_page_fault()` on page faults
   - `disk_account_io()` in block layer
   - `net_account_packet()` in network stack
3. Initialize subsystems early in boot:
   - `proc_table_init()`
   - `cpu_accounting_init()`
   - `mem_stats_init()`
   - `disk_accounting_init()`
   - `net_accounting_init()`
   - `energy_init()`
   - `thermal_init()`
   - `flight_rec_init()`
4. Start utm-collector in userspace init

## License

Designed for UTM - Your Custom Assembly Operating System.

*Built for UTM - Your Custom Assembly Operating System (Tattva OS)*