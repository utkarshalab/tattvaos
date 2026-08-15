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

%include "lib/percpu.inc"

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
; bsp_cpu_local is a real instance of percpu_t (lib/percpu.inc), not a second,
; hand-maintained copy of its layout. It used to be the latter — a field list
; here that had to be kept in step with the struc by hand — and it drifted:
; percpu_t grew five io fields (current_req through irq_stack) and, most
; recently, log_ring, while this stayed at its original 112 bytes. Every field
; from .current_fiber onward then sat 16 bytes into the *next* thing in
; .data, and log_ring_alloc_for_this_cpu's `mov [gs:percpu_t.log_ring], rbx`
; landed 8 bytes past .steal_lock's original end entirely — the io-fields gap
; percpu.inc's own header comment already tells this exact story about,
; happening again through a new door. `istruc`/`at`/`iend` builds this
; directly from the struc definition, so a future field can't silently do
; this a third time.
bsp_cpu_local:
istruc percpu_t
    at percpu_t.self,            dq bsp_cpu_local
    at percpu_t.cpu_id,          dd 0
    at percpu_t.lapic_id,        dd 0
    at percpu_t.stack_top,       dq kernel_stack_top
    at percpu_t.arena,           dq 0
    at percpu_t.current_req,     dq 0
    at percpu_t.submit_ring,     dq 0
    at percpu_t.complete_ring,   dq 0
    at percpu_t.nvme_sq,         dq 0
    at percpu_t.nvme_cq,         dq 0
    at percpu_t.irq_stack,       dq 0
    at percpu_t.current_fiber,   dq 0
    at percpu_t.idle_fiber,      dq 0
    at percpu_t.run_queue_head,  dq 0
    at percpu_t.run_queue_tail,  dq 0
    at percpu_t.fiber_count,     dd 0
    at percpu_t.steal_lock,      dd 0
    at percpu_t.ticks,           dq 0
    at percpu_t.log_ring,        dq 0
iend

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
