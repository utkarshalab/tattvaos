; ============================================================================
; Tattva System Call Interface — Canvas Binding
; Every Tattva service Canvas uses, exact syscall numbers and structures
; THIS IS THE CONTRACT — Tattva kernel MUST implement these
; ============================================================================

%ifndef __TATTVA_INC__
%define __TATTVA_INC__

%include "errors.inc"

; ---------------------------------------------------------------------------
; Syscall Numbers (Tattva Kernel ABI)
; ---------------------------------------------------------------------------

; Memory Management
%define SYS_MEM_ALLOC       0x01    ; alloc region
%define SYS_MEM_FREE        0x02    ; free region
%define SYS_MEM_RESIZE      0x03    ; resize region
%define SYS_MEM_MAP_PHYS    0x04    ; map physical pages
%define SYS_MEM_INFO        0x05    ; get region info
%define SYS_MEM_PROTECT     0x06    ; change protection

; Time
%define SYS_TIME_NOW_NS     0x10    ; monotonic ns
%define SYS_TIME_NOW_US     0x11    ; monotonic us
%define SYS_TIME_NOW_MS     0x12    ; monotonic ms
%define SYS_TIME_TSC        0x13    ; TSC ticks + freq
%define SYS_TIME_SLEEP_NS   0x14    ; sleep ns
%define SYS_TIME_SLEEP_UNTIL 0x15   ; sleep until deadline
%define SYS_TIMER_REGISTER  0x16    ; register timer
%define SYS_TIMER_CANCEL    0x17    ; cancel timer

; Logging
%define SYS_LOG_WRITE       0x20    ; write to console/serial
%define SYS_LOG_PRINTF      0x21    ; formatted write
%define SYS_LOG_SET_LEVEL   0x22    ; set log level
%define SYS_LOG_GET_LEVEL   0x23    ; get log level
%define SYS_LOG_FLUSH       0x24    ; flush buffers

; Entropy
%define SYS_ENTROPY_GET     0x30    ; fill buffer with random
%define SYS_ENTROPY_U64     0x31    ; get 64 random bits
%define SYS_ENTROPY_KEY     0x32    ; get siphash key (32 bytes)

; Wait / Yield
%define SYS_WAITSET_CREATE  0x40    ; create waitset
%define SYS_WAITSET_ADD     0x41    ; add event source
%define SYS_WAITSET_REMOVE  0x42    ; remove event source
%define SYS_WAIT_WAIT       0x43    ; wait for events
%define SYS_WAIT_YIELD      0x44    ; yield CPU
%define SYS_WAIT_WAKE_TASK  0x45    ; wake specific task

; Task Management
%define SYS_TASK_SPAWN      0x50    ; spawn task
%define SYS_TASK_EXIT       0x51    ; exit current task
%define SYS_TASK_WAIT       0x52    ; wait for task
%define SYS_TASK_SELF       0x53    ; get current task ID
%define SYS_TASK_SET_PRIO   0x54    ; set priority
%define SYS_TASK_PIN        0x55    ; pin to CPU

; IRQ Management
%define SYS_IRQ_REGISTER    0x60    ; register IRQ handler
%define SYS_IRQ_UNREGISTER  0x61    ; unregister IRQ handler
%define SYS_IRQ_ENABLE      0x62    ; enable IRQ
%define SYS_IRQ_DISABLE     0x63    ; disable IRQ
%define SYS_IRQ_AFFINITY    0x64    ; get affinity
%define SYS_IRQ_SET_AFFINITY 0x65   ; set affinity

; Input Events
%define SYS_INPUT_REGISTER_CB 0x70  ; register input callback
%define SYS_INPUT_UNREGISTER_CB 0x71; unregister callback
%define SYS_INPUT_DEV_INFO  0x72    ; get device info
%define SYS_INPUT_GRAB      0x73    ; grab/release device

; Filesystem (TVFS)
%define SYS_FS_READ         0x80    ; read entire file
%define SYS_FS_STAT         0x81    ; get file size
%define SYS_FS_LIST         0x82    ; list directory
%define SYS_FS_OPEN         0x83    ; open for streaming
%define SYS_FS_PREAD        0x84    ; read from open file
%define SYS_FS_CLOSE        0x85    ; close file
%define SYS_FS_WRITE        0x86    ; append/write streaming file
%define SYS_FS_PWRITE       0x87    ; positional write to open file

; PCI
%define SYS_PCI_FOR_EACH    0x90    ; iterate all devices
%define SYS_PCI_FIND_CLASS  0x91    ; find by class
%define SYS_PCI_CONFIG_READ 0x92    ; read config dword
%define SYS_PCI_CONFIG_WRITE 0x93   ; write config dword
%define SYS_PCI_ENABLE      0x94    ; enable device
%define SYS_PCI_DISABLE     0x95    ; disable device

; MMIO / DMA
%define SYS_MMIO_MAP        0xA0    ; map physical to virtual
%define SYS_MMIO_UNMAP      0xA1    ; unmap
%define SYS_DMA_ALLOC       0xA2    ; allocate DMA buffer
%define SYS_DMA_FREE        0xA3    ; free DMA buffer
%define SYS_DMA_MAP_DEVICE  0xA4    ; map into device IOMMU
%define SYS_DMA_SYNC        0xA5    ; sync CPU/device

; Power
%define SYS_POWER_REG_CB    0xB0    ; register power callback
%define SYS_POWER_UNREG_CB  0xB1    ; unregister
%define SYS_POWER_INHIBIT   0xB2    ; inhibit suspend
%define SYS_POWER_UNINHIBIT 0xB3    ; release inhibit
%define SYS_POWER_BATTERY   0xB4    ; get battery status

; Network / TLS
%define SYS_TLS_LISTEN      0xC0    ; listen TLS
%define SYS_TLS_ACCEPT      0xC1    ; accept TLS
%define SYS_TLS_CONNECT     0xC2    ; connect TLS
%define SYS_TLS_READ        0xC3    ; read TLS
%define SYS_TLS_WRITE       0xC4    ; write TLS
%define SYS_TLS_CLOSE       0xC5    ; close TLS
%define SYS_TLS_PEER_CERT   0xC6    ; get peer cert

; ---------------------------------------------------------------------------
; Memory Flags
; ---------------------------------------------------------------------------
%define MEM_DMA         0x01    ; DMA-able (contiguous physical)
%define MEM_EXEC        0x02    ; Executable
%define MEM_UNCACHED    0x04    ; Uncached (UC)
%define MEM_WC          0x08    ; Write-combining (WC)
%define MEM_SHARED      0x10    ; Shared with other tasks
%define MEM_HUGE        0x20    ; 2MB huge pages
%define MEM_1GB         0x40    ; 1GB huge pages
%define MEM_LOCKED      0x80    ; Locked (no swap/pageout)

; ---------------------------------------------------------------------------
; Wait Event Types
; ---------------------------------------------------------------------------
%define WAIT_IRQ        1       ; IRQ event
%define WAIT_CHANNEL    2       ; Channel message
%define WAIT_TIMER      3       ; Timer expiry
%define WAIT_TASK       4       ; Task exit
%define WAIT_INPUT      5       ; Input event

; ---------------------------------------------------------------------------
; Task Flags
; ---------------------------------------------------------------------------
%define TASK_USER       0x01    ; User mode (ring 3 when available)
%define TASK_KERNEL     0x00    ; Kernel mode (ring 0)
%define TASK_NO_FPU     0x02    ; No FPU/SSE/AVX context
%define TASK_NO_SSE     0x04    ; No SSE context
%define TASK_NO_AVX     0x08    ; No AVX context
%define TASK_DEBUG      0x10    ; Debug tracing enabled

; ---------------------------------------------------------------------------
; IRQ Flags
; ---------------------------------------------------------------------------
%define IRQ_SHARED      0x01    ; Shared IRQ line
%define IRQ_LEVEL       0x02    ; Level-triggered
%define IRQ_EDGE        0x04    ; Edge-triggered
%define IRQ_PER_CPU     0x08    ; Per-CPU IRQ

; ---------------------------------------------------------------------------
; Input Event Types (matches Linux EV_*)
; ---------------------------------------------------------------------------
%define EV_SYN          0x00
%define EV_KEY          0x01
%define EV_REL          0x02
%define EV_ABS          0x03
%define EV_MSC          0x04
%define EV_SW           0x05
%define EV_LED          0x11
%define EV_SND          0x12
%define EV_REP          0x14
%define EV_FF           0x15
%define EV_PWR          0x16
%define EV_FF_STATUS    0x17

; Input Capabilities
%define CAP_KEYBOARD    0x01
%define CAP_POINTER     0x02
%define CAP_TOUCH       0x04
%define CAP_TABLET      0x08

; Input Bus Types
%define BUS_PCI         0x01
%define BUS_ISAPNP      0x02
%define BUS_USB         0x03
%define BUS_HIL         0x04
%define BUS_BLUETOOTH   0x05
%define BUS_VIRTUAL     0x06
%define BUS_I2C         0x07
%define BUS_SPI         0x08
%define BUS_PS2         0x09

; ---------------------------------------------------------------------------
; PCI Structures
; ---------------------------------------------------------------------------
%define PCI_BAR_MEM     0x00
%define PCI_BAR_IO      0x01
%define PCI_BAR_PREFETCH 0x08

struc PciBar
    .type:      resd 1
    .base:      resq 1
    .size:      resq 1
endstruc

struc PciDevice
    .bus:           resb 1
    .dev:           resb 1
    .fn:            resb 1
    .reserved:      resb 1
    .vendor_id:     resw 1
    .device_id:     resw 1
    .class_code:    resb 1
    .subclass:      resb 1
    .prog_if:       resb 1
    .revision:      resb 1
    .bar0:          resb 24     ; PciBar
    .bar1:          resb 24
    .bar2:          resb 24
    .bar3:          resb 24
    .bar4:          resb 24
    .bar5:          resb 24
    .irq:           resb 1
    .padding:       resb 7
endstruc

; PCI Class Codes
%define PCI_CLASS_DISPLAY     0x03
%define PCI_SUBCLASS_VGA      0x00
%define PCI_SUBCLASS_XGA      0x01
%define PCI_SUBCLASS_3D       0x02
%define PCI_SUBCLASS_DISPLAY  0x80

%define PCI_CLASS_MULTIMEDIA  0x04
%define PCI_SUBCLASS_HDMI     0x03

; ---------------------------------------------------------------------------
; MMIO Flags
; ---------------------------------------------------------------------------
%define MMIO_UNCACHED   0x01
%define MMIO_WC         0x02
%define MMIO_DMA        0x04

; DMA Sync Directions
%define DMA_TO_DEVICE   1
%define DMA_FROM_DEVICE 2
%define DMA_BIDIR       3

; ---------------------------------------------------------------------------
; Power Events
; ---------------------------------------------------------------------------
%define POWER_SUSPEND       1
%define POWER_RESUME        2
%define POWER_HIBERNATE     3
%define POWER_LOW_BATTERY   4
%define POWER_AC_CHANGE     5

; ---------------------------------------------------------------------------
; Log Levels
; ---------------------------------------------------------------------------
%define LOG_NONE      0
%define LOG_ERROR     1
%define LOG_WARN      2
%define LOG_INFO      3
%define LOG_DEBUG     4
%define LOG_TRACE     5

; ---------------------------------------------------------------------------
; Tattva Version (for contract negotiation)
; ---------------------------------------------------------------------------
%define TATTVA_CONTRACT_VERSION  0x010000   ; 1.0.0

; ---------------------------------------------------------------------------
; External Function Declarations (implemented in src/tattva/*.asm)
; ---------------------------------------------------------------------------

%ifndef TATTVA_BINDING_IMPL

; Memory
extern tv_mem_alloc
extern tv_mem_free
extern tv_mem_resize
extern tv_mem_map_phys
extern tv_mem_info

; Time
extern tv_time_now_ns
extern tv_time_now_us
extern tv_time_now_ms
extern tv_time_tsc
extern tv_time_sleep_ns
extern tv_time_sleep_until
extern tv_timer_register
extern tv_timer_cancel

; Log
extern tv_log_write
extern tv_log_printf
extern tv_log_set_level
extern tv_log_get_level
extern tv_log_flush

; Entropy
extern tv_entropy_get
extern tv_entropy_u64
extern tv_entropy_siphash_key

; Wait
extern tv_waitset_create
extern tv_waitset_add
extern tv_waitset_remove
extern tv_wait_wait
extern tv_wait_yield
extern tv_wait_wake_task

; Task
extern tv_task_spawn
extern tv_task_exit
extern tv_task_wait
extern tv_task_self
extern tv_task_set_priority
extern tv_task_pin

; IRQ
extern tv_irq_register
extern tv_irq_unregister
extern tv_irq_enable
extern tv_irq_disable
extern tv_irq_affinity
extern tv_irq_set_affinity

; Input
extern tv_input_register_callback
extern tv_input_unregister_callback
extern tv_input_device_info
extern tv_input_grab

; FS
extern tv_fs_read
extern tv_fs_stat
%endif
extern tv_fs_list
extern tv_fs_open
extern tv_fs_pread
extern tv_fs_close

; PCI
extern tv_pci_for_each
extern tv_pci_find_class
extern tv_pci_config_read_dword
extern tv_pci_config_write_dword
extern tv_pci_enable_device
extern tv_pci_disable_device

; MMIO/DMA
extern tv_mmio_map
extern tv_mmio_unmap
extern tv_dma_alloc
extern tv_dma_free
extern tv_dma_map_device
extern tv_dma_sync

; Power
extern tv_power_register_callback
extern tv_power_unregister_callback
extern tv_power_inhibit_suspend
extern tv_power_uninhibit_suspend
extern tv_power_battery_status

; Network/TLS
extern tv_tls_listen
extern tv_tls_accept
extern tv_tls_connect
extern tv_tls_read
extern tv_tls_write
extern tv_tls_close
extern tv_tls_peer_cert

%endif ; __TATTVA_INC__
