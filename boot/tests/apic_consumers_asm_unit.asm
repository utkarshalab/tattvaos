; Object-level linkage/syntax harness for APIC-aware memory consumers.
[BITS 64]
default rel

%include "lib/mem/mem.inc"

NUMA_MAX_RANGES equ 32

extern phys_state
extern zram_in_use, zram_frames, zram_sizes
extern zswap_in_use, zswap_frames, zswap_sizes
extern phys_alloc_page, phys_free_page, memcpy
extern ram_swap_alloc_slot, ram_swap_write_page, ram_swap_free_slot
extern zswap_decompress_and_free, zram_read_page
extern lz4_decompress, rle_decompress
extern smp_send_all_others, smp_send_ipi, smp_lapic_eoi
extern udelay
extern uart_print_str, uart_print_dec, uart_print_hex64
extern boot_info_ptr, msg_crlf, register_idt_handler
extern numa_range_count, numa_ranges
extern buddy_generate_node, sched_migrate_threads_for_node

%include "lib/mem/virt/paging/tlb_shootdown.asm"
%include "lib/mem/virt/reclaim/zpool.asm"
%include "lib/mem/virt/hardware/acpi_hotplug.asm"
