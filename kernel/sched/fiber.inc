; =============================================================================
; Tattva OS — kernel/sched/fiber.inc
; =============================================================================
; Data structure definitions and constants for Ring-0 Cooperative Fibers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef FIBER_INC
%define FIBER_INC

; -----------------------------------------------------------------------------
; Constants
; -----------------------------------------------------------------------------
FIBER_STACK_SIZE    equ 16384       ; 16KB stack per fiber
FIBER_GUARD_SIZE    equ 4096        ; 4KB unmapped guard page below stack
FIBER_MAX_COUNT     equ 1024        ; Max fibers in system pool

; Fiber States
FIBER_STATE_FREE    equ 0           ; Unallocated slot in pool
FIBER_STATE_READY   equ 1           ; Ready to run in core queue
FIBER_STATE_RUNNING equ 2           ; Currently executing on a CPU core
FIBER_STATE_WAITING equ 3           ; Waiting for I/O or timer event
FIBER_STATE_DEAD    equ 4           ; Finished execution, pending cleanup

; -----------------------------------------------------------------------------
; Fiber Control Block (FCB) Structure
; Offset layout: 128 bytes total header size
; -----------------------------------------------------------------------------
struc fcb_t
    .rsp          resq 1            ; +00: Saved Stack Pointer (RSP)
    .rbp          resq 1            ; +08: Saved Base Pointer (RBP)
    .rbx          resq 1            ; +16: Callee-saved RBX
    .r12          resq 1            ; +24: Callee-saved R12
    .r13          resq 1            ; +32: Callee-saved R13
    .r14          resq 1            ; +40: Callee-saved R14
    .r15          resq 1            ; +48: Callee-saved R15
    .id           resq 1            ; +56: Unique Fiber ID
    .state        resd 1            ; +64: State (FREE, READY, RUNNING, WAITING, DEAD)
    .cpu_id       resd 1            ; +68: Currently assigned CPU core ID
    .stack_bottom resq 1            ; +72: Base address of 16KB stack allocation
    .stack_top    resq 1            ; +80: Top address of 16KB stack (initial RSP)
    .time_slice   resq 1            ; +88: Elapsed APIC ticks in current run
    .entry_point  resq 1            ; +96: Function pointer
    .arg          resq 1            ; +104: Argument passed to fiber function
    .next         resq 1            ; +112: Pointer to next FCB in queue
    .prev         resq 1            ; +120: Pointer to prev FCB in queue
endstruc

fcb_t_size equ 128

%endif ; FIBER_INC
