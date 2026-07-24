; =============================================================================
; Tattva OS — kernel/sched/fiber.inc
; =============================================================================
; Ultimate Enterprise Fiber Control Block (FCB) and Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef FIBER_INC
%define FIBER_INC

; -----------------------------------------------------------------------------
; Constants
; -----------------------------------------------------------------------------
FIBER_STACK_SIZE    equ 16384       ; 16KB stack payload per fiber
FIBER_GUARD_SIZE    equ 4096        ; 4KB unmapped guard page (VMA_NONE)
FIBER_TOTAL_ALLOC   equ 20480       ; 20KB total allocation (Guard + Stack)
FIBER_MAX_COUNT     equ 1024        ; Max fibers in system pool

; Fiber States
FIBER_STATE_FREE    equ 0           ; Unallocated slot in pool
FIBER_STATE_READY   equ 1           ; Ready to run in core MLFQ queue
FIBER_STATE_RUNNING equ 2           ; Currently executing on a CPU core
FIBER_STATE_WAITING equ 3           ; Waiting for I/O or timer event
FIBER_STATE_DEAD    equ 4           ; Finished or crashed, pending cleanup/restart

; Priority Bands (MLFQ)
PRIO_REALTIME       equ 0           ; 0-latency real-time task
PRIO_HIGH           equ 1           ; Interactive high-priority task
PRIO_NORMAL         equ 2           ; Default normal priority task
PRIO_IDLE           equ 3           ; Background idle reclaim task

; Restart Policies (Self-Healing Supervisor)
FIBER_RESTART_NEVER     equ 0       ; One-shot task (clean up stack on exit/crash)
FIBER_RESTART_ALWAYS    equ 1       ; Daemon task (auto-restart on normal exit or crash)
FIBER_RESTART_TRANSIENT equ 2       ; Task auto-restarts only on hardware crash

; Stack Canary Secret Constant
CANARY_DEFAULT_MAGIC equ 0xDEADBEEFCAFEBABE

; -----------------------------------------------------------------------------
; Enterprise Fiber Control Block (FCB) Structure
; Offset layout: 256 bytes total header size (L1 Cache Line Aligned)
; -----------------------------------------------------------------------------
struc fcb_t
    .rsp             resq 1         ; +000: Saved Stack Pointer (RSP)
    .rbp             resq 1         ; +008: Saved Base Pointer (RBP)
    .rbx             resq 1         ; +016: Callee-saved RBX
    .r12             resq 1         ; +024: Callee-saved R12
    .r13             resq 1         ; +032: Callee-saved R13
    .r14             resq 1         ; +040: Callee-saved R14
    .r15             resq 1         ; +048: Callee-saved R15
    .id              resq 1         ; +056: Unique Fiber ID
    .state           resd 1         ; +064: 0=FREE, 1=READY, 2=RUNNING, 3=WAITING, 4=DEAD
    .prio            resd 1         ; +068: Priority band (0..3)
    .pkey            resd 1         ; +072: Intel PKEY Protection Key (0..15)
    .cpu_id          resd 1         ; +076: Currently assigned CPU core ID
    .stack_bottom    resq 1         ; +080: Base address of 16KB stack allocation
    .stack_top       resq 1         ; +088: Top address of 16KB stack
    .guard_addr      resq 1         ; +096: Physical address of 4KB unmapped guard page
    .restart_policy  resd 1         ; +104: 0=NEVER, 1=ALWAYS, 2=TRANSIENT
    .crash_count     resd 1         ; +108: Consecutive crash count for throttling
    .entry_point     resq 1         ; +112: Function pointer
    .arg             resq 1         ; +120: Argument passed to function
    .name            resq 1         ; +128: ASCIIZ Fiber Name string pointer
    .exec_cycles     resq 1         ; +136: Total CPU cycles spent executing (RDTSC)
    .canary          resq 1         ; +144: Secret Stack Canary Cookie
    .time_slice      resq 1         ; +152: APIC ticks in current run slice
    .next            resq 1         ; +160: Pointer to next FCB in queue
    .prev            resq 1         ; +168: Pointer to prev FCB in queue
    .reserved        resq 10        ; +176..+256: L1 Cache Line Padding
endstruc

fcb_t_size equ 256

%endif ; FIBER_INC
