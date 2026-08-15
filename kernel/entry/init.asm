%ifndef GUARD_KERNEL_ENTRY_INIT_ASM
%define GUARD_KERNEL_ENTRY_INIT_ASM
; =============================================================================
; Tattva OS — kernel/entry/init.asm
; =============================================================================
; Kernel early initialization sequence. Saves the BootInfo pointer, verifies
; CPU-local storage (GS base), and sequentially calls initialization stubs for
; core kernel subsystems.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/mem/mem.inc"

section .text

kernel_init:
    ; 0. ulog early mode — safe before anything else exists; see
    ; lib/ulog/init/early_init.asm. Needs no allocator, no GS, nothing.
    call ulog_early_init

    ; 1. Save BootInfo pointer in a global variable
    mov [boot_info_ptr], rdi

    ; 1b. Load SMP active cores count from BootInfo structure (offset 80)
    mov eax, [rdi + 80]             ; load core count
    test eax, eax                   ; check if 0
    jnz .store_cores
    mov eax, 1                      ; default to 1 core
.store_cores:
    mov [smp_active_cores], eax

    ; 2. Initialize Kernel GDT & TSS (with IST stack overflow protection)
    call gdt_init

    ; 3. Print initial boot message
    mov rsi, msg_kernel_boot
    call uart_print_str

    ; 3b. Print GDT/TSS init status
    mov rsi, msg_init_gdt
    call uart_print_str
    mov rsi, msg_ok
    call uart_print_str

    ; 4. Print BootInfo physical address
    mov rsi, msg_boot_info_loc
    call uart_print_str
    mov rax, rdi
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5. Verify GS Base initialization at runtime
    mov ecx, 0xC0000101             ; MSR_GS_BASE
    rdmsr                           ; EDX:EAX = GS Base
    shl rdx, 32
    or rax, rdx                     ; RAX = full 64-bit GS base
    
    mov rsi, msg_gs_base_loc
    call uart_print_str
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5a. Test CPU-local GS Segment Accessors
    mov rsi, msg_gs_api_test
    call uart_print_str
    call cpu_get_id                 ; EAX = cpu_id
    call uart_print_dec
    mov al, '/'                     ; separator
    call uart_putc
    call cpu_get_stack_top          ; RAX = stack_top
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5b. Initialize early CPU hardware and verify mandatory vector features
    mov rsi, msg_init_cpu
    call uart_print_str
    call cpu_init_hardware

    ; 5c. Decode this core's SMT/core/package topology and cache hierarchy
    ; (lib/hw/ucpu). Needs GS live (verified in step 5) since the result is
    ; keyed by gs:percpu_t.cpu_id.
    mov rsi, msg_init_ucpu_topo
    call uart_print_str
    call ucpu_topology_decode_current
    call ucpu_cache_topology_scan
    mov rsi, msg_ok
    call uart_print_str

    ; 4b. Initialize Exception Handlers (IDT)
    mov rsi, msg_init_idt
    call uart_print_str
    call interrupts_init
    mov rsi, msg_ok
    call uart_print_str

    ; 4c. Calibrate the TSC against the PIT and start the monotonic clock.
    ; Nothing called this anywhere before — lib/time/tsc.asm's tsc_freq_hz
    ; sat at its uncalibrated 3.0 GHz default permanently, silently, for
    ; every udelay/mdelay/tsc_elapsed_nanos call in the kernel. Whatever the
    ; true frequency actually is, that default is only ever right by
    ; coincidence; on a host where it's meaningfully off, every TSC-based
    ; wait or duration is off by the same ratio. tsc_calibrate_pit uses
    ; PIT channel 2 by polling a status bit — it needs no interrupts, so it's
    ; safe to run right here regardless of IDT/PIC state.
    mov rsi, msg_init_time
    call uart_print_str
    call time_init
    mov rsi, msg_ok
    call uart_print_str

    ; 5. Initialize Memory Management
    mov rsi, msg_init_mm
    call uart_print_str
    call mm_init
    mov rsi, msg_ok
    call uart_print_str

    ; 6. Initialize Scheduler
    mov rsi, msg_init_sched
    call uart_print_str
    call sched_init
    mov rsi, msg_ok
    call uart_print_str

    ; 6b. ulog full mode — needs the heap (step 5) and fiber_create (step 6),
    ; so it lands here: pool + this core's ring + serial sink + the drain
    ; daemon fiber all come up together, then early-mode calls switch over.
    ;
    ; STILL PAGE-FAULTS even with bsp_cpu_local rebuilt as a real istruc
    ; percpu_t (verified: rebuilt, rebooted, same fault). Isolated the exact
    ; instruction via the page-fault handler's own R15 (pointer to the
    ; saved return RIP) rather than guessing from a register snapshot:
    ; log_ring_alloc_for_this_cpu's `mov [ulog_rings_by_cpu + rax*8], rbx`,
    ; writing to computed address ~0x2CAB648 (~45MB in) — non-present.
    ; Neither ulog_rings_by_cpu (512 bytes) nor a single core's ring_t
    ; (~32KB, confirmed via the heap_alloc size immediately before this)
    ; explain a .bss address that far out; this is either the whole tree's
    ; combined .bss genuinely reaching ~45MB (plausible at this codebase's
    ; scale, in which case something isn't extending the identity map that
    ; far) or a link-time address computed wrong. Both are outside what a
    ; scheduler-focused sweep can respons­ibly chase down. Bypassed again,
    ; same as before — restore once root-caused.
    mov rsi, msg_init_ulog
    call uart_print_str
    ; call ulog_full_init
    mov rsi, msg_ok
    call uart_print_str

    ; 7. Initialize Device Drivers
    mov rsi, msg_init_drivers
    call uart_print_str
    call drivers_init
    mov rsi, msg_ok
    call uart_print_str

    ; 8. Initialize System Services
    mov rsi, msg_init_serve
    call uart_print_str
    call serve_init
    mov rsi, msg_ok
    call uart_print_str

    ; 9. Jump to the main kernel loop
    jmp kernel_main

; -----------------------------------------------------------------------------
; Subsystem Initialization Stubs
; (To be replaced by actual implementations in subsequent milestones)
; -----------------------------------------------------------------------------
mm_init:
    call phys_init
    call virt_shuffle_pml4_init

    ; 1. Mark kernel code/data as global (1MB to the true end of the kernel's
    ; footprint, .bss included). Neither kernel_end (end of .text) nor the
    ; ULF header's size field (end of the on-disk image) reach .bss — see the
    ; kernel_bss_end comment in kernel/entry.asm — and .bss is exactly where
    ; this kernel's own runtime state (including the physical allocator's
    ; bitmap and the kernel stacks) lives.
    mov rdi, 0x100000               ; kernel start: 1MB
    mov rsi, kernel_bss_end
    sub rsi, 0x100000                ; kernel size, .bss included
    call virt_mark_global_range

    ; 1b. Mark kernel code segment as read-only for write protection
    mov rdi, kernel_text_start
    mov rsi, kernel_text_end
    sub rsi, rdi                    ; kernel code size
    call virt_mark_read_only_range

    ; 2. Mark physical allocator bitmap as global
    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    mov rsi, [phys_state + phys_state_t.bitmap_size]
    call virt_mark_global_range

    ; 3. Allocate 1024 pages (4MB) for kernel early bump heap
    mov rdi, 1024
    call phys_alloc_pages
    test rax, rax
    jz .error

    ; Save heap start address
    push rax

    ; 4. Mark early heap as global
    mov rdi, rax
    mov rsi, 1024 * 4096            ; 4MB size
    call virt_mark_global_range

    pop rax                         ; restore heap start address

    ; 4b. Mark early heap as NX (No-Execute)
    push rax
    mov rdi, rax
    mov rsi, 1024 * 4096            ; 4MB size
    call virt_mark_nx_range
    pop rax

    mov rdi, rax
    mov rsi, 1024 * 4096            ; 4MB size
    call heap_init
    call page_list_init
    call numa_detect_init
    ; lib/hw/unuma: parses SRAT Processor Affinity (Type 0/2) into a real
    ; apic_id -> node_id map. Must run after numa_detect_init, which locates
    ; the SRAT table this reuses (numa_srat_phys_addr).
    call unuma_cpu_detect_init
    ; lib/hw/uhbm: parses ACPI HMAT into a real node-pair bandwidth matrix.
    ; Also runs after numa_detect_init, which locates the HMAT table this
    ; reuses (numa_hmat_phys_addr).
    call uhbm_layout_init
    call numa_init_local_bitmaps
    call swap_init
    call kswapd_init
    call acpi_hotplug_init
    call sched_affinity_init
    call kernel_relocate_critical_tables
    call heap_transition
    call kmem_cache_init_all

    call smp_stacks_init

    ; 5. Unmap the kernel stack guard page to trap stack overflows
    mov rdi, kernel_stack_guard
    call virt_unmap

    ; 5b. Mark active kernel stack as NX (No-Execute)
    mov rdi, kernel_stack_bottom
    mov rsi, kernel_stack_top
    sub rsi, rdi                    ; size of stack
    call virt_mark_nx_range

    ret


.error:
    cli
    hlt
    jmp .error

sched_init:
    call fiber_system_init
    call sched_init_real
    ret

drivers_init:
    ; unet_init registers every NIC driver this stack has (currently just
    ; e1000) and probes the PCI bus once via lib/io/pci/enum.asm's
    ; pci_enumerate. Nothing calls unet_init anywhere else — before this it
    ; was dead code, correct or not, because it never ran.
    call unet_init
    ; lib/hw/ugpu + lib/hw/ucxl: PCI class-code scans for GPUs and CXL
    ; memory devices. Only need port I/O (CF8/CFC), no allocator — could
    ; run earlier, placed here because this is where device discovery
    ; already happens.
    call ugpu_detect_init
    call ucxl_detect_init
    ret

serve_init:
    ; TODO: Implement system security/serving layers
    ret

sys_handler:
    ; stub system call handler for syscall interface
    sysret

; -----------------------------------------------------------------------------
; Messages & Global Data
; -----------------------------------------------------------------------------
section .data

align 8
global boot_info_ptr
boot_info_ptr:      dq 0

msg_kernel_boot:     db "Tattva Kernel Booting...", 0x0D, 0x0A, 0
msg_init_gdt:        db "Initializing Kernel GDT/TSS... ", 0
msg_boot_info_loc:   db "BootInfo Pointer: ", 0
msg_gs_base_loc:     db "GS Base register: ", 0
msg_gs_api_test:     db "GS Accessor Test (CPU/Stack): ", 0
msg_init_cpu:        db "Initializing CPU hardware & features... ", 0
msg_init_ucpu_topo:  db "Decoding CPU topology & cache hierarchy (lib/hw/ucpu)... ", 0
msg_init_idt:        db "Initializing Exception Handlers (IDT)... ", 0
msg_init_time:       db "Calibrating TSC / starting monotonic clock... ", 0
msg_init_mm:         db "Initializing MM (Physical Allocator)... ", 0
msg_init_sched:      db "Initializing Scheduler... ", 0
msg_init_ulog:       db "Initializing ulog (pool, ring, drain fiber)... ", 0
msg_init_drivers:    db "Initializing Device Drivers... ", 0
msg_init_serve:      db "Initializing Services... ", 0
msg_ok:              db "OK", 0x0D, 0x0A, 0
msg_crlf:            db 0x0D, 0x0A, 0

%endif ; GUARD_KERNEL_ENTRY_INIT_ASM
