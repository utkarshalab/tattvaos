; =============================================================================
; Tattva OS — lib/mem/mem.asm
; =============================================================================
; Memory management library top-level include wrapper.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_MEM_ASM
%define LIB_MEM_MEM_ASM

[BITS 64]

%include "lib/mem/mem.inc"
%include "lib/mem/ops/memcpy.asm"
%include "lib/mem/ops/memset.asm"
%include "lib/mem/ops/memzero.asm"
%include "lib/mem/ops/memcmp.asm"
%include "lib/mem/ops/memmove.asm"
%include "lib/mem/ops/user_copy.asm"
%include "lib/mem/phys/map.asm"
%include "lib/mem/phys/bitmap.asm"
%include "lib/mem/phys/phys.asm"
%include "lib/mem/heap/bump.asm"
%include "lib/mem/heap/free_list.asm"
%include "lib/mem/heap/leak_tracker.asm"
%include "lib/mem/heap/heap.asm"
%include "lib/mem/heap/defrag.asm"

%include "lib/mem/slab/slab.asm"
%include "lib/mem/slab/slab_create.asm"
%include "lib/mem/slab/slab_alloc.asm"
%include "lib/mem/slab/slab_free.asm"
%include "lib/mem/slab/slab_reap.asm"
%include "lib/mem/buddy/buddy.asm"
%include "lib/mem/arena/arena.asm"
%include "lib/mem/pool/pool.asm"
%include "lib/mem/numa/numa.asm"
%include "lib/mem/numa/numa_detect.asm"

; 1. Paging Subdirectory
%include "lib/mem/virt/paging/virt.asm"
%include "lib/mem/virt/paging/pgtable.asm"
%include "lib/mem/virt/paging/pgtable_map.asm"
%include "lib/mem/virt/paging/pgtable_unmap.asm"
%include "lib/mem/virt/paging/pgtable_walk.asm"
%include "lib/mem/virt/paging/pgtable_split.asm"
%include "lib/mem/virt/paging/pgtable_lock.asm"
%include "lib/mem/virt/paging/pgtable_cache.asm"
%include "lib/mem/virt/paging/tlb.asm"
%include "lib/mem/virt/paging/tlb_shootdown.asm"
%include "lib/mem/virt/paging/thp.asm"

; 2. Reclaim Subdirectory
%include "lib/mem/virt/reclaim/swap.asm"
%include "lib/mem/virt/reclaim/swap_device.asm"
%include "lib/mem/virt/reclaim/kswapd.asm"
%include "lib/mem/virt/reclaim/zswap.asm"
%include "lib/mem/virt/reclaim/zram.asm"
%include "lib/mem/virt/reclaim/zpool.asm"
%include "lib/mem/virt/reclaim/replacement.asm"
%include "lib/mem/virt/reclaim/balloon.asm"
%include "lib/mem/virt/reclaim/writeback.asm"
%include "lib/mem/virt/reclaim/mglru.asm"
%include "lib/mem/virt/reclaim/lz4.asm"

; 3. Coco Subdirectory
%include "lib/mem/virt/coco/sev.asm"
%include "lib/mem/virt/coco/tdx.asm"
%include "lib/mem/virt/coco/cca.asm"
%include "lib/mem/virt/coco/enc_swap.asm"
%include "lib/mem/virt/coco/mte.asm"

; 4. CXL Subdirectory
%include "lib/mem/virt/cxl/cxl_t1.asm"
%include "lib/mem/virt/cxl/cxl_t3.asm"
%include "lib/mem/virt/cxl/cxl_tier.asm"
%include "lib/mem/virt/cxl/cxl_pmem.asm"
%include "lib/mem/virt/cxl/cxl_fabric.asm"

; 5. Profile Subdirectory
%include "lib/mem/virt/profile/hw_perf.asm"
%include "lib/mem/virt/profile/alloc_site.asm"
%include "lib/mem/virt/profile/timeline.asm"
%include "lib/mem/virt/profile/numa_stat.asm"
%include "lib/mem/virt/profile/bw_sat.asm"
%include "lib/mem/virt/profile/inf_prof.asm"
%include "lib/mem/virt/profile/dbg_watch.asm"

; 6. Hardware Subdirectory
%include "lib/mem/virt/hardware/ept.asm"
%include "lib/mem/virt/hardware/spt.asm"
%include "lib/mem/virt/hardware/eve.asm"
%include "lib/mem/virt/hardware/vtlb.asm"
%include "lib/mem/virt/hardware/pml.asm"
%include "lib/mem/virt/hardware/nested.asm"
%include "lib/mem/virt/hardware/hmm.asm"
%include "lib/mem/virt/hardware/gpummu.asm"
%include "lib/mem/virt/hardware/p2pdma.asm"
%include "lib/mem/virt/hardware/hmm_metrics.asm"
%include "lib/mem/virt/hardware/hle.asm"
%include "lib/mem/virt/hardware/spec_walk.asm"
%include "lib/mem/virt/hardware/dmabuf.asm"
%include "lib/mem/virt/hardware/acpi_hotplug.asm"
%include "lib/mem/virt/hardware/kernel_relocator.asm"
%include "lib/mem/virt/hardware/zone_transition.asm"
%include "lib/mem/virt/hardware/locality_scorer.asm"

; 7. RT Safe Subdirectory
%include "lib/mem/virt/rt_safe/mlock.asm"
%include "lib/mem/virt/rt_safe/prefault.asm"
%include "lib/mem/virt/rt_safe/rt_reserve.asm"
%include "lib/mem/virt/rt_safe/rt_det_alloc.asm"
%include "lib/mem/virt/rt_safe/rt_isr_alloc.asm"
%include "lib/mem/virt/rt_safe/ipc.asm"
%include "lib/mem/virt/rt_safe/stack.asm"
%include "lib/mem/virt/rt_safe/temporal.asm"
%include "lib/mem/virt/rt_safe/uaf.asm"
%include "lib/mem/virt/rt_safe/sched_affinity.asm"

; 8. RAS Subdirectory
%include "lib/mem/virt/ras/ras_ecc.asm"
%include "lib/mem/virt/ras/ras_mce.asm"
%include "lib/mem/virt/ras/ras_poison.asm"
%include "lib/mem/virt/ras/ras_dimm.asm"
%include "lib/mem/virt/ras/ras_scrub.asm"

; 9. Accounting Subdirectory
%include "lib/mem/virt/accounting/percpu_stat.asm"
%include "lib/mem/virt/accounting/meminfo.asm"
%include "lib/mem/virt/accounting/proc_memstat.asm"
%include "lib/mem/virt/accounting/mbm.asm"

; 10. AI Subdirectory
%include "lib/mem/virt/ai/tensor_pool.asm"
%include "lib/mem/virt/ai/weight_cache.asm"
%include "lib/mem/virt/ai/kv_cache.asm"
%include "lib/mem/virt/ai/activation_recycler.asm"
%include "lib/mem/virt/ai/prefetch_alloc.asm"
%include "lib/mem/virt/ai/quant_layout.asm"

; Storage mmap-related files
%include "storage/ummapf/mmap.asm"
%include "storage/ummapf/dax.asm"
%include "storage/ummapf/pmem.asm"
%include "storage/ummapf/window.asm"
%include "storage/ummapf/bypass.asm"
%include "storage/ummapf/barrier.asm"

; 11. Test Suite File
%include "lib/mem/tests/mem_tests.asm"

%endif ; LIB_MEM_MEM_ASM
