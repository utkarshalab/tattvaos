; Object-level syntax/layout harness for the canonical fiber scheduler.
[BITS 64]
default rel

PAGE_PRESENT  equ (1 << 0)
PAGE_WRITABLE equ (1 << 1)
PAGE_NX       equ (1 << 63)

extern phys_alloc_pages
extern phys_free_pages
extern virt_map
extern virt_unmap
extern pkey_init
extern pkey_alloc
extern pkey_switch
extern canary_plant
extern canary_verify
extern fiber_guard_init
extern fiber_guard_trap
extern smp_sched_park_if_requested
extern smp_sched_percpu_for_id
extern smp_sched_send_wake
extern smp_sched_run_mask
extern smp_active_cores
extern smp_mpmc_pop
extern default_mxcsr

%include "kernel/sched/fiber.asm"
%include "kernel/sched/sched.asm"

%if SCHED_FRAME_SIZE != 176
    %error "canonical scheduler frame size changed"
%endif
%if SCHED_FRAME_RFLAGS != 152
    %error "canonical scheduler RFLAGS offset changed"
%endif
%if SCHED_FRAME_RSP != 160 || SCHED_FRAME_SS != 168
    %error "canonical scheduler stack-return offsets changed"
%endif
%if fcb_t_size != 256
    %error "FCB ABI size changed"
%endif
%if fcb_t.affinity != 192
    %error "FCB affinity offset changed"
%endif
%if percpu_t_size != 192
    %error "per-CPU cache-line stride changed"
%endif
%if percpu_t.resched_ipis != 152 || percpu_t.drained_fibers != 156
    %error "per-CPU scheduler counter offsets changed"
%endif
