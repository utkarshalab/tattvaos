# Utkarsha–Canvas Contract

**Every Utkarsha kernel service Canvas requires, with exact function signatures, memory layouts, and error codes.**

This is the **source of truth** for the Utkarsha kernel team. Canvas will not work without these.

---

## 1. Service Overview

| Service | Canvas Module | Purpose |
|---------|---------------|---------|
| Memory Regions | `ut_mem` | Arenas, DMA-able scanout buffers, shared rings |
| Monotonic Clock | `ut_time` | Frame scheduling, timestamps, timers |
| Console/Serial Log | `ut_log` | Debug output, test results, panic messages |
| Entropy | `ut_entropy` | Capability tokens, siphash keys |
| Wait/Yield | `ut_wait` | Event loop, vblank wait, client ping |
| Task Creation | `ut_task` | Worker tasks, client processes |
| IRQ Registration | `ut_irq` | Vblank, input, channel wakeups |
| Input Events | `ut_input` | Keyboard, mouse, touch from Utkarsha drivers |
| Filesystem Read | `ut_fs` | Config, fonts, cursors, wallpapers, ICC |
| PCI Enumeration | `ut_pci` | GPU/display controller discovery |
| MMIO/DMA Mapping | `ut_mmio` | Display engine registers, GPU command rings |
| Power Events | `ut_power` | Suspend/resume, display hotplug |
| Network + TLS | `ut_net` | Remote display (RFB/CRP) |

---

## 2. Calling Convention

All Utkarsha services use **Utkarsha ABI** (defined in `inc/abi.inc`):
- **Registers**: `rdi, rsi, rdx, rcx, r8, r9` for first 6 args; rest on stack
- **Return**: `rax` (u64), `rdx` (u64 for 128-bit)
- **Preserved**: `rbx, rbp, r12-r15` callee-saved
- **Clobbered**: `rax, rcx, rdx, rsi, rdi, r8-r11`
- **Errors**: Negative `rax` = `-Errno` (see `inc/errors.inc`)

---

## 3. Service Specifications

### 3.1 Memory Regions (`ut_mem.asm`)

```asm
; Allocate a memory region
;   in:  rdi = size (bytes, page-aligned)
;        rsi = flags (bitmask: MEM_DMA=1, MEM_EXEC=2, MEM_UNCACHED=4, MEM_SHARED=8)
;   out: rax = virtual address (page-aligned)  OR  negative error
;        rdx = physical address (if MEM_DMA)
;        r8  = region handle (for free/resize)
ut_mem_alloc

; Free a region
;   in:  rdi = region handle
;   out: rax = 0 OK, negative error
ut_mem_free

; Resize region (may move)
;   in:  rdi = region handle, rsi = new_size
;   out: rax = new virtual address, rdx = new physical (if DMA), negative error
ut_mem_resize

; Map physical pages into region (for DMA buffers from GPU)
;   in:  rdi = region handle, rsi = phys_addr, rdx = count, rcx = offset_in_region
;   out: rax = 0 OK, negative error
ut_mem_map_phys

; Get region info
;   in:  rdi = region handle
;   out: rax = vaddr, rdx = paddr (or 0), r8 = size, r9 = flags
ut_mem_info
```

**Errors**: `ENOMEM`, `EINVAL`, `EACCES`, `ENXIO`

---

### 3.2 Monotonic Clock (`ut_time.asm`)

```asm
; Current monotonic time in nanoseconds
;   out: rax = ns since boot (u64, never wraps in practice)
ut_time_now_ns

; Current monotonic time in microseconds
;   out: rax = us since boot
ut_time_now_us

; Current monotonic time in milliseconds
;   out: rax = ms since boot
ut_time_now_ms

; High-resolution timestamp (TSC-based, for frame timeline)
;   out: rax = tsc_ticks, rdx = tsc_hz (constant)
ut_time_tsc

; Sleep until deadline (ns)
;   in:  rdi = deadline_ns (absolute)
;   out: rax = 0 woke on time, ETIMEDOUT if past, EINTR if interrupted
ut_time_sleep_until

; Sleep for duration (ns)
;   in:  rdi = duration_ns
;   out: rax = 0 OK, EINTR if interrupted
ut_time_sleep_ns

; Register one-shot timer
;   in:  rdi = deadline_ns, rsi = callback_fn, rdx = user_data
;   out: rax = timer_id (>0), negative error
ut_timer_register

; Cancel timer
;   in:  rdi = timer_id
;   out: rax = 0 OK, EINVAL if not found
ut_timer_cancel
```

**Notes**: 
- `ut_time_now_ns` must be **lock-free, wait-free** — used in hot paths
- Timer callbacks run in interrupt context → **no blocking, no locks**
- TSC frequency constant across cores (invariant TSC required)

---

### 3.3 Console/Serial Log (`ut_log.asm`)

```asm
; Write bytes to console/serial (blocking, but fast)
;   in:  rdi = buffer, rsi = length
;   out: rax = bytes written (== length on success), negative error
ut_log_write

; Write formatted (printf-style, limited: %s %d %x %p %c %% )
;   in:  rdi = format string, rsi... = args
;   out: rax = chars written
ut_log_printf

; Set log level filter (0=none, 1=error, 2=warn, 3=info, 4=debug, 5=trace)
;   in:  rdi = level
ut_log_set_level

; Get current log level
;   out: rax = level
ut_log_get_level

; Flush any buffered output
;   out: rax = 0 OK
ut_log_flush
```

**Used by**: `inc/log.asm` leveled logger, test harness, panic handler

---

### 3.4 Entropy (`ut_entropy.asm`)

```asm
; Fill buffer with cryptographic random bytes
;   in:  rdi = buffer, rsi = length
;   out: rax = 0 OK, negative error (EAGAIN if pool low)
ut_entropy_get

; Get 64 random bits (fast path for tokens)
;   out: rax = u64 random
ut_entropy_u64

; Get 256-bit key for siphash (for capability tokens)
;   in:  rdi = buffer[32]
;   out: rax = 0 OK
ut_entropy_siphash_key
```

**Source**: Hardware RNG (RDRAND/RDSEED) + interrupt timing + boot entropy

---

### 3.5 Wait/Yield (`ut_wait.asm`)

```asm
; Wait for any of multiple event sources (like poll/epoll but simpler)
;   in:  rdi = waitset handle, rsi = deadline_ns (0 = infinite, -1 = poll)
;   out: rax = triggered_event_mask, negative error
ut_wait_wait

; Create waitset
;   out: rax = waitset_handle, negative error
ut_waitset_create

; Add event source to waitset
;   in:  rdi = waitset, rsi = event_type, rdx = source_id, rcx = trigger_mask
;   out: rax = 0 OK
; event_type: WAIT_IRQ=1, WAIT_CHANNEL=2, WAIT_TIMER=3, WAIT_TASK=4
ut_waitset_add

; Remove event source
;   in:  rdi = waitset, rsi = event_type, rdx = source_id
;   out: rax = 0 OK
ut_waitset_remove

; Yield CPU to other tasks (cooperative)
;   out: rax = 0
ut_wait_yield

; Wake specific task (by task_id from ut_task)
;   in:  rdi = task_id
;   out: rax = 0 OK, ESRCH if not found
ut_wait_wake_task
```

**Canvas uses**: Single waitset per event loop iteration; waits on IRQ + channel + timer events

---

### 3.6 Task Creation (`ut_task.asm`)

```asm
; Spawn new task (client process or worker)
;   in:  rdi = entry_fn, rsi = arg, rdx = stack_size, rcx = flags
;        r8 = name_ptr, r9 = name_len
;   out: rax = task_id (>0), negative error
; flags: TASK_USER=1 (ring3 if HW domains), TASK_KERNEL=0 (ring0), TASK_NO_FPU=2
ut_task_spawn

; Exit current task
;   in:  rdi = exit_code
;   (does not return)
ut_task_exit

; Wait for task exit
;   in:  rdi = task_id
;   out: rax = exit_code, negative error
ut_task_wait

; Get current task ID
;   out: rax = task_id
ut_task_self

; Set task priority (0=low, 127=normal, 255=high)
;   in:  rdi = task_id, rsi = priority
;   out: rax = 0 OK
ut_task_set_priority

; Pin task to CPU core
;   in:  rdi = task_id, rsi = cpu_id
;   out: rax = 0 OK
ut_task_pin
```

**Canvas usage**:
- Main canvasd task (pinned to core 0)
- Per-client tasks (if HW domains later; currently all in one address space)
- Render workers (optional, for parallel composition)

---

### 3.7 IRQ Registration (`ut_irq.asm`)

```asm
; Register IRQ handler
;   in:  rdi = irq_number, rsi = handler_fn, rdx = user_data, rcx = flags
;   out: rax = irq_handle (>0), negative error
; flags: IRQ_SHARED=1, IRQ_LEVEL=2, IRQ_EDGE=4
ut_irq_register

; Unregister IRQ handler
;   in:  rdi = irq_handle
;   out: rax = 0 OK
ut_irq_unregister

; Enable IRQ
;   in:  rdi = irq_handle
;   out: rax = 0 OK
ut_irq_enable

; Disable IRQ
;   in:  rdi = irq_handle
;   out: rax = 0 OK
ut_irq_disable

; Get IRQ affinity (which CPUs can handle it)
;   in:  rdi = irq_number
;   out: rax = cpu_mask
ut_irq_affinity

; Set IRQ affinity
;   in:  rdi = irq_number, rsi = cpu_mask
;   out: rax = 0 OK
ut_irq_set_affinity
```

**Canvas IRQs**:
- Display vblank (per CRTC) — `ut_irq_register` in `ut_vblank.asm`
- Input device interrupts — `ut_input.asm` source
- Channel wakeup (IPI or eventfd-like) — `ut_wait` integration
- GPU command completion — C24

---

### 3.8 Input Events (`ut_input.asm`)

```asm
; Input event from Utkarsha HID/PS2/USB drivers
struct InputEvent {
  type: u32,      ; EV_KEY=1, EV_REL=2, EV_ABS=3, EV_SW=4, EV_MSC=5
  code: u32,      ; KEY_*, REL_*, ABS_*, SW_*
  value: i32,     ; press/release, relative delta, absolute position
  time_ns: u64,   ; monotonic timestamp
  device_id: u32  ; Utkarsha device ID
}

; Register input event callback (called from IRQ context!)
;   in:  rdi = callback_fn(event: *InputEvent), rsi = user_data
;   out: rax = 0 OK
ut_input_register_callback

; Unregister callback
;   out: rax = 0 OK
ut_input_unregister_callback

; Get device info
;   in:  rdi = device_id
;   out: rax = dev_info_ptr (see below), negative error
ut_input_device_info

; Device info struct (read-only)
struct InputDevInfo {
  id: u32,
  name: *u8,      ; null-terminated
  bus: u32,       ; BUS_USB=3, BUS_PS2=4, BUS_I2C=5, BUS_PLATFORM=6
  vendor: u16,
  product: u16,
  version: u16,
  caps: u64,      ; bitmask: CAP_KEYBOARD=1, CAP_POINTER=2, CAP_TOUCH=4, CAP_TABLET=8
  max_x: i32,     ; for ABS
  max_y: i32,
  res_x: u32,     ; resolution (units/mm)
  res_y: u32
}

; Grab device exclusively (for direct scanout client, kiosk)
;   in:  rdi = device_id, rsi = grab (1=grab, 0=release)
;   out: rax = 0 OK, EBUSY if already grabbed
ut_input_grab
```

**Notes**:
- Callback **must be fast** — no allocation, no locks, just push to SPSC ring
- Canvas `source_ut.asm` converts to internal `Event` struct (24 bytes)
- Device IDs stable across reboots (from ACPI/PCI path)

---

### 3.9 Filesystem Read (`ut_fs.asm`)

```asm
; Read entire file into buffer (TVFS is read-only for Canvas)
;   in:  rdi = path (null-terminated), rsi = out_buffer, rdx = buffer_size
;   out: rax = bytes_read (== file size), negative error
;        if buffer too small: returns required size in rdx, ENOBUFS
ut_fs_read

; Get file size only
;   in:  rdi = path
;   out: rax = size, negative error
ut_fs_stat

; List directory (for keymaps, cursors, fonts)
;   in:  rdi = path, rsi = callback_fn(entry_name, is_dir, user_data), rdx = user_data
;   out: rax = entry_count, negative error
ut_fs_list

; Open file for streaming (large files: wallpapers, fonts)
;   in:  rdi = path
;   out: rax = file_handle, negative error
ut_fs_open

; Read from open file
;   in:  rdi = file_handle, rsi = buffer, rdx = length, rcx = offset
;   out: rax = bytes_read, negative error
ut_fs_pread

; Close file
;   in:  rdi = file_handle
;   out: rax = 0 OK
ut_fs_close
```

**Paths Canvas reads**:
- `/etc/canvas/canvas.conf`, `outputs.conf`, `seats.conf`, `policy.conf`, `rules.conf`
- `/usr/share/canvas/profiles/*.profile`
- `/usr/share/canvas/keymaps/*.km`, `compose.tbl`
- `/usr/share/canvas/fonts/*.ttf`
- `/usr/share/canvas/cursors/*.png`
- `/usr/share/canvas/wallpapers/*.png`
- `/usr/share/canvas/icc/*.icc`

---

### 3.10 PCI Enumeration (`ut_pci.asm`)

```asm
; PCI device info
struct PciDevice {
  bus: u8, dev: u8, fn: u8,
  vendor_id: u16, device_id: u16,
  class_code: u8, subclass: u8, prog_if: u8,
  revision: u8,
  bar: [6] PciBar,
  irq: u8
}
struct PciBar { type: u32, base: u64, size: u64 } ; type: MEM=0, IO=1, PREFETCH=8

; Iterate all PCI devices
;   in:  rdi = callback_fn(dev: *PciDevice, user_data), rsi = user_data
;   out: rax = device_count
ut_pci_for_each

; Find device by class (e.g., DISPLAY=0x03, GPU=0x0380)
;   in:  rdi = class_code, rsi = subclass
;   out: rax = dev_ptr (first match), 0 if none
ut_pci_find_class

; Read PCI config space (dword)
;   in:  rdi = dev_ptr, rsi = offset (0-255)
;   out: rax = value, negative error
ut_pci_config_read_dword

; Write PCI config space (dword)
;   in:  rdi = dev_ptr, rsi = offset, rdx = value
;   out: rax = 0 OK
ut_pci_config_write_dword

; Enable device (memory/IO/BusMaster)
;   in:  rdi = dev_ptr
;   out: rax = 0 OK
ut_pci_enable_device

; Disable device
;   in:  rdi = dev_ptr
;   out: rax = 0 OK
ut_pci_disable_device
```

**Canvas usage**: `src/backend/native_pci.asm` discovers display controllers (VGA class 0x0300, HDMI/DP audio 0x0403, etc.)

---

### 3.11 MMIO/DMA Mapping (`ut_mmio.asm`)

```asm
; Map PCI BAR or physical range to virtual address
;   in:  rdi = phys_addr, rsi = size, rdx = flags (MMIO_UNCACHED=1, MMIO_WC=2, MMIO_DMA=4)
;   out: rax = virtual address, negative error
ut_mmio_map

; Unmap MMIO region
;   in:  rdi = vaddr, rsi = size
;   out: rax = 0 OK
ut_mmio_unmap

; Allocate DMA-coherent buffer (for GPU command rings, scanout)
;   in:  rdi = size, rsi = alignment (power of 2)
;   out: rax = cpu_vaddr, rdx = dma_addr (device physical), r8 = handle
ut_dma_alloc

; Free DMA buffer
;   in:  rdi = dma_handle
;   out: rax = 0 OK
ut_dma_free

; Map DMA buffer into device address space (for GPU page tables)
;   in:  rdi = dma_handle, rsi = device_iommu_domain
;   out: rax = device_addr, negative error
ut_dma_map_device

; Sync DMA buffer (CPU ↔ device)
;   in:  rdi = dma_handle, rsi = offset, rdx = length, rcx = dir (TO_DEVICE=1, FROM_DEVICE=2)
;   out: rax = 0 OK
ut_dma_sync
```

**Critical for**: Native backend (display engine registers), GPU command rings (C24), scanout buffers

---

### 3.12 Power Events (`ut_power.asm`)

```asm
; Power event types
enum PowerEvent { SUSPEND=1, RESUME=2, HIBERNATE=3, LOW_BATTERY=4, AC_CHANGE=5 }

; Register power event callback
;   in:  rdi = callback_fn(event: PowerEvent, user_data), rsi = user_data
;   out: rax = 0 OK
ut_power_register_callback

; Unregister
;   out: rax = 0 OK
ut_power_unregister_callback

; Request suspend inhibit (for idle inhibit protocol)
;   in:  rdi = reason_string, rsi = reason_len
;   out: rax = inhibit_handle, negative error
ut_power_inhibit_suspend

; Release suspend inhibit
;   in:  rdi = inhibit_handle
;   out: rax = 0 OK
ut_power_uninhibit_suspend

; Get battery status
;   out: rax = percent (0-100), rdx = charging (1=yes), r8 = time_remaining_sec
ut_power_battery_status
```

**Canvas usage**: Session lock on suspend, buffer preservation, display re-init on resume

---

### 3.13 Network + TLS (`ut_net.asm`)

```asm
; TLS 1.3 connection (for RFB/CRP remote display)
struct TlsConn { opaque }

; Listen on TCP port with TLS
;   in:  rdi = port, rsi = cert_pem, rdx = cert_len, rcx = key_pem, r8 = key_len
;   out: rax = listener_handle, negative error
ut_tls_listen

; Accept TLS connection
;   in:  rdi = listener, rsi = timeout_ns
;   out: rax = conn_handle, negative error (EAGAIN if timeout)
ut_tls_accept

; Connect TLS client
;   in:  rdi = ip_addr (u32 BE), rsi = port, rdx = server_name (SNI), rcx = ca_pem, r8 = ca_len
;   out: rax = conn_handle, negative error
ut_tls_connect

; Read from TLS connection
;   in:  rdi = conn, rsi = buffer, rdx = length
;   out: rax = bytes_read, negative error (ETIMEDOUT, ECONNRESET)
ut_tls_read

; Write to TLS connection
;   in:  rdi = conn, rsi = buffer, rdx = length
;   out: rax = bytes_written, negative error
ut_tls_write

; Close TLS connection
;   in:  rdi = conn
;   out: rax = 0 OK
ut_tls_close

; Get peer certificate info
;   in:  rdi = conn
;   out: rax = cert_info_ptr
ut_tls_peer_cert
```

**Canvas usage**: `src/remote/rfb_tls.asm`, `src/remote/crp_server.asm`

---

## 4. Error Codes (`inc/errors.inc`)

```
ESUCCESS    = 0
EINVAL      = -1
ENOMEM      = -2
EACCES      = -3
EBUSY       = -4
EEXIST      = -5
ENOENT      = -6
ENOSPC      = -7
ENOTSUP     = -8
EIO         = -9
ETIMEDOUT   = -10
EAGAIN      = -11
EINTR       = -12
ENXIO       = -13
EPERM       = -14
ENOSYS      = -15
ECONNRESET  = -16
ENOBUFS     = -17
ERANGE      = -18
EOVERFLOW   = -19
```

---

## 5. Bootstrap Sequence

Utkarsha must provide these **before** Canvas init:

1. **Early**: `ut_log_write` (serial output for boot messages)
2. **Early**: `ut_mem_alloc` (for Canvas initial arena)
3. **Early**: `ut_time_now_ns` (for init timing)
4. **Init**: `ut_entropy_get` (for first capability tokens)
5. **Init**: `ut_fs_read` (load `canvas.conf`, profiles, keymaps)
6. **Init**: `ut_pci_for_each` (discover display/GPU)
7. **Init**: `ut_mmio_map` (map display engine BARs)
8. **Init**: `ut_irq_register` (vblank, input)
8. **Init**: `ut_task_spawn` (if workers needed)
9. **Runtime**: `ut_wait_wait` (event loop), `ut_dma_alloc` (scanout buffers)

---

## 6. Hardware Requirements (Minimum)

| Feature | Required | Notes |
|---------|----------|-------|
| x86-64 | Yes | Long mode, SSE2 minimum |
| Invariant TSC | Yes | For `ut_time_tsc` |
| RDRAND/RDSEED | Yes | For `ut_entropy` |
| APIC/MSI | Yes | For `ut_irq` |
| PCIe | Yes | For display/GPU discovery |
| IOMMU (VT-d/AMD-Vi) | Preferred | For DMA isolation (C24) |
| UEFI GOP or VBE | Yes | Boot framebuffer for `fb_linear` |
| Serial port (16550) | Yes | `ut_log` output |

---

## 7. Versioning

| Contract Version | Canvas Phases | Utkarsha Kernel Min Version |
|------------------|---------------|---------------------------|
| 1.0 | C0–C10 | 0.1 |
| 1.1 | C11–C20 | 0.2 (adds `ut_power`, `ut_net`) |
| 1.2 | C21–C33 | 0.3 (adds IOMMU, GPU reset) |

Canvas checks contract version at startup via `ut_version()` (to be added).