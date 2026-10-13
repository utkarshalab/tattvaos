; Object-level syntax/linkage harness for kernel/arch/x86_64/smp.asm.
[BITS 64]
default rel

phys_state_t.direct_map_limit equ 0

extern boot_info_ptr
extern phys_state
extern smp_cpu_stacks
extern smp_active_cores
extern bsp_cpu_local
extern virt_walk_table
extern uart_print_str
extern uart_print_dec
extern uart_putc
extern udelay
extern register_idt_handler
extern sched_init_real
extern sched_core_loop
extern sched_switch_frame
extern sched_drain_current_cpu
extern fiber_create_on_cpu
extern fiber_create_preemptible_on_cpu
extern fiber_yield
extern ucpu_topology_decode_current
extern ucpu_cache_topology_scan
extern sys_handler
extern default_mxcsr
extern idt_ptr
extern tsc_freq_hz
extern tlb_shootdown

%include "kernel/arch/x86_64/smp.asm"

%if fcb_t.affinity != 192 || fcb_t_size != 256
    %error "SMP scheduler affinity changed the FCB ABI"
%endif
%if percpu_t.resched_ipis != 152 || percpu_t.drained_fibers != 156
    %error "SMP scheduler counters changed the per-CPU ABI"
%endif
