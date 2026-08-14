; =============================================================================
; lib/io/io.inc
; Shared structure definitions, constants, and vector mappings.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef LIB_IO_IO_INC
%define LIB_IO_IO_INC

; =============================================================================
; SHARED STRUCTURES
; =============================================================================

; ---- fd_t : descriptor table entry -----------------------------------------
struc fd_t
    .type        resq 1      ; FD_TYPE_{FILE,BLOCK,CHAR,EVENT,PIPE}
    .state       resq 1      ; FD_OPEN | FD_STALE
    .refcount    resq 1      ; active references
    .generation  resq 1      ; bumped on free; detects use-after-free
    .device      resq 1      ; -> device_t (fops live there; native path)
    .vtable      resq 1      ; -> posix/win32 fops (hosted shims only; 0 on native)
    .priv        resq 1      ; driver-private pointer
endstruc

; ---- iovec_t : one scatter-gather element ----------------------------------
struc iovec_t
    .base        resq 1      ; virtual base address
    .phys        resq 1      ; physical base (filled by dma/map)
    .len         resq 1      ; byte length
    .flags       resq 1      ; page-crossing split marker, etc.
endstruc

; ---- io_request_t : one async I/O request ----------------------------------
struc io_request_t
    .opcode      resq 1      ; IO_OP_{READ,WRITE,FLUSH,TRIM,WRITE_ZEROES}
    .flags       resq 1      ; IO_DIRECT | IO_FUA | IO_FIXEDBUF | ...
    .device      resq 1      ; -> block device
    .lba         resq 1      ; starting logical block
    .nblocks     resq 1      ; block count
    .iov         resq 1      ; -> iovec_t array
    .iov_cnt     resq 1      ; iovec count
    .id          resq 1      ; completion / correlation ID
    .state       resq 1      ; INIT..COMPLETE/ERROR/CANCELLED/TIMEOUT
    .status      resq 1      ; final result code (§3 band on error)
    .pin_token   resq 1      ; DMA pin handle; released on completion
    .submit_tsc  resq 1      ; rdtsc at submit (latency histogram)
    .complete_tsc resq 1     ; rdtsc at completion
    .result      resq 1      ; bytes transferred / device-specific
    .waiter      resq 1      ; -> waitq entry, or 0
endstruc

; ---- io_completion_t : one completion-ring slot (pre-allocated) ------------
struc io_completion_t
    .id          resq 1      ; matches io_request_t.id
    .status      resq 1      ; result code
    .result      resq 1      ; bytes transferred / device-specific
    .complete_tsc resq 1     ; rdtsc at completion
endstruc

; ---- virtq_desc : virtio split-virtqueue descriptor (16 bytes) -------------
struc virtq_desc
    .addr        resq 1      ; guest-physical buffer address
    .len         resd 1      ; length
    .flags       resw 1      ; NEXT | WRITE | INDIRECT
    .next        resw 1      ; index of next descriptor when NEXT set
endstruc

; ---- boot_handoff_t : consumed from boot (mirrors boot_params) ------------
struc boot_handoff_t
    .magic       resq 1
    .mem_map     resq 1      ; -> memory map array
    .mem_map_cnt resq 1
    .rsdp        resq 1      ; ACPI RSDP physical address
    .framebuffer resq 1      ; -> framebuffer info
    .boot_device resq 1      ; boot block device handle
    .pml4        resq 1      ; initial page-table root
endstruc

; ---- mem_map_entry_t : memory map region entry (24 bytes) ------------------
struc mem_map_entry_t
    .base        resq 1      ; physical base address
    .len         resq 1      ; byte length of the region
    .type        resd 1      ; region type: 1=available RAM, 2=reserved, 3=ACPI reclaim, 4=MMIO
    .pad         resd 1      ; 64-bit alignment pad
endstruc

; ---- spsc_ring_t : single-producer single-consumer ring buffer -------------
struc spsc_ring_t
    ; --- line 0 (offset 0): read-only shared header ---
    .mask        resq 1      ; capacity-1 (capacity must be a power of 2)
    .buffer      resq 1      ; -> array of entries (io_request_t * or io_completion_t *)
    .entry_size  resq 1      ; bytes per entry (index scaling)
    .capacity    resq 1      ; total slots (= mask + 1)
    .resv0       resq 4      ; pad line 0 to 64 bytes
    ; --- line 1 (offset 64): producer-owned ---
    .prod_idx    resq 1      ; producer index (owned/written by submitter)
    .resv1       resq 7      ; pad to 64 bytes (no false sharing with consumer)
    ; --- line 2 (offset 128): consumer/ISR-owned ---
    .cons_idx    resq 1      ; consumer index (owned/written by ISR/completion)
    .resv2       resq 7      ; pad to 64 bytes
endstruc                     ; total = 192 (three cache lines)

; ---- percpu_t ---------------------------------------------------------------
; Declared in lib/percpu.inc, not here. It is shared with lib/mem (the per-core
; arena) and kernel/sched (the run queue), and keeping a private copy is what
; let those three subsystems drift onto colliding offsets.
%include "lib/percpu.inc"

; ---- driver_binding_t : driver registration entry --------------------------
struc driver_binding_t
    .vendor_id   resw 1      ; PCI vendor ID
    .device_id   resw 1      ; PCI device ID
    .class_mask  resd 1      ; PCI class mask
    .class_match resd 1      ; PCI class code to match
    .probe_fn    resq 1      ; function pointer: probe(device_t *dev, pci_dev_t *pci) -> rax (status)
endstruc

; ---- device_t : a probed device + its operation table ----------------------
struc device_t
    .name        resb 32     ; human-readable id
    .type        resq 1      ; DEV_TYPE_{BLOCK,CHAR,EVENT}  (NET reserved for unet)
    .state       resq 1      ; PROBE|ONLINE|DEGRADED|RESET|OFFLINE (health/state.asm)
    ; --- operation table ---
    .open        resq 1
    .close       resq 1
    .read        resq 1      ; synchronous fallback / char-device read
    .write       resq 1      ; synchronous fallback / char-device write
    .submit      resq 1      ; ASYNC: submit(device_t *dev, io_request_t *req)
    .flush       resq 1      ; barrier / flush / FUA entry
    .ioctl       resq 1      ; device-specific control (absorbs seek etc.)
    ; --- block geometry (queried at probe; invariant #3) ---
    .sector_size resq 1      ; 512 or 4096, from LBA-format query
    .capacity    resq 1      ; total addressable blocks
    .parent      resq 1      ; -> parent device_t (0 for physical/root devices)
    .lba_offset  resq 1      ; partition start sector (0 for physical devices)
    .lba_count   resq 1      ; partition size in sectors (equal to capacity for physical devices)
    ; --- async plumbing ---
    .queue       resq 1      ; -> per-device request queue / NVMe SQ-CQ array
    .private     resq 1      ; driver-private state
endstruc

; ---- idt_gate_t : x86-64 IDT Gate Descriptor (16 bytes) --------------------
struc idt_gate_t
    .offset_low  resw 1      ; offset bits 0-15
    .selector    resw 1      ; code segment selector in GDT (e.g. SEL_CODE64)
    .ist         resb 1      ; bits 0-2: IST stack index, bits 3-7: zero
    .type_attr   resb 1      ; type and attributes (e.g. gate type, privilege level, present)
    .offset_mid  resw 1      ; offset bits 16-31
    .offset_high resd 1      ; offset bits 32-63
    .reserved    resd 1      ; reserved, must be zero
endstruc

; ---- tss_descriptor_t : GDT TSS System Segment Descriptor (16 bytes) -------
struc tss_descriptor_t
    .limit_low   resw 1      ; limit bits 0-15
    .base_low    resw 1      ; base bits 0-15
    .base_mid1   resb 1      ; base bits 16-23
    .type_attr   resb 1      ; type and flags (present, type=0x9/0xB for TSS)
    .limit_high  resb 1      ; limit bits 16-19 and flags
    .base_mid2   resb 1      ; base bits 24-31
    .base_high   resd 1      ; base bits 32-63
    .reserved    resd 1      ; reserved, must be zero
endstruc

; ---- acpi_header_t : ACPI Table Common Header (36 bytes) -------------------
struc acpi_header_t
    .signature   resb 4      ; table identifier (e.g., "APIC", "MCFG")
    .length      resd 1      ; table length in bytes
    .revision    resb 1      ; revision of structure
    .checksum    resb 1      ; checksum over entire table
    .oem_id      resb 6      ; OEM ID string
    .oem_table_id resb 8     ; OEM Table ID string
    .oem_revision resd 1     ; OEM revision number
    .creator_id  resd 1      ; ASL compiler creator ID
    .creator_rev resd 1      ; ASL compiler creator revision
endstruc

; ---- virtq_avail_t : virtio available ring ---------------------------------
struc virtq_avail_t
    .flags       resw 1      ; available ring flags (e.g. NO_INTERRUPT)
    .idx         resw 1      ; index where driver will write next descriptor index
endstruc

; ---- virtq_used_elem_t : virtio used ring element (8 bytes) ----------------
struc virtq_used_elem_t
    .id          resd 1      ; index of start of used descriptor chain
    .len         resd 1      ; total length of the written descriptor chain
endstruc

; ---- virtq_used_t : virtio used ring ---------------------------------------
struc virtq_used_t
    .flags       resw 1      ; used ring flags (e.g. NO_PUBLISH)
    .idx         resw 1      ; index where device will write next used element
endstruc

; ---- interrupt_frame_t : ISR Stack Save Frame (120 bytes) ------------------
struc interrupt_frame_t
    ; Pushed manually by isr_common_stub (GP registers in reverse push order)
    .r11         resq 1      ; general purpose register 11
    .r10         resq 1      ; general purpose register 10
    .r9          resq 1      ; general purpose register 9
    .r8          resq 1      ; general purpose register 8
    .rdi         resq 1      ; general purpose register DI
    .rsi         resq 1      ; general purpose register SI
    .rdx         resq 1      ; general purpose register DX
    .rcx         resq 1      ; general purpose register CX
    .rax         resq 1      ; general purpose register AX
    ; Pushed by hardware exception, or manually by stub if no error code
    .error_code  resq 1      ; error code pushed by CPU or 0 dummy
    .rip         resq 1      ; return instruction pointer
    .cs          resq 1      ; return code segment selector
    .rflags      resq 1      ; return flags register
    .rsp         resq 1      ; return stack pointer
    .ss          resq 1      ; return stack segment selector
endstruc

; ---- vga_cell_t : VGA Text Mode Buffer Cell (2 bytes) ----------------------
struc vga_cell_t
    .char        resb 1      ; ASCII character code
    .attr        resb 1      ; attribute byte (foreground, background, blink)
endstruc

; ---- pci_header_t : standard PCI Configuration Header Type 0 (64 bytes) -----
struc pci_header_t
    .vendor_id      resw 1      ; 0x00
    .device_id      resw 1      ; 0x02
    .command        resw 1      ; 0x04
    .status         resw 1      ; 0x06
    .revision_id    resb 1      ; 0x08
    .class_code     resb 3      ; 0x09 (prog_if, subclass, class)
    .cache_line_sz  resb 1      ; 0x0C
    .latency_timer  resb 1      ; 0x0D
    .header_type    resb 1      ; 0x0E
    .bist           resb 1      ; 0x0F
    .bar            resd 6      ; 0x10 Base Address Registers (BAR0-5)
    .cardbus_cis    resd 1      ; 0x28
    .sub_vendor_id  resw 1      ; 0x2C
    .sub_system_id  resw 1      ; 0x2E
    .rom_base       resd 1      ; 0x30
    .cap_pointer    resb 1      ; 0x34 Capabilities Pointer
    .reserved       resb 7      ; 0x35
    .interrupt_line resb 1      ; 0x3C
    .interrupt_pin  resb 1      ; 0x3D
    .min_gnt        resb 1      ; 0x3E
    .max_lat        resb 1      ; 0x3F
endstruc

; ---- msix_table_entry_t : MSI-X Table Entry Layout (16 bytes) ---------------
struc msix_table_entry_t
    .msg_addr_low   resd 1      ; 0x00 Lower 32-bits of destination APIC address
    .msg_addr_high  resd 1      ; 0x04 Upper 32-bits
    .msg_data       resd 1      ; 0x08 Message data register (vector mapping)
    .vector_ctrl    resd 1      ; 0x0C Vector control register (e.g. mask bit)
endstruc

; ---- nvme_regs_t : NVMe Controller Registers (64 bytes) --------------------
struc nvme_regs_t
    .cap            resq 1      ; 0x00 Controller Capabilities
    .vs             resd 1      ; 0x08 Version
    .intms          resd 1      ; 0x0C Interrupt Mask Set
    .intmc          resd 1      ; 0x10 Interrupt Mask Clear
    .cc             resd 1      ; 0x14 Controller Configuration
    .reserved0      resd 1      ; 0x18 Reserved
    .csts           resd 1      ; 0x1C Controller Status
    .nssr           resd 1      ; 0x20 NVM Subsystem Reset (optional)
    .aqa            resd 1      ; 0x24 Admin Queue Attributes
    .asq            resq 1      ; 0x28 Admin Submission Queue Base Address
    .acq            resq 1      ; 0x30 Admin Completion Queue Base Address
    .cmbloc         resd 1      ; 0x38 Controller Memory Buffer Location
    .cmbsz          resd 1      ; 0x3C Controller Memory Buffer Size
endstruc

; ---- msi_cap_t : Message Signaled Interrupts Capability (8 bytes) -----------
struc msi_cap_t
    .cap_id         resb 1      ; 0x05 for MSI
    .next_ptr       resb 1      ; Offset to next capability
    .msg_control    resw 1      ; Message control register
    .msg_addr_low   resd 1      ; Lower 32-bits of target message address
endstruc

; ---- msix_cap_t : Message Signaled Interrupts Extended Capability (12 bytes) -
struc msix_cap_t
    .cap_id         resb 1      ; 0x11 for MSI-X
    .next_ptr       resb 1      ; Offset to next capability
    .msg_control    resw 1      ; Message control register
    .table_offset   resd 1      ; Table BIR (bits 0-2) + offset (bits 3-31)
    .pba_offset     resd 1      ; Pending Bit Array BIR (bits 0-2) + offset
endstruc

; ---- virtio_blk_req_t : Virtio-Blk Request Header (16 bytes) ----------------
struc virtio_blk_req_t
    .type           resd 1      ; 0=read (IN), 1=write (OUT), 4=flush
    .reserved       resd 1      ; Must be 0
    .sector         resq 1      ; Target LBA (logical sector number)
endstruc

; ---- tss_t : x86-64 Task State Segment (HARDWARE-FIXED, 104 bytes) ----------
struc tss_t
    .reserved0   resd 1      ; 0x00
    .rsp0        resq 1      ; 0x04  Ring-0 stack pointer
    .rsp1        resq 1      ; 0x0C
    .rsp2        resq 1      ; 0x14
    .reserved1   resq 1      ; 0x1C
    .ist1        resq 1      ; 0x24  IST1: double-fault stack
    .ist2        resq 1      ; 0x2C  IST2: NMI stack
    .ist3        resq 1      ; 0x34
    .ist4        resq 1      ; 0x3C
    .ist5        resq 1      ; 0x44
    .ist6        resq 1      ; 0x4C
    .ist7        resq 1      ; 0x54
    .reserved2   resq 1      ; 0x5C
    .reserved3   resw 1      ; 0x64
    .iomap_base  resw 1      ; 0x66  I/O permission-map base offset
endstruc

; ---- rsdp_t : ACPI Root System Description Pointer (ACPI 2.0+, 36 bytes) ----
struc rsdp_t
    .signature    resb 8     ; 0x00  "RSD PTR "
    .checksum     resb 1     ; 0x08  v1 checksum (first 20 bytes)
    .oem_id       resb 6     ; 0x09
    .revision     resb 1     ; 0x0F  0 = ACPI 1.0, 2 = ACPI 2.0+
    .rsdt_addr    resd 1     ; 0x10  32-bit RSDT (legacy; ignore when revision>=2)
    .length       resd 1     ; 0x14  total table length
    .xsdt_addr    resq 1     ; 0x18  64-bit XSDT (use this on revision>=2)
    .ext_checksum resb 1     ; 0x20  checksum over the whole 36-byte structure
    .reserved     resb 3     ; 0x21
endstruc

; =============================================================================
; CONSTANTS
; =============================================================================

; ---- io_request_t State Constants (io_request_t.state) ----------------------
IO_REQ_INIT       equ 0      ; Request initialized but not yet submitted
IO_REQ_SUBMITTED  equ 1      ; Request placed in SPSC submission ring
IO_REQ_IN_FLIGHT  equ 2      ; Driver has picked up request and is executing DMA
IO_REQ_COMPLETE   equ 3      ; Request completed successfully
IO_REQ_ERROR      equ 4      ; Request failed with an error
IO_REQ_CANCELLED  equ 5      ; Request cancelled before or during execution
IO_REQ_TIMEOUT    equ 6      ; Request timed out on the timeout wheel

; ---- File Descriptor Type Constants (fd_t.type) ---------------------------
FD_TYPE_FILE      equ 0      ; Regular file (reserved for uxfs subsystem)
FD_TYPE_BLOCK     equ 1      ; Block device (disk, NVMe, partition)
FD_TYPE_CHAR      equ 2      ; Character device (serial console, keyboard)
FD_TYPE_EVENT     equ 3      ; Event synchronization primitive
FD_TYPE_PIPE      equ 4      ; In-kernel pipe

; ---- Device State Constants (device_t.state) ------------------------------
DEV_STATE_PROBE    equ 0      ; Device is being probed / detected
DEV_STATE_ONLINE   equ 1      ; Device is active and accepting I/O requests
DEV_STATE_DEGRADED equ 2      ; Device is active but running in degraded/recovery mode
DEV_STATE_RESET    equ 3      ; Device is undergoing controller/queue reset
DEV_STATE_OFFLINE  equ 4      ; Device is disabled (failed or hot-removed)

; ---- I/O Opcode Constants (io_request_t.opcode) ---------------------------
IO_OP_READ         equ 0      ; Read sectors/bytes
IO_OP_WRITE        equ 1      ; Write sectors/bytes
IO_OP_FLUSH        equ 2      ; Flush write caches / barrier
IO_OP_TRIM         equ 3      ; Trim / discard blocks
IO_OP_WRITE_ZEROES equ 4      ; Fast-zero blocks

; ---- I/O Flag Bits (io_request_t.flags) ------------------------------------
IO_DIRECT          equ (1 << 0) ; Direct I/O (bypass host page/block caches)
IO_FUA             equ (1 << 1) ; Force Unit Access (write directly to media)
IO_FIXEDBUF        equ (1 << 2) ; Pre-registered / pinned DMA buffer

; ---- Page Table Entry (PTE) Hardware Bits ----------------------------------
PTE_PRESENT        equ (1 << 0) ; Page is mapped in translation tables
PTE_WRITE          equ (1 << 1) ; Write access allowed
PTE_USER           equ (1 << 2) ; User-mode access allowed
PTE_PWT            equ (1 << 3) ; Write-Through caching (PWT)
PTE_PCD            equ (1 << 4) ; Cache-Disabled (PCD)
PTE_PAT            equ (1 << 7) ; Page Attribute Table index bit (for PTEs)
PTE_NX             equ (1 << 63); No-Execute (requires LME.NXE enabled)

; ---- Virtio-Blk Status Codes -----------------------------------------------
VIRTIO_BLK_S_OK     equ 0       ; Success
VIRTIO_BLK_S_IOERR  equ 1       ; Device I/O error
VIRTIO_BLK_S_UNSUPP equ 2       ; Unsupported command

; ---- Local APIC Register MMIO Offsets ---------------------------------------
LAPIC_ID           equ 0x0020   ; Local APIC ID
LAPIC_VER          equ 0x0030   ; Version
LAPIC_TPR          equ 0x0080   ; Task Priority Register
LAPIC_EOI          equ 0x00B0   ; End Of Interrupt
LAPIC_SVR          equ 0x00F0   ; Spurious Interrupt Vector Register
LAPIC_ICR0         equ 0x0300   ; Interrupt Command Register [0:31]
LAPIC_ICR1         equ 0x0310   ; Interrupt Command Register [32:63]
LAPIC_LVT_TIMER    equ 0x0320   ; Timer LVT Register
LAPIC_TIMER_INIT   equ 0x0380   ; Timer Initial Count Register
LAPIC_TIMER_CUR    equ 0x0390   ; Timer Current Count Register
LAPIC_TIMER_DIV    equ 0x03E0   ; Timer Divide Configuration Register

; ---- IO-APIC Register Offsets ----------------------------------------------
IOAPIC_REGSEL      equ 0x00     ; Index Select Register
IOAPIC_IOWIN       equ 0x10     ; Data Window Register
IOAPIC_REDTBL_BASE equ 0x10     ; Base offset for Redirection Table entries (0-23)

; =============================================================================
; STRUCTURE SIZE & LAYOUT ASSERTIONS
; =============================================================================

%if pci_header_t_size != 64
  %error "pci_header_t size drift — must be 64 bytes"
%endif
%if msix_table_entry_t_size != 16
  %error "msix_table_entry_t size drift — must be 16 bytes"
%endif
%if nvme_regs_t_size != 64
  %error "nvme_regs_t size drift — must be 64 bytes"
%endif
%if msi_cap_t_size != 8
  %error "msi_cap_t size drift — must be 8 bytes"
%endif
%if msix_cap_t_size != 12
  %error "msix_cap_t size drift — must be 12 bytes"
%endif
%if virtio_blk_req_t_size != 16
  %error "virtio_blk_req_t size drift — must be 16 bytes"
%endif
%if tss_t_size    != 104 
  %error "tss_t layout drift — must be 104 bytes (x86-64 hardware-fixed)"
%endif
%if rsdp_t_size   != 36
  %error "rsdp_t layout drift — must be 36 bytes (ACPI 2.0+)"
%endif
%if virtq_desc_size != 16
  %error "virtq_desc must be 16 bytes (virtio spec)"
%endif
%if io_completion_t_size > 64
  %error "io_completion_t exceeds one cache line — false-sharing risk in ISR path"
%endif
%if boot_handoff_t_size != 56
  %error "boot_handoff_t drift — must be 56 bytes"
%endif
%if mem_map_entry_t_size != 24
  %error "mem_map_entry_t size drift — must be 24 bytes"
%endif
%if spsc_ring_t_size != 192
  %error "spsc_ring_t must be 192 bytes (three cache lines; prod/cons on separate lines)"
%endif
%if spsc_ring_t.prod_idx != 64
  %error "spsc_ring_t.prod_idx must sit on cache line 1 (offset 64)"
%endif
%if spsc_ring_t.cons_idx != 128
  %error "spsc_ring_t.cons_idx must sit on cache line 2 (offset 128)"
%endif
%if percpu_t_size != 64
  %error "percpu_t layout drift — must be exactly 64 bytes"
%endif
%if driver_binding_t_size != 20
  %error "driver_binding_t layout drift — must be 20 bytes"
%endif
%if device_t_size != 160
  %error "device_t layout drift — must be 160 bytes"
%endif
%if idt_gate_t_size != 16
  %error "idt_gate_t layout drift — must be 16 bytes"
%endif
%if tss_descriptor_t_size != 16
  %error "tss_descriptor_t layout drift — must be 16 bytes"
%endif
%if acpi_header_t_size != 36
  %error "acpi_header_t layout drift — must be 36 bytes"
%endif
%if interrupt_frame_t_size != 120
  %error "interrupt_frame_t layout drift — must be 120 bytes"
%endif
%if vga_cell_t_size != 2
  %error "vga_cell_t layout drift — must be 2 bytes"
%endif

; ---- Common I/O ports ----
PORT_UART_COM1    equ 0x3F8       ; COM1 UART base
PORT_UART_COM2    equ 0x2F8       ; COM2 UART base
PORT_VGA_IDX      equ 0x3D4       ; VGA CRTC index
PORT_VGA_DATA     equ 0x3D5       ; VGA CRTC data

%endif ; LIB_IO_IO_INC
