; Object-level syntax/linkage harness for kernel/arch/x86_64/smp.asm.
[BITS 64]
default rel

phys_state_t.direct_map_limit equ 0

extern boot_info_ptr
extern phys_state
extern smp_cpu_stacks
extern smp_active_cores
extern virt_walk_table
extern uart_print_str
extern uart_print_dec
extern uart_putc
extern udelay
extern register_idt_handler
extern sched_init_real
extern sched_core_loop
extern ucpu_topology_decode_current
extern ucpu_cache_topology_scan
extern sys_handler
extern default_mxcsr
extern idt_ptr

%include "kernel/arch/x86_64/smp.asm"
