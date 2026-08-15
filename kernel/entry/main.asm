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

section .text

global kernel_main

kernel_main:
    ; 1. Print kernel execution ready state
    mov rsi, msg_kernel_ready
    call uart_print_str

    call run_all_memory_tests

    ; 2. Spawn a heartbeat fiber and hand off to the real scheduler loop.
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
    ; 2b. Spawn the network poll fiber. unet_init (called from drivers_init,
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
    ; 3. Enter the scheduler's own core loop. Never returns: sched_core_loop
    ; is what used to be this file's manual `cli; hlt` idle loop, except it
    ; actually polls, reaps, and runs fibers instead of just waiting for an
    ; interrupt no driver here yet raises.
    jmp sched_core_loop

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

    ; Paced to be legible on a serial console, not to be a real timer. There
    ; is no periodic interrupt wired up yet for this cooperative scheduler to
    ; preempt on, so pacing is this fiber spin-waiting then yielding — the
    ; same voluntary-yield model every other fiber here is expected to use.
    mov rdi, 1000                   ; 1000ms
    call mdelay
    call fiber_yield
    jmp .loop

; -----------------------------------------------------------------------------
; net_poll_fiber — drives unet_poll (e1000 RX/TX + tcp_timer_tick) on the
; same voluntary-yield pattern as heartbeat_fiber. 10ms is arbitrary — there's
; no interrupt-driven RX path yet (e1000_poll is pure polling), so this is
; the entire receive latency budget until one exists.
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
