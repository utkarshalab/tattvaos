%ifndef GUARD_VERTEX_AGENT_MAIN_ASM
%define GUARD_VERTEX_AGENT_MAIN_ASM
; =============================================================================
; vertex-agent — CRI Runtime Main Entry Point
; =============================================================================
; Translates kubelet CRI gRPC calls → Utkarsha OS primitives
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/percpu.inc"
%include "lib/mem/mem.inc"
%include "lib/ulib/vec.inc"
%include "lib/ulog/ulog.inc"
%include "security/usrauth/usrauth.inc"
%include "net/unet/unet.inc"
%include "storage/uxfs/uxfs.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_agent_main — Entry point (called by ish as supervised app)
; -----------------------------------------------------------------------------
global vertex_agent_main
vertex_agent_main:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Early logging (before heap, before GS)
    call ulog_early_init
    mov rsi, msg_starting
    call uart_print_str

    ; 2. Initialize GS base for this fiber (already done by kernel for app fibers)
    ;    Verify we have a valid percpu_t
    call cpu_get_id
    test eax, eax
    jz .panic_no_cpu_id

    ; 3. Initialize full ulog (needs heap + scheduler)
    mov rsi, msg_init_ulog
    call uart_print_str
    call ulog_full_init
    test rax, rax
    jz .panic_ulog
    mov rsi, msg_ok
    call uart_print_str

    ; 4. Verify capabilities from manifest
    mov rsi, msg_check_caps
    call uart_print_str
    call vertex_agent_verify_caps
    test rax, rax
    jz .panic_caps
    mov rsi, msg_ok
    call uart_print_str

    ; 5. Initialize subsystems
    call vertex_agent_subsys_init

    ; 6. Start gRPC server fiber
    mov rsi, msg_start_grpc
    call uart_print_str
    call vertex_grpc_server_start
    test rax, rax
    jz .panic_grpc
    mov rsi, msg_ok
    call uart_print_str

    ; 7. Start background fibers
    call vertex_agent_start_background_fibers

    ; 8. Main loop: wait for shutdown signal
    mov rsi, msg_running
    call uart_print_str
    call vertex_agent_main_loop

    ; Normal shutdown
    call vertex_agent_shutdown
    xor rax, rax
    jmp .done

.panic_no_cpu_id:
    mov rsi, msg_panic_no_cpu
    call uart_print_str
    jmp .panic

.panic_ulog:
    mov rsi, msg_panic_ulog
    call uart_print_str
    jmp .panic

.panic_caps:
    mov rsi, msg_panic_caps
    call uart_print_str
    jmp .panic

.panic_grpc:
    mov rsi, msg_panic_grpc
    call uart_print_str
    jmp .panic

.panic:
    cli
    hlt
    jmp .panic

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_agent_verify_caps — Check we have all declared capabilities
; Returns: RAX = 1 (ok), 0 (missing)
; -----------------------------------------------------------------------------
vertex_agent_verify_caps:
    push rbx
    push r12

    ; Check each capability via usrauth_cap_check
    ; Capability handles are stored in our fiber's subject
    ; TODO: Implement capability verification against manifest

    mov rax, 1
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_agent_subsys_init — Initialize all vertex-agent subsystems
; -----------------------------------------------------------------------------
vertex_agent_subsys_init:
    push rbx

    ; Initialize sandbox manager
    mov rsi, msg_init_sandbox
    call uart_print_str
    call vertex_sandbox_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    ; Initialize container manager
    mov rsi, msg_init_container
    call uart_print_str
    call vertex_container_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    ; Initialize image manager
    mov rsi, msg_init_image
    call uart_print_str
    call vertex_image_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    ; Initialize network manager
    mov rsi, msg_init_network
    call uart_print_str
    call vertex_network_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    ; Initialize volume manager
    mov rsi, msg_init_volume
    call uart_print_str
    call vertex_volume_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    ; Initialize exec handler
    mov rsi, msg_init_exec
    call uart_print_str
    call vertex_exec_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    ; Initialize metrics collector
    mov rsi, msg_init_metrics
    call uart_print_str
    call vertex_metrics_init
    test rax, rax
    jz .fail
    mov rsi, msg_ok
    call uart_print_str

    pop rbx
    ret

.fail:
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_agent_start_background_fibers — Spawn background worker fibers
; -----------------------------------------------------------------------------
vertex_agent_start_background_fibers:
    push rbx
    push r12

    ; GC fiber: cleanup dead containers, unused image layers
    mov rdi, vertex_gc_fiber
    xor rsi, rsi
    mov rdx, PRIO_LOW
    mov rcx, FIBER_RESTART_ON_FAILURE
    call fiber_create
    test rax, rax
    jz .fail
    mov [gc_fiber_handle], rax

    ; Image GC fiber: cleanup unused layers
    mov rdi, vertex_image_gc_fiber
    xor rsi, rsi
    mov rdx, PRIO_LOW
    mov rcx, FIBER_RESTART_ON_FAILURE
    call fiber_create
    test rax, rax
    jz .fail
    mov [image_gc_fiber_handle], rax

    ; Metrics collector fiber
    mov rdi, vertex_metrics_collector_fiber
    xor rsi, rsi
    mov rdx, PRIO_LOW
    mov rcx, FIBER_RESTART_ALWAYS
    call fiber_create
    test rax, rax
    jz .fail
    mov [metrics_fiber_handle], rax

    pop r12
    pop rbx
    ret

.fail:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_agent_main_loop — Wait for shutdown signal
; -----------------------------------------------------------------------------
vertex_agent_main_loop:
.loop:
    ; Check shutdown flag (set by signal handler)
    mov rax, [shutdown_requested]
    test rax, rax
    jnz .shutdown

    ; Yield to other fibers
    call fiber_yield
    jmp .loop

.shutdown:
    ret


; -----------------------------------------------------------------------------
; vertex_agent_shutdown — Graceful shutdown
; -----------------------------------------------------------------------------
vertex_agent_shutdown:
    push rbx
    push r12

    mov rsi, msg_shutdown
    call uart_print_str

    ; 1. Stop accepting new gRPC requests
    call vertex_grpc_server_stop

    ; 2. Wait for in-flight requests to complete (timeout 30s)
    mov rdi, 30000000000      ; 30 seconds in nanoseconds
    call vertex_grpc_drain

    ; 3. Stop background fibers
    mov rdi, [gc_fiber_handle]
    test rdi, rdi
    jz .skip_gc
    call fiber_kill
.skip_gc:
    mov rdi, [image_gc_fiber_handle]
    test rdi, rdi
    jz .skip_img_gc
    call fiber_kill
.skip_img_gc:
    mov rdi, [metrics_fiber_handle]
    test rdi, rdi
    jz .skip_metrics
    call fiber_kill
.skip_metrics:

    ; 4. Flush logs
    call ulog_flush_all

    ; 5. Shutdown subsystems
    call vertex_network_shutdown
    call vertex_volume_shutdown
    call vertex_image_shutdown
    call vertex_container_shutdown
    call vertex_sandbox_shutdown

    mov rsi, msg_shutdown_done
    call uart_print_str

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Background Fibers
; -----------------------------------------------------------------------------

vertex_gc_fiber:
    ; Periodic garbage collection of dead containers
    ; Runs every 60 seconds
.loop:
    mov rdi, 60000000000      ; 60 seconds
    call mono_sleep_ns
    call vertex_gc_collect
    jmp .loop

vertex_image_gc_fiber:
    ; Periodic image layer garbage collection
    ; Runs every 300 seconds (5 minutes)
.loop:
    mov rdi, 300000000000     ; 300 seconds
    call mono_sleep_ns
    call vertex_image_gc_collect
    jmp .loop

vertex_metrics_collector_fiber:
    ; Periodic metrics collection for CRI stats
    ; Runs every 10 seconds
.loop:
    mov rdi, 10000000000      ; 10 seconds
    call mono_sleep_ns
    call vertex_metrics_collect
    jmp .loop


; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------
section .data
align 8

gc_fiber_handle:        dq 0
image_gc_fiber_handle:  dq 0
metrics_fiber_handle:   dq 0
shutdown_requested:     dq 0

msg_starting:           db "vertex-agent: Starting CRI runtime...", 0x0D, 0x0A, 0
msg_init_ulog:          db "  Initializing ulog... ", 0
msg_check_caps:         db "  Verifying capabilities... ", 0
msg_init_sandbox:       db "  Initializing sandbox manager... ", 0
msg_init_container:     db "  Initializing container manager... ", 0
msg_init_image:         db "  Initializing image manager... ", 0
msg_init_network:       db "  Initializing network manager... ", 0
msg_init_volume:        db "  Initializing volume manager... ", 0
msg_init_exec:          db "  Initializing exec handler... ", 0
msg_init_metrics:       db "  Initializing metrics collector... ", 0
msg_start_grpc:         db "  Starting gRPC server... ", 0
msg_running:            db "vertex-agent: Running on [::]:10010", 0x0D, 0x0A, 0
msg_shutdown:           db "vertex-agent: Shutting down...", 0x0D, 0x0A, 0
msg_shutdown_done:      db "vertex-agent: Shutdown complete", 0x0D, 0x0A, 0
msg_ok:                 db "OK", 0x0D, 0x0A, 0

msg_panic_no_cpu:       db "PANIC: No CPU ID", 0x0D, 0x0A, 0
msg_panic_ulog:         db "PANIC: ulog init failed", 0x0D, 0x0A, 0
msg_panic_caps:         db "PANIC: Missing required capabilities", 0x0D, 0x0A, 0
msg_panic_grpc:         db "PANIC: gRPC server start failed", 0x0D, 0x0A, 0

%endif ; GUARD_VERTEX_AGENT_MAIN_ASM