%ifndef GUARD_KERNEL_ENTRY_MAIN_ASM
%define GUARD_KERNEL_ENTRY_MAIN_ASM
; =============================================================================
; Tattva OS â€” kernel/entry/main.asm
; =============================================================================
; Kernel main entry point. Invoked after subsystem initialization completes.
; Prints the final kernel ready message and transitions to the CPU idle loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

; kernel/entry/main.asm is included ahead of kernel/sched/fiber.asm in
; kernel/entry.asm's %include order, so PRIO_NORMAL/FIBER_RESTART_ALWAYS
; below aren't defined yet by the time this file is assembled unless pulled
; in directly — guarded, so this is a harmless no-op once fiber.asm's own
; %include of the same file runs later.
%include "kernel/sched/fiber.inc"
%include "lib/mem/mem.inc"

section .text

global kernel_main

kernel_main:
    ; 1. Exercise the minimum PMM/direct-map contract before advertising ready.
    call kernel_boot_memory_selftest

    ; 2. Print kernel execution ready state
    mov rsi, msg_kernel_ready
    call uart_print_str

    ; 3. Spawn a heartbeat fiber and hand off to the real scheduler loop.
    ;
    ; Every subsystem up to this point has only ever been proven by its own
    ; init routine returning without crashing — kernel_main itself has never
    ; run a fiber, context-switched, or produced output after boot. The
    ; heartbeat fiber is a minimal, indefinite proof of the cooperative
    ; scheduler doing what it's built to do: sched_core_loop pops it, plants
    ; it as the running fiber via a real fiber_switch, it prints and calls
    ; fiber_yield, sched_core_loop pops it again next pass. Anything wrong
    ; with fiber_create's stack setup, pkey_switch, or the ready queue shows
    ; up as a crash or silence within the first second instead of staying
    ; latent until something else exercises it first.
    mov rdi, heartbeat_fiber
    xor rsi, rsi                    ; no argument
    mov rdx, PRIO_NORMAL
    mov rcx, FIBER_RESTART_ALWAYS   ; a dead heartbeat should restart, not vanish
    call fiber_create
    test rax, rax
    jnz .have_heartbeat

    mov rsi, msg_heartbeat_spawn_failed
    call uart_print_str

.have_heartbeat:
    ; 3b. Spawn the network poll fiber. unet_init (called from drivers_init,
    ; earlier in kernel_init) only brings the stack up; nothing drives RX/TX
    ; without something calling unet_poll on a schedule, same as the
    ; heartbeat above proves the scheduler itself is alive.
    mov rdi, net_poll_fiber
    xor rsi, rsi
    mov rdx, PRIO_NORMAL
    mov rcx, FIBER_RESTART_ALWAYS
    call fiber_create
    test rax, rax
    jnz .have_net_poll

    mov rsi, msg_net_poll_spawn_failed
    call uart_print_str

.have_net_poll:
    ; All shared initialization and initial fiber creation are complete.
    ; Only now copy/seal the trampoline and start APs: while an AP waits with
    ; interrupts disabled it cannot receive a TLB shootdown, so starting it
    ; before drivers/services finish changing shared mappings is unsafe.
    call smp_start

    ; Publish the final online set, enable BSP interrupts, and release APs.
    call smp_release
    call smp_timer_verify
    jc .timer_failed
    call smp_sched_lifecycle_selftest
    jc .timer_failed

    ; Enter the scheduler's own core loop. Never returns: sched_core_loop
    ; is what used to be this file's manual `cli; hlt` idle loop, except it
    ; actually polls, reaps, and runs fibers instead of just waiting for an
    ; interrupt no driver here yet raises.
    jmp sched_core_loop

.timer_failed:
    cli
    hlt
    jmp .timer_failed

; -----------------------------------------------------------------------------
; kernel_boot_memory_selftest — prove the Phase-A PMM/direct-map contract
; before kernel_main reports the system ready.
; -----------------------------------------------------------------------------
kernel_boot_memory_selftest:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Software address translation must agree with the PML4 slot selected by
    ; hardware.  Software-only shuffling cannot change a CPU page-table walk.
    cmp word [pml4_shuffle_map + 2], 1
    jne .failed

    mov r12, [phys_state + phys_state_t.free_pages]
    call phys_alloc_page
    test rax, rax
    jz .failed
    mov rbx, rax

    test rbx, 4095
    jnz .failed
    mov rdi, rbx
    mov rsi, 1
    call phys_range_is_online_usable
    test rax, rax
    jz .failed

    mov rax, 0x544154545641504D     ; "TATTVAPM"
    mov [rbx], rax
    cmp [rbx], rax
    jne .release_failed

    mov rdi, rbx
    call phys_free_page
    cmp [phys_state + phys_state_t.free_pages], r12
    jne .failed
    cmp qword [rbx], 0
    jne .failed
    cmp qword [rbx + 4088], 0
    jne .failed

    ; A second release must not change counters.  Permanent metadata remains
    ; owned by the kernel and additionally proves rejection happens pre-zero.
    mov rdi, rbx
    call phys_free_page
    cmp [phys_state + phys_state_t.free_pages], r12
    jne .failed

    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    mov r13, [rdi]
    test r13, r13
    jz .failed
    call phys_free_page
    cmp [phys_state + phys_state_t.free_pages], r12
    jne .failed
    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    cmp [rdi], r13
    jne .failed

    ; When firmware published a usable NUMA node wholly above 4 GiB, prove
    ; that the node-local allocator and generic free path agree on ownership,
    ; direct-map access, zeroing, and both local/global counters.  Skip tiny or
    ; low-only nodes; the QEMU two-node high-memory contract must execute it.
    cmp qword [numa_local_bitmaps_active], 1
    jne .passed
    cmp qword [numa_node_count], 2
    jb .passed
    cmp qword [phys_state + phys_state_t.highmem_ready], 1
    jne .passed

    mov r13, 1                     ; node 0 was already exercised above
.find_test_node:
    cmp r13, [numa_node_count]
    jae .passed
    mov rax, r13
    imul rax, numa_node_t_size
    lea r14, [numa_nodes + rax]
    mov eax, [r14 + numa_node_t.flags]
    and eax, 3                     ; active and local bitmap initialized
    cmp eax, 3
    jne .next_test_node
    cmp qword [r14 + numa_node_t.start_page], (PHYS_BOOTSTRAP_MAP_LIMIT >> 12)
    jb .next_test_node
    mov r15, [r14 + numa_node_t.free_pages]
    mov rax, [r14 + numa_node_t.pages_min]
    inc rax
    cmp r15, rax
    jb .next_test_node

    mov rbx, [r14 + numa_node_t.reserved_pages]
    mov rbp, [phys_state + phys_state_t.reserved_pages]
    mov rdi, r13
    call phys_alloc_page_node
    test rax, rax
    jz .failed
    mov r13, rax
    mov rax, PHYS_BOOTSTRAP_MAP_LIMIT
    cmp r13, rax
    jb .numa_release_failed

    mov rax, r15
    dec rax
    cmp [r14 + numa_node_t.free_pages], rax
    jne .numa_release_failed
    mov rax, r12
    dec rax
    cmp [phys_state + phys_state_t.free_pages], rax
    jne .numa_release_failed
    mov rax, rbx
    inc rax
    cmp [r14 + numa_node_t.reserved_pages], rax
    jne .numa_release_failed
    mov rax, rbp
    inc rax
    cmp [phys_state + phys_state_t.reserved_pages], rax
    jne .numa_release_failed

    mov rdi, r13
    lea rsi, [r13 + 4096]
    call numa_range_owner
    mov edx, [r14 + numa_node_t.node_id]
    cmp eax, edx
    jne .numa_release_failed

    mov rax, 0x4E554D414E4F4445     ; "NUMANODE"
    mov [r13], rax
    cmp [r13], rax
    jne .numa_release_failed
    not rax
    mov [r13 + 4088], rax
    cmp [r13 + 4088], rax
    jne .numa_release_failed

    mov rdi, r13
    call phys_free_page
    cmp [r14 + numa_node_t.free_pages], r15
    jne .failed
    cmp [phys_state + phys_state_t.free_pages], r12
    jne .failed
    cmp [r14 + numa_node_t.reserved_pages], rbx
    jne .failed
    cmp [phys_state + phys_state_t.reserved_pages], rbp
    jne .failed
    cmp qword [r13], 0
    jne .failed
    cmp qword [r13 + 4088], 0
    jne .failed

    mov rsi, msg_boot_numa_selftest_pass
    call uart_print_str
    jmp .passed

.next_test_node:
    inc r13
    jmp .find_test_node

.passed:
    mov rsi, msg_boot_memory_selftest_pass
    call uart_print_str
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.release_failed:
    mov rdi, rbx
    call phys_free_page
    jmp .failed

.numa_release_failed:
    mov rdi, r13
    call phys_free_page

.failed:
    mov rsi, msg_boot_memory_selftest_fail
    call uart_print_str
    cli
.halt:
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; heartbeat_fiber — proves the scheduler is alive: print, pace, yield, repeat.
; Runs as PRIO_NORMAL/FIBER_RESTART_ALWAYS, forever, on its own fiber stack.
; -----------------------------------------------------------------------------
heartbeat_fiber:
.loop:
    mov rsi, msg_heartbeat_prefix
    call uart_print_str
    mov eax, [heartbeat_count]
    call uart_print_dec
    mov rsi, msg_heartbeat_crlf
    call uart_print_str
    inc dword [heartbeat_count]

    ; Paced to be legible on a serial console, not to be a real timer. APIC
    ; timer interrupts do not yet preempt cooperative fibers, so pacing is
    ; this fiber spin-waiting then yielding — the same voluntary-yield model
    ; every other fiber here is expected to use.
    mov rdi, 1000                   ; 1000ms
    call mdelay
    call fiber_yield
    jmp .loop

; -----------------------------------------------------------------------------
; net_poll_fiber — drives unet_poll (e1000 RX/TX + tcp_timer_tick) on the
; same voluntary-yield pattern as heartbeat_fiber. The APIC timer does not
; preempt fibers and e1000_poll is pure polling, so 10ms remains the receive
; latency budget until an interrupt RX path exists.
; -----------------------------------------------------------------------------
net_poll_fiber:
.loop:
    call unet_poll
    mov rdi, 10                     ; 10ms
    call mdelay
    call fiber_yield
    jmp .loop

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
section .data

msg_boot_memory_selftest_pass: db 'Boot memory self-test: PASS', 0x0D, 0x0A, 0
msg_boot_numa_selftest_pass: db 'NUMA high-node R/W/free: PASS', 0x0D, 0x0A, 0
msg_boot_memory_selftest_fail: db 'KERNEL PANIC: boot memory self-test failed', 0x0D, 0x0A, 0
msg_kernel_ready:     db 'Tattva Kernel Ready. Entering main execution.', 0x0D, 0x0A, 0
msg_heartbeat_prefix: db 'heartbeat #', 0
msg_heartbeat_spawn_failed: db 'WARN: heartbeat fiber_create failed (no free FCB slots?)', 0x0D, 0x0A, 0
msg_heartbeat_crlf:    db 0x0D, 0x0A, 0
msg_net_poll_spawn_failed: db 'WARN: net_poll fiber_create failed (no free FCB slots?)', 0x0D, 0x0A, 0

section .bss
align 4
heartbeat_count: resd 1

; Every file this codebase includes after this one assumes it's arriving in
; .text unless it declares its own section — kernel/drivers/serial/uart.asm,
; %include'd immediately after this file, is one of them. Leaving the active
; section as .bss here silently discarded its entire contents: NASM computed
; real-looking addresses for uart_putc/uart_print_str/etc., but a .bss
; section holds no bytes, so every one of those functions and dbg_start_msg
; the caller thought it was calling into or reading from resolved into
; unpopulated, all-zero memory. cpu_clear_gprs — next in the include order
; after uart.asm — happens to declare `section .text` at its own top and
; masked the effect: everything from cpu.asm onward is real code again, only
; uart.asm's own content silently wasn't.
section .text

%endif ; GUARD_KERNEL_ENTRY_MAIN_ASM
