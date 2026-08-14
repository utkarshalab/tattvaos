; =============================================================================
; lib/io/core/init.asm
; Top-level I/O subsystem initialization wiring sequence (io_init).
;
; Implements the spec §8 initialization flow, bringing up serial, ACPI scan,
; per-CPU structures, PIC remap, Local APIC + IO-APIC, PCI bus enumeration,
; driver probing, DMA buffers, and per-core async rings.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_INIT_ASM
%define IO_CORE_INIT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; Subsystem module initialization entry points















; Static driver bindings registered at probe time
section .data
align 8
virtio_blk_driver_binding:
istruc driver_binding_t
    at driver_binding_t.vendor_id,   dw 0x1AF4
    at driver_binding_t.device_id,   dw 0x1001
    at driver_binding_t.class_mask,  dd 0
    at driver_binding_t.class_match, dd 0
    at driver_binding_t.probe_fn,    dq virtio_blk_probe
iend

section .text

; =============================================================================
; io_init — Initialize the entire I/O subsystem (BSP path)
; In : RDI = -> boot_handoff_t parameter structure from bootloader
; Out: RAX = 0 on success, or negative error code (from acpi, dma, pci bands)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC io_init
    guard_null rdi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rbx, rdi                ; RBX = -> boot_handoff_t

    ; 1. Ingest bootloader parameters
    mov     rdi, rbx
    call    handoff_ingest
    test    rax, rax
    jnz     .fail

    ; 2. Initialize debug serial port (Try COM1 first, fallback to COM2 if COM1 is missing)
    mov     rdi, 0x3F8
    call    serial_init
    test    rax, rax
    jz      .serial_ok              ; COM1 succeeded!

    ; COM1 failed. Attempt COM2 (0x2F8)
    mov     rdi, 0x2F8
    call    serial_init
    test    rax, rax
    jz      .serial_ok              ; COM2 succeeded!

    ; Both failed. Set global_serial_port to 0 to disable milestones
    mov     word [rel global_serial_port], 0
    jmp     .serial_done

.serial_ok:
    mov     [rel global_serial_port], di ; Write the working port base to the redirector

.serial_done:

    ; 3. Emit early initialization milestone
    lea     rdi, [rel .msg_init]
    call    console_milestone

    ; 4. Parse ACPI tables (RSDP address passed in boot parameters)
    mov     rdi, [rbx + boot_handoff_t.rsdp]
    call    acpi_scan
    test    rax, rax
    jnz     .fail

    ; 5. Initialize per-CPU storage base for BSP (core 0)
    call    percpu_init
    test    rax, rax
    jnz     .fail

    ; 6. Register exception handlers (Double Fault + Spurious vector)
    mov     rdi, 0x08               ; Double Fault
    lea     rsi, [rel io_exception_df_handler]
    mov     rdx, 1                  ; IST 1
    call    idt_register_handler

    mov     rdi, 0xFF               ; Spurious Vector
    lea     rsi, [rel io_spurious_handler]
    xor     rdx, rdx                ; No IST
    call    idt_register_handler

    ; 7. Remap legacy PIC interrupts and mask them
    call    pic_remap

    ; 8. Initialize Local APIC and arm the timer vector 0x30
    call    lapic_init
    mov     rdi, 1000000            ; Timer initial count ticks
    mov     rsi, 0x30               ; Timer Vector
    call    lapic_timer_start

    ; 9. Pre-register dynamic PCI drivers
    lea     rdi, [rel virtio_blk_driver_binding]
    call    driver_register
    test    rax, rax
    jnz     .fail

    ; 10. Walk PCI/PCIe buses and probe matching devices (virtio-blk)
    call    pci_enumerate

    ; 11. Initialize DMA allocations and bounce buffer pool
    call    dma_init
    test    rax, rax
    jnz     .fail

    ; 12. Allocate per-core lockless SPSC submission and completion rings
    call    async_init
    test    rax, rax
    jnz     .fail

    ; 13. System fully armed
    lea     rdi, [rel .msg_ready]
    call    console_milestone

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.fail:
    ; Emit failure log
    mov     rbx, rax                ; RBX = failed error code
    lea     rdi, [rel .msg_fail]
    call    console_milestone
    mov     rax, rbx                ; Return failed code

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC io_init

; =============================================================================
; dma_init — Pre-allocate bounce buffer pool for 32-bit addressing DMA
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC dma_init
    call    bounce_init
IO_ENDFUNC dma_init

; =============================================================================
; async_init — Allocate submission/completion SPSC rings for current CPU
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC async_init
    push    r12
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; 1. Get percpu block for current CPU
    call    percpu_get
    test    rax, rax
    jz      .err_null
    mov     rbx, rax                ; RBX = -> percpu_t

    ; 2. Allocate submission ring descriptor
    mov     rdi, spsc_ring_t_size
    mov     rsi, 64
    xor     rdx, rdx
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem
    mov     [rbx + percpu_t.submit_ring], rbx ; virtual base is in RBX from dma_alloc
    mov     r12, rbx                ; R12 = -> submit_ring

    ; Allocate submission ring queue buffer array (128 entries of 8 bytes = 1024 bytes)
    mov     rdi, 1024
    mov     rsi, 64
    xor     rdx, rdx
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem

    mov     qword [r12 + spsc_ring_t.mask], 127
    mov     [r12 + spsc_ring_t.buffer], rbx
    mov     qword [r12 + spsc_ring_t.entry_size], 8
    mov     qword [r12 + spsc_ring_t.capacity], 128
    mov     qword [r12 + spsc_ring_t.prod_idx], 0
    mov     qword [r12 + spsc_ring_t.cons_idx], 0

    ; 3. Allocate completion ring descriptor
    mov     rdi, spsc_ring_t_size
    mov     rsi, 64
    xor     rdx, rdx
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem
    mov     [rbx + percpu_t.complete_ring], rbx
    mov     r12, rbx                ; R12 = -> complete_ring

    ; Allocate completion ring queue buffer array (128 entries of 32 bytes = 4096 bytes)
    mov     rdi, 128 * io_completion_t_size
    mov     rsi, 64
    xor     rdx, rdx
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem

    mov     qword [r12 + spsc_ring_t.mask], 127
    mov     [r12 + spsc_ring_t.buffer], rbx
    mov     qword [r12 + spsc_ring_t.entry_size], io_completion_t_size
    mov     qword [r12 + spsc_ring_t.capacity], 128
    mov     qword [r12 + spsc_ring_t.prod_idx], 0
    mov     qword [r12 + spsc_ring_t.cons_idx], 0

    xor     rax, rax                ; Return 0
    jmp     .exit

.err_null:
    mov     rax, IO_ERR_NULL
    jmp     .exit

.err_nomem:
    mov     rax, IO_ERR_NOMEM

.exit:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     r12
IO_ENDFUNC async_init

section .rodata
.msg_init:  db "IO:INIT", 0
.msg_ready: db "IO:READY", 0
.msg_fail:  db "IO:FAIL", 0

%endif ; IO_CORE_INIT_ASM
