%ifndef GUARD_KERNEL_ENTRY_START_ASM
%define GUARD_KERNEL_ENTRY_START_ASM
; =============================================================================
; Tattva OS — kernel/entry/start.asm
; =============================================================================
; Kernel startup logic. Reloads segment registers, sets up the 16KB aligned
; kernel stack, and configures the GS base register for CPU-local storage.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; kernel_start — first instructions executed inside kernel_entry
; -----------------------------------------------------------------------------
    ; 1. Reload 64-bit data segment registers (SEL_DATA64 = 0x10)
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; 2. Set up the aligned kernel stack
    mov rsp, kernel_stack_top

    ; 3. Preserve the BootInfo pointer passed in RDI
    push rdi

    ; 4. Initialize GS base MSR to point to BSP's CPU-local structure
    mov ecx, 0xC0000101             ; MSR_GS_BASE
    mov rax, bsp_cpu_local          ; low 32 bits
    mov rdx, rax
    shr rdx, 32                     ; high 32 bits (EDX:EAX)
    wrmsr

    ; 5. Sanitize CPU general purpose registers (excluding RSP/RDI)
    call cpu_clear_gprs

    ; 6. Restore BootInfo pointer and jump to early initialization
    pop rdi
    jmp kernel_init

; -----------------------------------------------------------------------------
; CPU-local Data Structures
; -----------------------------------------------------------------------------
section .data
align 8
bsp_cpu_local:
    .self        dq bsp_cpu_local   ; pointer to self (standard GS self-reference)
    .cpu_id      dd 0               ; CPU ID 0 for BSP
    .reserved    dd 0               ; explicit alignment padding
    .stack_top   dq kernel_stack_top; kernel stack top address
    .arena       dq 0               ; thread-local/core-local arena pointer (offset 24)
    .pool        dq 0               ; offset 32
    .reclaim     dq 0               ; offset 40
    .spare1      dq 0               ; offset 48
    .spare2      dq 0               ; offset 56
    .current_fiber  dq 0            ; GS:64
    .idle_fiber     dq 0            ; GS:72
    .run_queue_head dq 0            ; GS:80
    .run_queue_tail dq 0            ; GS:88
    .fiber_count    dd 0            ; GS:96
    .ticks          dq 0            ; GS:104
    .steal_lock     dd 0            ; GS:112

; -----------------------------------------------------------------------------
; Kernel Stack allocation with unmapped guard page
; -----------------------------------------------------------------------------
section .bss
alignb 4096
global kernel_stack_guard
kernel_stack_guard:
    resb 4096                       ; 4KB stack guard page
alignb 4096
kernel_stack_bottom:
    ; 64KB, not the 16KB this started as. The BSP runs the entire boot-time
    ; init chain on this one stack before any fiber/thread stack exists —
    ; phys_init, every virt_mark_*/virt_unmap call, heap_init, NUMA, ACPI
    ; hotplug, scheduler affinity, kmem_cache_init_all, smp_stacks_init — all
    ; nested, none of it tail-called. 16KB was enough to reach the guard-page
    ; unmap near the end of mm_init and not one call further: the very next
    ; nested call after `virt_unmap(kernel_stack_guard)` armed the trap it had
    ; just placed and walked straight into it. This isn't a runaway/recursive
    ; bug to chase — it's the genuine depth of a single-stack sequential boot,
    ; and it will only grow as more subsystems gain init-time work.
    resb 65536                      ; 64KB stack allocation
kernel_stack_top:


%endif ; GUARD_KERNEL_ENTRY_START_ASM
