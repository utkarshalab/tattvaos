%ifndef LIB_PERCPU_INC
%define LIB_PERCPU_INC
; =============================================================================
; Tattva OS — lib/percpu.inc
; =============================================================================
; THE canonical per-CPU block layout, reached through GS.
;
; This header exists because three subsystems previously invented their own GS
; offsets independently and two of them collided:
;
;   lib/io/io.inc      declared a 64-byte struct ending at .irq_stack
;   lib/mem/arena      wrote its per-core arena pointer to gs:24, which that
;                      struct had already assigned to .submit_ring
;   kernel/arch        used gs:16 as .stack_top, which it called .current_req
;   kernel/sched       used gs:64 .. gs:112 — entirely PAST the 64-byte block,
;                      i.e. inside the NEXT core's slot
;
; The last one is the dangerous one. Blocks are contiguous with a fixed stride,
; so on a single core the scheduler's writes landed in unused table space and
; nothing failed. On SMP they corrupt core N+1's self pointer, cpu_id and I/O
; ring pointers — silently, and only under load.
;
; RULES
;   1. Every per-CPU field is declared HERE, once, with a name.
;   2. No file may use a raw `gs:NN` offset. Use `percpu_t.field`.
;   3. The allocation stride comes from `percpu_t_size`, never a literal.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%define PERCPU_MAX_CORES    64

struc percpu_t
    ; ---- identity: kernel/arch/x86_64/cpu.asm ----
    .self           resq 1      ; +000  self pointer, for validation
    .cpu_id         resd 1      ; +008  logical CPU index
    .lapic_id       resd 1      ; +012  hardware Local APIC ID
    .stack_top      resq 1      ; +016  top of this core's kernel stack

    ; ---- memory: lib/mem/arena ----
    .arena          resq 1      ; +024  per-core bump arena

    ; ---- I/O: lib/io ----
    .current_req    resq 1      ; +032  io_request_t in flight (debug)
    .submit_ring    resq 1      ; +040  SPSC submission ring
    .complete_ring  resq 1      ; +048  SPSC completion ring
    .nvme_sq        resq 1      ; +056  NVMe submission queue
    .nvme_cq        resq 1      ; +064  NVMe completion queue
    .irq_stack      resq 1      ; +072  dedicated IST/IRQ stack

    ; ---- scheduler: kernel/sched ----
    .current_fiber  resq 1      ; +080
    .idle_fiber     resq 1      ; +088
    .run_queue_head resq 1      ; +096
    .run_queue_tail resq 1      ; +104
    .fiber_count    resd 1      ; +112
    .steal_lock     resd 1      ; +116  work-stealing spin flag
    .ticks          resq 1      ; +120

    ; ---- logging: lib/ulog/record ----
    .log_ring       resq 1      ; +128  this core's ring_t* (record/ring_alloc.asm)
endstruc                        ; = 136 bytes

%endif ; LIB_PERCPU_INC
