; =============================================================================
; Tattva OS -- lib/mem/tests/mem_tests.asm
; =============================================================================
; Dedicated memory verification test suite extracted from main.asm.
; =============================================================================

%ifndef LIB_MEM_TESTS_MEM_TESTS_ASM
%define LIB_MEM_TESTS_MEM_TESTS_ASM

[BITS 64]


%ifndef PAGE_XO
PAGE_XO         equ (1 << 9)
%endif
%ifndef PAGE_KEY_1
PAGE_KEY_1      equ (1 << 59)
%endif

; SMC RMM simulation constants
%ifndef SMC_RMI_VERSION
SMC_RMI_VERSION             equ 0xC4000150
%endif
%ifndef SMC_RMI_RTT_MAP_UNPROTECTED
SMC_RMI_RTT_MAP_UNPROTECTED equ 0xC400015F
%endif

section .text

%if 0
; External VMM functions
extern vma_create
extern uart_print_str
extern uart_print_hex64
extern phys_alloc_page
extern virt_map
extern virt_translate
extern memcpy
extern zero_page_addr
extern vma_destroy
extern page_list_get_active_count
extern page_list_get_inactive_count
extern page_list_move_to_inactive
extern page_list_move_to_active
extern virt_unmap
extern phys_free_page
extern page_replace_clock_evict
extern phys_state
extern overcommit_mode
extern overcommit_ratio
extern virt_reserved_pages
extern swap_register_device
extern ata_swap_dev
extern nvme_swap_dev
extern kswapd_low_watermark
extern kswapd_high_watermark
extern kswapd_check_and_reclaim
extern zswap_compressed_pages
extern zram_compressed_pages
extern zram_swap_dev
extern zram_init
extern zpool_balance
extern zswap_max_slots
extern zram_max_slots
extern zswap_compress_and_store
extern zswap_in_use
extern zswap_compact
extern zram_compact
extern zswap_writeback
extern zram_writeback
extern zpool_batch_decompress_submit
extern dbg_dirty_trace_init
extern dbg_dirty_trace_register
extern dbg_dirty_trace_is_dirty
extern dbg_dirty_trace_get_rip
extern dbg_dirty_trace_clear_dirty
extern dbg_dirty_trace_deregister
extern dbg_watchpoint_init
extern dbg_watchpoint_register
extern dbg_watchpoint_is_hit
extern dbg_watchpoint_get_last_rip
extern dbg_watchpoint_get_last_type
extern dbg_watchpoint_rearm
extern dbg_watchpoint_deregister
extern dbg_ift_init
extern dbg_ift_register
extern dbg_ift_is_hit
extern dbg_ift_get_last_rip
extern dbg_ift_rearm
extern dbg_ift_deregister
extern dbg_hist_init
extern dbg_hist_register
extern dbg_hist_get_read_count
extern dbg_hist_get_write_count
extern dbg_hist_get_total_count
extern dbg_hist_rearm
extern dbg_hist_deregister
extern dbg_phys_wp_init
extern dbg_phys_wp_register
extern dbg_phys_wp_get_hit_count
extern dbg_phys_wp_get_last_rip
extern dbg_phys_wp_get_last_vaddr
extern dbg_phys_wp_get_last_type
extern dbg_phys_wp_rearm
extern dbg_phys_wp_deregister
extern thread_table
extern thread_count
extern sched_register_thread
extern virt_oom_calculate_score
extern virt_oom_select_victim
extern virt_oom_kill_process
extern virt_oom_register_notifier
extern virt_memcg_create
extern virt_memcg_destroy
extern virt_memcg_attach
extern virt_oom_select_victim_in_cgroup
extern virt_alloc_retry_mock
extern virt_psi_update_thread_state
extern virt_psi_get_sys_metrics
extern virt_psi_get_cgroup_metrics
extern sys_psi_active_count
extern numa_set_watermarks
extern sys_proactive_reclaim_headroom
extern virt_proactive_reclaim
extern virt_proactive_reclaim_node
extern numa_set_proactive_headroom
extern sys_balloon_target_pages
extern sys_balloon_current_pages
extern virt_balloon_set_target
extern virt_memcg_set_high_limit
extern sched_get_current_thread
extern virt_page_cache_init
extern virt_file_read
extern virt_file_write
extern sys_page_cache_hits
extern sys_page_cache_misses
extern sys_readahead_window_size
extern sys_readahead_prefetched_pages
extern sys_writeback_throttle_delay
extern sys_writeback_dirty_limit
extern sys_writeback_throttled_pages
extern sys_o_direct
extern sys_folio_size
extern sys_mglru_enabled
extern sys_mglru_head
extern sys_mglru_count
extern sys_mglru_promotions
extern sys_mglru_reclaims
extern virt_mglru_init
extern virt_mglru_age
extern sys_kmem_cgroup_charge
extern sys_kmem_cgroup_uncharge
extern kswapd_check_and_reclaim_node
extern page_replace_clock_evict_node
extern kswapd_min_watermark
extern numa_ranges


extern numa_range_count
extern numa_node_count
extern numa_get_node_by_phys
extern numa_detect_init
extern numa_get_distance
extern uart_print_dec
extern numa_local_bitmaps_active
extern numa_nodes
extern phys_alloc_page_node
extern phys_alloc_pages_node

extern mtrr_supported
extern mtrr_get_vcnt
extern mtrr_set_variable
extern mtrr_get_variable
extern mtrr_disable_variable
extern fb_init
extern fb_benchmark
extern heap_active_allocator
extern heap_register_relocatable
extern heap_unregister_relocatable
extern heap_compact
extern kmem_cache_file
extern kmem_cache_task
extern kmem_cache_vma
extern kmem_slab_grow
extern kmem_slab_link
extern kmem_slab_unlink
extern kmem_cache_create
extern kmem_cache_free
extern kmem_cache_reap
extern buddy_init
extern buddy_alloc
extern buddy_free
extern buddy_free_heads
extern buddy_start_addr
extern buddy_end_addr
extern buddy_metadata
extern arena_create
extern arena_alloc
extern arena_reset
extern arena_destroy
extern arena_checkpoint_save
extern arena_checkpoint_restore
extern arena_init_local
extern arena_alloc_local
extern arena_reset_local
extern arena_destroy_local
extern pool_create
extern pool_alloc
extern pool_free
extern pool_grow
extern pool_destroy
extern mock_file_create
extern mock_file_destroy
extern vma_map_file
extern vma_map_dax
extern virt_handle_dax_map
extern vma_map_pmem
extern virt_handle_pmem_map
extern nvdimm_dev
extern vma_map_pmem_window
extern virt_handle_pmem_window_map
extern pmem_window_init
extern pmem_window_select_block
extern pmem_memcpy_nt
extern pmem_flush_range
extern mmap_msync
extern mmap_munmap
extern virt_create_user_pml4
extern ipc_share_frame
extern ipc_create_ring_buffer
extern ipc_destroy_ring_buffer
extern virt_share_page_directories
extern virt_shared_page_release
extern shared_dir_table

shared_dir_desc_t.phys_addr equ 0
shared_dir_desc_t.ref_count equ 8
shared_dir_desc_t.lock     equ 16
shared_dir_desc_t_size     equ 24
extern leak_tracker_init
extern heap_leak_report
extern leak_table
extern uaf_init
extern current_thread_idx
extern tsx_begin
extern tsx_end
extern tsx_log_init
extern tsx_log_address
extern tsx_spec_walk_engine
extern trans_cache_lookup
extern trans_cache_invalidate
extern trans_cache_flush
extern pgtable_locks
extern pgtable_lock_acquire
extern pgtable_lock_release
extern hle_protect_range
extern hle_is_cache_aligned
extern pgtable_lock_abort_counts
extern virt_map_decoy
extern decoy_page_phys
extern virt_logical_to_physical_vaddr
extern pml4_shuffle_map
extern virt_temporal_obfuscation_init
extern virt_temporal_obfuscation_tick
extern temporal_code_vaddr
extern percpu_stat_init
extern percpu_stat_inc
extern percpu_stat_dec
extern percpu_event_inc
extern percpu_sync
extern percpu_stat_read
extern percpu_event_read
extern percpu_stat_delta_read
extern percpu_event_delta_read
extern sys_percpu_sync_count
extern meminfo_snapshot
extern meminfo_get_field
extern meminfo_get_snapshot_ptr
extern sys_meminfo_snap_count
extern sys_mapped_pages
extern sys_buf_pages
extern sys_shmem_pages
extern proc_memstat_compute
extern proc_memstat_get_vsz
extern proc_memstat_get_rss
extern proc_memstat_get_pss
extern proc_memstat_get_uss
extern mbm_detect
extern mbm_init
extern mbm_assign_rmid
extern mbm_set_sim_counter
extern mbm_read_bw
extern mbm_read_total_bw
extern mbm_read_local_bw
extern mbm_poll_all
extern mbm_is_saturated
extern sys_mbm_supported
extern sys_mbm_scale
extern sys_mbm_active_rmids
extern mbm_bw_snapshot
extern sev_detect
extern sev_is_active
extern sev_init
extern sev_encrypt_gpa
extern sev_decrypt_gpa
extern sev_is_encrypted
extern sev_vmgexit
extern sev_validate_page
extern sys_sev_supported
extern sys_sev_active
extern sys_sev_cbit
extern sys_sev_encrypted_pages
extern sys_sev_init_count
extern sev_enc_bitmap
extern tdx_detect
extern tdx_is_active
extern tdx_init
extern tdx_share_gpa
extern tdx_private_gpa
extern tdx_is_shared
extern tdx_accept_page
extern tdx_vmcall
extern tdx_report
extern sys_tdx_supported
extern sys_tdx_active
extern sys_tdx_shared_pages
extern sys_tdx_init_count
extern tdx_shared_bitmap

; ARM CCA (Subfeature 35.3)
extern cca_detect
extern cca_init
extern cca_realm_create
extern cca_realm_destroy
extern cca_map_gpa
extern cca_unmap_gpa
extern cca_is_realm_page
extern cca_smc_call
extern sys_cca_supported
extern sys_cca_realm_count
extern sys_cca_mapped_pages
extern sys_cca_init_count

; Encrypted Memory Swapping (Subfeature 35.4)
extern enc_swap_init
extern enc_swap_encrypt_page
extern enc_swap_decrypt_page
extern sys_enc_swap_enabled
extern sys_enc_swap_key
extern sys_enc_swap_pages_encrypted
extern sys_enc_swap_pages_decrypted

; Memory Tagging Extension (Subfeature 35.5)
extern mte_detect
extern mte_init
extern mte_set_granule_tag
extern mte_get_granule_tag
extern mte_validate_ptr
extern mte_tag_page
extern mte_tag_free_page
extern sys_mte_supported
extern sys_mte_active
extern sys_mte_tagged_pages
extern sys_mte_tag_faults

; Tensor Memory Pool (Subfeature 36.1)
extern tensor_pool_init
extern tensor_pool_alloc
extern tensor_pool_free
extern sys_tensor_pool_allocated_blocks
extern sys_tensor_pool_total_blocks

; Weight Cache Manager (Subfeature 36.2)
extern weight_cache_init
extern weight_cache_pin
extern weight_cache_unpin
extern weight_cache_evict_lru
extern weight_cache_access
extern sys_weight_cache_max_bytes
extern sys_weight_cache_total_bytes
extern sys_weight_cache_pinned_bytes
extern sys_weight_cache_resident_models

; KV Cache Physical Allocator (Subfeature 36.3)
extern kv_cache_init
extern kv_cache_alloc_block
extern kv_cache_free_block
extern kv_cache_pack_turboquant
extern kv_cache_unpack_turboquant
extern sys_kv_cache_allocated_blocks
extern sys_kv_cache_contiguous_pages

; Activation Memory Recycler (Subfeature 36.4)
extern activation_recycler_init
extern activation_recycler_register
extern activation_recycler_map
extern activation_recycler_unmap
extern sys_activation_page_count
extern sys_activation_mapped_buffers

; Prefetch-Aware Allocator (Subfeature 36.5)
extern prefetch_alloc_aligned
extern prefetch_alloc_hint
extern sys_prefetch_aligned_allocations

; Quantized Memory Layout Manager (Subfeature 36.6)
extern quant_layout_pack_int4
extern quant_layout_unpack_int4
extern sys_quant_packed_weights
extern sys_quant_avx2_alignments

; Real-Time Memory Locking (Subfeature 37.1)
extern rt_mlockall
extern rt_munlockall
extern rt_is_locked
extern sys_rt_mlockall_active
extern sys_rt_mlockall_flags
extern sys_rt_locked_pages

; Real-Time Memory Pre-faulting (Subfeature 37.2)
extern rt_prefault_range
extern rt_prefault_vma
extern sys_rt_prefaulted_pages

; Deterministic Allocator (Subfeature 37.3)
extern rt_det_alloc_init
extern rt_det_alloc
extern rt_det_free
extern sys_rt_det_allocated_bytes
extern sys_rt_det_free_blocks

; Interrupt-Safe Allocator (Subfeature 37.4)
extern rt_isr_alloc_init
extern rt_isr_alloc
extern rt_isr_free
extern sys_rt_isr_head
extern sys_rt_isr_tail
extern sys_rt_isr_allocations
extern sys_rt_isr_freed

; Memory Reservation (Subfeature 37.5)
extern rt_reserve_boot_memory
extern rt_reserve_alloc
extern rt_reserve_free
extern rt_reserve_backup
extern sys_rt_reserved_total_bytes
extern sys_rt_reserved_used_bytes

; ECC Memory Error Detection (Subfeature 38.1)
extern ras_ecc_init
extern ras_ecc_report
extern sys_ras_ecc_single_bit_errors
extern sys_ras_ecc_double_bit_errors

; MCE Handler (Subfeature 38.2)
extern ras_mce_init
extern ras_mce_handler
extern sys_ras_mce_occurred
extern sys_ras_mce_recovered

; Poison Page Handling (Subfeature 38.3)
extern ras_poison_page
extern ras_is_poisoned
extern sys_ras_poisoned_pages

; DIMM Failure Prediction (Subfeature 38.4)
extern ras_dimm_log_error
extern ras_dimm_predict_failure
extern sys_ras_dimm_errors_dimm0
extern sys_ras_dimm_errors_dimm1
extern sys_ras_dimm_migrated_pages

; Memory Scrubbing (Subfeature 38.5)
extern ras_scrub_init
extern ras_scrub_tick
extern sys_ras_scrubbed_pages
extern sys_ras_scrub_errors_detected

; CXL Type 1 Device Support (Subfeature 39.1)
extern cxl_t1_init
extern cxl_t1_get_bandwidth
extern sys_cxl_t1_active_devices
extern sys_cxl_t1_bandwidth_mbps

; CXL Type 3 Memory Expansion (Subfeature 39.2)
extern cxl_t3_init
extern cxl_t3_hotplug
extern sys_cxl_t3_device_count
extern sys_cxl_t3_total_capacity_gb

; CXL Memory Tiering (Subfeature 39.3)
extern cxl_tier_init
extern cxl_tier_demote
extern cxl_tier_promote
extern sys_cxl_promoted_pages
extern sys_cxl_demoted_pages

; CXL Persistent Memory (Subfeature 39.4)
extern cxl_pmem_init
extern cxl_pmem_flush
extern sys_cxl_pmem_active_regions
extern sys_cxl_pmem_flushed_bytes

; CXL Fabric Manager Integration (Subfeature 39.5)
extern cxl_fabric_init
extern cxl_fabric_allocate
extern cxl_fabric_release
extern sys_cxl_fabric_slices_allocated
extern sys_cxl_fabric_allocated_gb

; Hardware Performance Counters for Memory (Subfeature 40.1)
extern hw_perf_init
extern hw_perf_sample
extern sys_hw_perf_llc_miss_rate
extern sys_hw_perf_dram_bw_mbps
extern sys_hw_perf_latency_ns

; Allocation Site Tracking (Subfeature 40.2)
extern alloc_site_init
extern alloc_site_record
extern sys_alloc_site_count
extern sys_alloc_site_total_bytes

; Memory Timeline Recorder (Subfeature 40.3)
extern timeline_init
extern timeline_log
extern sys_timeline_event_count

; NUMA Hit/Miss Counters (Subfeature 40.4)
extern numa_stat_init
extern numa_stat_record
extern sys_numa_local_hits
extern sys_numa_remote_misses

; Memory Bandwidth Saturation Detector (Subfeature 40.5)
extern bw_sat_init
extern bw_sat_check
extern sys_bw_sat_alerts

; Inference Memory Profiler (Subfeature 40.6)
extern inf_prof_init
extern inf_prof_record_layer
extern sys_inf_prof_peak_activation_bytes
extern sys_inf_prof_weight_bytes
extern sys_inf_prof_kv_cache_bytes




%endif

global run_all_memory_tests

run_all_memory_tests:
.share_test_start:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_share_test_start
    call uart_print_str

    ; Save original CR3 to r15
    mov r15, cr3

    ; 1. Create source PML4
    xor rdi, rdi
    call virt_create_user_pml4
    test rax, rax
    jz .share_fail_alloc_src_pml4
    mov r12, rax                    ; R12 = physical base of source PML4

    ; 2. Create destination PML4
    xor rdi, rdi
    call virt_create_user_pml4
    test rax, rax
    jz .share_fail_alloc_dest_pml4
    mov r13, rax                    ; R13 = physical base of dest PML4

    ; 3. Switch CR3 to source PML4 to map pages in it
    mov cr3, r12

    ; Allocate physical page 1
    call phys_alloc_page
    test rax, rax
    jz .share_fail_alloc_page1
    mov r14, rax                    ; R14 = physical page 1

    ; Map physical page 1 to 0x80000000
    mov rdi, 0x80000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .share_fail_map1

    ; Write test signature to page 1
    mov rdi, 0x80000000
    mov qword [rdi], 0x5348415245445F31 ; "SHARED_1"

    ; Allocate physical page 2
    call phys_alloc_page
    test rax, rax
    jz .share_fail_alloc_page2
    mov rbp, rax                    ; RBP = physical page 2

    ; Map physical page 2 to 0x80001000
    mov rdi, 0x80001000
    mov rsi, rbp
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .share_fail_map2

    ; Write test signature to page 2
    mov rdi, 0x80001000
    mov qword [rdi], 0x5348415245445F32 ; "SHARED_2"

    ; Restore original CR3
    mov cr3, r15

    ; 4. Call virt_share_page_directories to share directory from source to dest
    mov rdi, r13                    ; destination PML4
    mov rsi, r12                    ; source PML4
    mov rdx, 0x80000000             ; start_vaddr (2MB aligned)
    mov rcx, 0x200000               ; size (2MB)
    call virt_share_page_directories
    test rax, rax
    jz .share_fail_call

    ; 5. Switch to destination PML4 to verify sharing
    mov cr3, r13

    ; Verify signature 1 at 0x80000000
    mov rdi, 0x80000000
    mov rax, [rdi]
    cmp rax, 0x5348415245445F31     ; "SHARED_1"
    jne .share_fail_verify_val1

    ; Verify signature 2 at 0x80001000
    mov rdi, 0x80001000
    mov rax, [rdi]
    cmp rax, 0x5348415245445F32     ; "SHARED_2"
    jne .share_fail_verify_val2

    ; Restore original CR3
    mov cr3, r15

    ; Verify read-only enforcement in destination PML4
    ; PML4 logical index for 0x80000000
    mov rax, 0x80000000
    shr rax, 39
    and rax, 0x1FF
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]
    mov rbx, [r13 + rax * 8]
    test rbx, 0x01
    jz .share_fail_ro_check
    and rbx, 0xFFFFFFFFFFFFF000     ; PDPT physical address

    ; PDPT index for 0x80000000
    mov rax, 0x80000000
    shr rax, 30
    and rax, 0x1FF
    mov rdx, [rbx + rax * 8]
    test rdx, 0x01
    jz .share_fail_ro_check
    and rdx, 0xFFFFFFFFFFFFF000     ; PD physical address

    ; PD index for 0x80000000
    mov rax, 0x80000000
    shr rax, 21
    and rax, 0x1FF
    mov rsi, [rdx + rax * 8]        ; rsi = PD entry (pointing to PT)
    test rsi, 0x01
    jz .share_fail_ro_check
    test rsi, 0x02                  ; Check Writable (bit 1)
    jnz .share_fail_ro_check        ; Should NOT be writable!

    ; 6. Verify shared descriptor in shared_dir_table
    lea rbx, [shared_dir_table]
    xor rcx, rcx
.find_desc_loop:
    cmp rcx, 128
    jge .share_fail_desc_not_found
    imul rdx, rcx, shared_dir_desc_t_size
    add rdx, rbx
    cmp qword [rdx + shared_dir_desc_t.phys_addr], 0
    jne .found_desc
    inc rcx
    jmp .find_desc_loop

.found_desc:
    ; Verify reference count is 2
    mov rax, [rdx + shared_dir_desc_t.ref_count]
    cmp rax, 2
    jne .share_fail_refcount
    
    ; Save the physical address of the shared PT page to rsi
    mov rsi, [rdx + shared_dir_desc_t.phys_addr]

    ; 7. Test virt_shared_page_release
    ; First release (decrements from 2 to 1) -> returns 1 (still shared)
    push rdx                        ; save descriptor pointer
    push rsi                        ; save PT page physical address
    mov rdi, rsi
    call virt_shared_page_release
    pop rsi
    pop rdx
    cmp rax, 1
    jne .share_fail_release_1

    ; Verify reference count is now 1
    mov rax, [rdx + shared_dir_desc_t.ref_count]
    cmp rax, 1
    jne .share_fail_refcount_1

    ; Second release (decrements from 1 to 0) -> returns 0 (safe to free)
    push rdx
    push rsi
    mov rdi, rsi
    call virt_shared_page_release
    pop rsi
    pop rdx
    test rax, rax
    jnz .share_fail_release_2

    ; Verify descriptor has been cleared (phys_addr = 0)
    cmp qword [rdx + shared_dir_desc_t.phys_addr], 0
    jne .share_fail_desc_not_cleared

    ; 8. Clean up allocated PML4s & physical pages
    ; Clean up mappings in source PML4
    mov cr3, r12
    mov rdi, 0x80000000
    call virt_unmap
    mov rdi, 0x80001000
    call virt_unmap

    ; Switch to dest PML4 and clean up its PDPT/PD directories manually
    mov cr3, r13
    
    ; PML4 logical index for 0x80000000
    mov rax, 0x80000000
    shr rax, 39
    and rax, 0x1FF
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]
    mov rbx, [r13 + rax * 8]
    and rbx, 0xFFFFFFFFFFFFF000     ; PDPT physical address

    ; PDPT index for 0x80000000
    mov rax, 0x80000000
    shr rax, 30
    and rax, 0x1FF
    mov rdx, [rbx + rax * 8]
    and rdx, 0xFFFFFFFFFFFFF000     ; PD physical address

    ; Switch to original CR3
    mov cr3, r15

    ; Free the dest PML4's PDPT and PD pages
    mov rdi, rbx
    call phys_free_page
    mov rdi, rdx
    call phys_free_page

    ; Free the allocated physical pages
    ; Physical page 1
    mov rdi, r14
    call phys_free_page
    ; Physical page 2
    mov rdi, rbp
    call phys_free_page

    ; Free PML4 pages
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call phys_free_page

    ; Test PASSED!
    mov rsi, msg_share_test_passed
    call uart_print_str

    ; =========================================================================
    ; 1.2 Page Table Reaping Test
    ; =========================================================================
    mov rsi, msg_reap_test_start
    call uart_print_str

    ; Create dummy PML4
    xor rdi, rdi
    call virt_create_user_pml4
    test rax, rax
    jz .reap_fail_pml4
    mov r12, rax                    ; R12 = dummy PML4

    ; Switch CR3 to dummy PML4
    mov cr3, r12

    ; Allocate physical page 1
    call phys_alloc_page
    test rax, rax
    jz .reap_fail_alloc1
    mov r13, rax                    ; R13 = physical page 1

    ; Map physical page 1 to 0x40000000 (allocates PDPT, PD, and PT)
    mov rdi, 0x40000000
    mov rsi, r13
    mov rdx, 0x07                   ; Present | Writable | User
    call virt_map
    test rax, rax
    jz .reap_fail_map1

    ; Switch to original CR3 to perform reaping check
    mov cr3, r15

    ; Call virt_reap_empty_page_tables. Since PT contains mapped page, reap count must be 0!
    mov rdi, r12
    call virt_reap_empty_page_tables
    test rax, rax
    jnz .reap_fail_count1

    ; Switch to dummy PML4 to clear PTE manually
    mov cr3, r12

    ; Walk page table to find PTE for 0x40000000
    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE physical/virtual pointer
    test rax, rax
    jz .reap_fail_walk
    mov qword [rax], 0              ; Clear PTE manually to simulate page unmap without directory free

    ; Switch to original CR3
    mov cr3, r15

    ; Call virt_reap_empty_page_tables. PT is now empty, must reap it (count = 1)
    mov rdi, r12
    call virt_reap_empty_page_tables
    cmp rax, 1
    jne .reap_fail_count2

    ; Verify that PMD entry in dummy PML4 is indeed cleared (0)
    ; PML4 logical index for 0x40000000
    mov rax, 0x40000000
    shr rax, 39
    and rax, 0x1FF
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]
    mov rbx, [r12 + rax * 8]
    and rbx, 0xFFFFFFFFFFFFF000     ; RBP = PDPT physical address
    mov rbp, rbx

    ; PDPT index for 0x40000000
    mov rax, 0x40000000
    shr rax, 30
    and rax, 0x1FF
    mov rdx, [rbp + rax * 8]
    and rdx, 0xFFFFFFFFFFFFF000     ; RBP = PD physical address
    mov rbp, rdx

    ; PD index for 0x40000000
    mov rax, 0x40000000
    shr rax, 21
    and rax, 0x1FF
    mov rsi, [rbp + rax * 8]        ; RSI = PMD entry
    test rsi, rsi                   ; Must be 0 (reaped)!
    jnz .reap_fail_pmd_not_cleared

    ; Free allocated physical page 1
    mov rdi, r13
    call phys_free_page

    ; Free remaining tables (PDPT, PD) of dummy PML4 manually
    mov rax, 0x40000000
    shr rax, 39
    and rax, 0x1FF
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]
    mov rbx, [r12 + rax * 8]
    and rbx, 0xFFFFFFFFFFFFF000     ; rbx = PDPT physical address

    mov rax, 0x40000000
    shr rax, 30
    and rax, 0x1FF
    mov rdx, [rbx + rax * 8]
    and rdx, 0xFFFFFFFFFFFFF000     ; rdx = PD physical address

    ; Free PD and PDPT
    mov rdi, rdx
    call phys_free_page
    mov rdi, rbx
    call phys_free_page

    ; Free dummy PML4
    mov rdi, r12
    call phys_free_page

    ; Reap Test PASSED!
    mov rsi, msg_reap_test_passed
    call uart_print_str


    ; =========================================================================
    ; 1.3 Cooperative Lockless Allocator Test
    ; =========================================================================
    mov rsi, msg_coop_test_start
    call uart_print_str

    ; Allocate memory for coop queue (4120 bytes)
    mov rdi, 4120
    call heap_alloc
    test rax, rax
    jz .coop_fail_queue_alloc
    mov r12, rax                    ; R12 = coop_queue_t virtual pointer

    ; Initialize coop queue
    mov qword [r12 + coop_queue_t.head], 0
    mov qword [r12 + coop_queue_t.tail], 0
    mov qword [r12 + coop_queue_t.capacity], 512

    ; Enable coop test mode (bypass spinning)
    extern coop_test_mode
    mov qword [coop_test_mode], 1

    ; Request 4 pages (order 2) via coop_alloc_pages
    mov rdi, r12
    mov rsi, 4                      ; 4 pages
    call coop_alloc_pages           ; RAX = slot index (0)
    cmp rax, 0
    jne .coop_fail_slot             ; should return slot 0

    ; Verify request is written in the slot
    mov rax, [r12 + coop_queue_t.ring + 0 * 8]
    cmp rax, 4
    jne .coop_fail_request_val

    ; Run kernel processing routine
    mov rdi, r12
    call coop_process_requests

    ; Disable test mode
    mov qword [coop_test_mode], 0

    ; Verify that head and tail are both 1
    mov rax, [r12 + coop_queue_t.head]
    cmp rax, 1
    jne .coop_fail_head
    mov rax, [r12 + coop_queue_t.tail]
    cmp rax, 1
    jne .coop_fail_tail

    ; Read the allocated physical address from slot 0
    mov r13, [r12 + coop_queue_t.ring + 0 * 8]
    test r13, r13
    jz .coop_fail_phys_val

    ; Free allocated pages back (order 2 block)
    extern buddy_free
    mov rdi, r13
    mov rsi, 2                      ; order 2
    call buddy_free

    ; Free the queue memory
    mov rdi, r12
    call heap_free

    ; Coop Test PASSED!
    mov rsi, msg_coop_test_passed
    call uart_print_str


    ; =========================================================================
    ; 1.4 Memory Compact Hot-Plug Zones Test (ZONE_MOVABLE)
    ; =========================================================================
    mov rsi, msg_zone_test_start
    call uart_print_str

    ; Mark range [100, 200) as movable
    mov rdi, 100
    mov rsi, 200
    call zone_mark_movable

    ; Verify pages_array is initialized
    extern pages_array
    mov r12, [pages_array]
    test r12, r12
    jz .zone_fail_init

    ; Verify PFN 150 flags has PAGE_MOVABLE set (bit 12)
    imul rax, 150, 16               ; PFN 150 descriptor offset
    mov rdx, [r12 + rax]            ; RDX = page_t.flags
    test rdx, (1 << 12)
    jz .zone_fail_flag

    ; Verify Buddy Allocator bypass logic:
    ; Enable buddy_alloc_mask (avoid ZONE_MOVABLE)
    extern buddy_alloc_mask
    mov qword [buddy_alloc_mask], 1

    ; Request order 0 allocation
    mov rdi, 0
    call buddy_alloc                ; RAX = physical address
    mov qword [buddy_alloc_mask], 0 ; restore mask

    test rax, rax
    jz .zone_fail_alloc

    ; Assert that allocated frame does NOT fall inside movable PFN zone [100, 200)
    ; Movable zone address boundary: [buddy_start_addr + 100 * 4096, buddy_start_addr + 200 * 4096)
    mov rcx, [buddy_start_addr]
    lea rdx, [rcx + 100 * 4096]
    cmp rax, rdx
    jb .zone_alloc_ok
    lea rdx, [rcx + 200 * 4096]
    cmp rax, rdx
    jb .zone_fail_movable_alloc     ; allocated page is inside the movable zone!

.zone_alloc_ok:
    ; Free allocated page
    mov rdi, rax
    mov rsi, 0                      ; order 0
    call buddy_free

    ; Zone Test PASSED!
    mov rsi, msg_zone_test_passed
    call uart_print_str


    ; =========================================================================
    ; 1.5 Live Kernel ASLR Re-Shuffling Test
    ; =========================================================================
    mov rsi, msg_aslr_test_start
    call uart_print_str

    ; Allocate physical page 1 (old)
    call phys_alloc_page
    test rax, rax
    jz .aslr_fail_alloc1
    mov r12, rax                    ; R12 = old physical frame address

    ; Allocate physical page 2 (new)
    call phys_alloc_page
    test rax, rax
    jz .aslr_fail_alloc2
    mov r13, rax                    ; R13 = new physical frame address

    ; Write signature to old page using identity mapping
    mov rdi, r12
    mov qword [rdi], 0x41534C525F4F4B3F ; "ASLR_OK?"

    ; Map old page to virtual address 0x30000000 in current address space (CR3)
    mov rdi, 0x30000000
    mov rsi, r12
    mov rdx, 0x07                   ; Present | Writable | User
    call virt_map
    test rax, rax
    jz .aslr_fail_map1

    ; Verify virtual address reads correctly
    mov rax, [0x30000000]
    cmp rax, 0x41534C525F4F4B3F
    jne .aslr_fail_sig1

    ; Trigger Live ASLR Migration
    mov rdi, r12                    ; target_old_paddr
    mov rsi, r13                    ; target_new_paddr
    mov rdx, 4096                   ; size
    call kernel_live_aslr_migrate

    ; Verify that 0x30000000 now translates to new physical address r13
    mov rdi, 0x30000000
    call virt_translate
    cmp rax, r13
    jne .aslr_fail_translate

    ; Verify that virtual address still reads correct data (copied successfully)
    mov rax, [0x30000000]
    cmp rax, 0x41534C525F4F4B3F
    jne .aslr_fail_sig2

    ; Unmap virtual address 0x30000000
    mov rdi, 0x30000000
    call virt_unmap

    ; Free physical page frames
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call phys_free_page

    ; ASLR Test PASSED!
    mov rsi, msg_aslr_test_passed
    call uart_print_str


    ; =========================================================================
    ; 1.6 PASID Table Binding Test
    ; =========================================================================
    mov rsi, msg_pasid_test_start
    call uart_print_str

    ; Allocate memory for mock PASID table (512 entries * 64 bytes = 32,768 bytes)
    mov rdi, 32768
    call heap_alloc
    test rax, rax
    jz .pasid_fail_alloc
    mov r12, rax                    ; R12 = PASID table pointer

    extern pasid_table_base
    mov [pasid_table_base], r12     ; Register base

    ; Zero out table
    mov rdi, r12
    mov rsi, 32768
    call memzero

    ; Bind PASID entry 123 to dummy physical PML4 0x900000
    mov rdi, 123                    ; PASID index
    mov rsi, 0x900000               ; PML4 physical base
    call iommu_bind_pasid_table

    ; Verify entry at offset 123 * 64 bytes
    mov rax, [r12 + 123 * 64]
    cmp rax, 0x900003               ; Address + Present (1) + PRI (2)
    jne .pasid_fail_entry

    ; Unbind and free table
    mov qword [pasid_table_base], 0
    mov rdi, r12
    call heap_free

    ; PASID Test PASSED!
    mov rsi, msg_pasid_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ; 2. Run VMM Page Fault On-Demand Paging Test
    mov rsi, msg_test_start
    call uart_print_str

    ; Create a VMA: start=0x70000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x70000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .test_fail_vma

    mov rsi, msg_vma_ok
    call uart_print_str

    ; Access address to trigger page fault (read/write check)
    mov rdi, 0x70000000
    mov byte [rdi], 0x42            ; should trigger #PF and resume!

    ; Verification 1: Check if the written byte is present and correct
    mov al, [rdi]
    cmp al, 0x42
    jne .test_fail_val

    ; Verification 2: Print the mock loaded page content
    mov rsi, rdi
    call uart_print_str             ; should print "TATTVA_OS_ONDEMAND_PAGE_LOADED"
    mov rsi, msg_crlf
    call uart_print_str

    ; Verification 3: Check unique address written at offset 32
    mov rax, [rdi + 32]
    cmp rax, 0x70000000
    jne .test_fail_addr

    ; Test PASSED!
    mov rsi, msg_test_passed
    call uart_print_str

    ; 3. Run VMM Page Fault Copy-on-Write (COW) Test
    mov rsi, msg_cow_test_start
    call uart_print_str

    ; Step A: Allocate a physical page for parent content
    call phys_alloc_page
    test rax, rax
    jz .cow_fail_alloc
    mov r14, rax                    ; R14 = parent physical address

    ; Step B: Initialize the parent page content
    mov rdi, r14
    mov rsi, msg_cow_parent_data
    mov rdx, 25                     ; length of "COW_PARENT_ORIGINAL_DATA" (24 chars + null)
    call memcpy

    ; Step C: Create a VMA for the COW virtual address
    ; start=0x60000000, size=4096, flags=VMA_READ|VMA_WRITE (0x03)
    mov rdi, 0x60000000
    mov rsi, 4096
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .cow_fail_vma

    ; Step D: Map 0x60000000 to the parent physical page as read-only with PAGE_COW
    mov rdi, 0x60000000
    mov rsi, r14                    ; physical page
    mov rdx, 0x200                  ; PAGE_COW flag (1 << 9)
    call virt_map
    test rax, rax
    jz .cow_fail_map

    ; Verify initial mapping: virtual address should read the parent data
    mov rsi, msg_cow_before_write
    call uart_print_str
    mov rsi, 0x60000000
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; Step E: Write to the virtual address to trigger COW page fault
    mov rdi, 0x60000000
    ; Write "CHILD_DATA" to virtual page (triggering COW)
    mov rsi, msg_cow_child_data
    mov rdx, 11                     ; length of msg_cow_child_data (10 chars + null)
    call memcpy

    ; Step F: Verify the write succeeded on the virtual page
    mov rsi, msg_cow_after_write
    call uart_print_str
    mov rsi, 0x60000000
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; Step G: Verify page isolation (parent page must remain unmodified)
    mov rsi, msg_cow_parent_check
    call uart_print_str
    mov rsi, r14
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; Programmatic verification:
    ; 1. Check if virtual page content has modified data "CHILD_DATA"
    mov rax, [0x60000000]
    mov rbx, 0x41445F444C494843     ; 'CHILD_DA' in little-endian
    cmp rax, rbx
    jne .cow_fail_isolation

    ; 2. Check if parent page content is still "COW_PARENT_ORIGINAL_DATA"
    mov rax, [r14]
    mov rbx, 0x455241505F574F43     ; 'COW_PARE' in little-endian
    cmp rax, rbx
    jne .cow_fail_isolation

    ; 3. Verify that virtual address is now mapped to a different physical address
    mov rdi, 0x60000000
    call virt_translate
    cmp rax, r14
    je .cow_fail_same_page

    ; COW Test PASSED!
    mov rsi, msg_cow_test_passed
    call uart_print_str

    ; 4. Run VMM Page Fault Zero-Fill-on-Demand (ZFOD) Test
    mov rsi, msg_zfod_test_start
    call uart_print_str

    ; Step A: Create a VMA for the ZFOD virtual address space
    ; start=0x50000000, size=8192 (2 pages), flags=VMA_READ|VMA_WRITE|VMA_ZFOD (0x23)
    mov rdi, 0x50000000
    mov rsi, 8192
    mov rdx, 0x23                   ; VMA_READ | VMA_WRITE | VMA_ZFOD
    call vma_create
    test rax, rax
    jz .zfod_fail_vma

    ; Step B: Test the read path on page 1 (0x50000000)
    ; Reading from it should return 0 since it is mapped to the shared zero page
    mov rax, [0x50000000]
    test rax, rax
    jnz .zfod_fail_read_val

    ; Let's verify that zero_page_addr has been initialized
    mov rax, [zero_page_addr]
    test rax, rax
    jz .zfod_fail_zero_ptr

    mov rsi, msg_zfod_read_ok
    call uart_print_str

    ; Step C: Write to page 1 to trigger COW on the shared zero page
    mov rax, 0x123456789ABCDEF0
    mov [0x50000000], rax

    ; Step D: Verify the write succeeded on page 1
    mov rax, [0x50000000]
    mov rbx, 0x123456789ABCDEF0
    cmp rax, rbx
    jne .zfod_fail_write_val

    ; Step E: Verify page isolation (shared zero page must still be all zeroes)
    mov rcx, [zero_page_addr]
    mov rax, [rcx]                  ; read from physical address (identity mapped)
    test rax, rax
    jnz .zfod_fail_isolation

    ; Step F: Verify mapping isolation (0x50000000 maps to a private page, not the zero page)
    mov rdi, 0x50000000
    call virt_translate
    mov rcx, [zero_page_addr]
    cmp rax, rcx
    je .zfod_fail_same_page

    mov rsi, msg_zfod_page1_ok
    call uart_print_str

    ; Step G: Test direct write path on page 2 (0x50001000)
    ; Accessing it directly via write should allocate a private zeroed page immediately
    mov rax, 0xABCDEF0123456789
    mov [0x50001000], rax

    ; Step H: Verify the write succeeded on page 2
    mov rax, [0x50001000]
    mov rbx, 0xABCDEF0123456789
    cmp rax, rbx
    jne .zfod_fail_page2_val

    ; Step I: Verify page 2 is not mapped to the shared zero page
    mov rdi, 0x50001000
    call virt_translate
    mov rcx, [zero_page_addr]
    cmp rax, rcx
    je .zfod_fail_page2_same

    ; ZFOD Test PASSED!
    mov rsi, msg_zfod_test_passed
    call uart_print_str

    ; 5. Run VMM Page Fault Stack Auto-Grow Test
    mov rsi, msg_stack_test_start
    call uart_print_str

    ; Step A: Determine page boundary immediately below current RSP
    mov rdi, rsp
    and rdi, -4096                  ; align down to 4KB boundary
    sub rdi, 4096                   ; page address immediately below RSP
    mov r14, rdi                    ; R14 = stack grow test virtual address

    ; Step B: Create a VMA for this stack grow region
    ; start=R14, size=4096, flags=VMA_READ|VMA_WRITE|VMA_STACK (0x43)
    mov rsi, 4096
    mov rdx, 0x43                   ; VMA_READ | VMA_WRITE | VMA_STACK
    call vma_create
    test rax, rax
    jz .stack_fail_vma
    mov r13, rax                    ; R13 = VMA pointer

    ; Step C: Trigger a write to the stack page
    ; We write at R14 + 4088 (8 bytes below the top of the new page, i.e. 8 bytes below original page boundary)
    mov r15, r14
    add r15, 4088
    mov qword [r15], 0x9876543210FEDCBA

    ; Step D: Verify the write succeeded
    mov rax, [r15]
    mov rbx, 0x9876543210FEDCBA
    cmp rax, rbx
    jne .stack_fail_val

    ; Step E: Verify the page is now mapped in the page table
    mov rdi, r15
    call virt_translate
    test rax, rax
    jz .stack_fail_map

    ; Step F: Clean up the stack VMA
    mov rdi, r13
    call vma_destroy

    ; Stack Auto-Grow Test PASSED!
    mov rsi, msg_stack_test_passed
    call uart_print_str

    ; 6. Run VMM Page Replacement Active/Inactive Page Lists Test
    mov rsi, msg_rep_test_start
    call uart_print_str

    ; Step A: Verify initial active and inactive page counts are 0
    call page_list_get_active_count
    test rax, rax
    jnz .rep_fail_init_count
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_init_count

    ; Step B: Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .rep_fail_alloc
    mov r14, rax                    ; R14 = physical page address

    ; Step C: Create a VMA for the tracked virtual address space
    ; start=0x30000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER (0x0B)
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .rep_fail_vma
    mov r15, rax                    ; R15 = VMA pointer

    ; Step D: Map 0x30000000 to the physical page (triggers active list hook)
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .rep_fail_map

    ; Step E: Verify page added to Active list
    call page_list_get_active_count
    cmp rax, 1
    jne .rep_fail_active_count
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_inactive_count

    ; Step F: Move page to Inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Step G: Verify page is now in Inactive list
    call page_list_get_active_count
    test rax, rax
    jnz .rep_fail_active_count_inactive
    call page_list_get_inactive_count
    cmp rax, 1
    jne .rep_fail_inactive_count_inactive

    ; Step H: Move page back to Active list
    mov rdi, r14
    call page_list_move_to_active

    ; Step I: Verify page is back in Active list
    call page_list_get_active_count
    cmp rax, 1
    jne .rep_fail_active_count_back
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_inactive_count_back

    ; Step J: Unmap page (triggers removal hook)
    mov rdi, 0x30000000
    call virt_unmap

    ; Step K: Verify page is untracked (counts return to 0)
    call page_list_get_active_count
    test rax, rax
    jnz .rep_fail_final_count
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_final_count

    ; Step L: Clean up physical frame and VMA
    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    ; Active/Inactive Lists Test PASSED!
    mov rsi, msg_rep_test_passed
    call uart_print_str

    ; 7. Run VMM Clock/Second-Chance Eviction Test
    mov rsi, msg_clock_test_start
    call uart_print_str

    ; Step A: Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .clock_fail_alloc
    mov r14, rax                    ; R14 = physical page address

    ; Step B: Initialize page content
    mov rdi, r14
    mov rsi, msg_clock_test_data
    mov rdx, 25                     ; length of msg_clock_test_data
    call memcpy

    ; Step C: Create a VMA for the tracked virtual address space
    ; start=0x20000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER (0x0B)
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .clock_fail_vma
    mov r15, rax                    ; R15 = VMA pointer

    ; Step D: Map 0x20000000 to the physical page (triggers active list hook)
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .clock_fail_map

    ; Step E: Move page to inactive list (to make it a candidate for eviction)
    mov rdi, r14
    call page_list_move_to_inactive

    ; Verify it is in inactive list
    call page_list_get_inactive_count
    cmp rax, 1
    jne .clock_fail_inactive

    ; Step F: Clear Accessed bit in PTE to simulate no recent accesses
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .clock_fail_walk
    and qword [rax], ~0x20          ; clear PAGE_ACCESSED (bit 5)

    ; Step G: Trigger Clock Eviction!
    call page_replace_clock_evict
    test rax, rax
    jz .clock_fail_evict

    ; Step H: Verify page is evicted
    ; 1. PTE Present bit should be 0
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .clock_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present bit set?
    jnz .clock_fail_still_present

    ; 2. PTE Swapped bit should be 1
    test rcx, 0x400                 ; PAGE_SWAPPED (bit 10) set?
    jz .clock_fail_not_swapped

    ; 3. Telemetry swap_pages count should be 1
    mov rax, [phys_state + phys_state_t.swap_pages]
    cmp rax, 1
    jne .clock_fail_stats

    ; 4. Active/Inactive list counts should return to 0
    call page_list_get_active_count
    test rax, rax
    jnz .clock_fail_list_counts
    call page_list_get_inactive_count
    test rax, rax
    jnz .clock_fail_list_counts

    mov rsi, msg_clock_evicted_ok
    call uart_print_str

    ; Step I: Access the evicted page to trigger swap-in page fault!
    ; We read from 0x20000000. It should transparently swap-in the page!
    mov rax, [0x20000000]

    ; Step J: Verify data is intact
    mov rax, [0x20000000]
    mov rbx, 0x434F4D5F50415753     ; 'SWAP_MOC' in little-endian
    cmp rax, rbx
    jne .clock_fail_data_corrupt

    ; Step K: Verify page statistics and lists are restored
    ; 1. Telemetry swap_pages count should return to 0
    mov rax, [phys_state + phys_state_t.swap_pages]
    test rax, rax
    jnz .clock_fail_stats_restore

    ; 2. Page should be back in the active list (count = 1)
    call page_list_get_active_count
    cmp rax, 1
    jne .clock_fail_active_restore
    call page_list_get_inactive_count
    test rax, rax
    jnz .clock_fail_inactive_restore

    ; Step L: Clean up
    ; Get new physical page mapping
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax                    ; save new physical address for freeing

    mov rdi, 0x20000000
    call virt_unmap
    
    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    ; Clock Eviction Test PASSED!
    mov rsi, msg_clock_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; ATA Swap Device Test
    ; -------------------------------------------------------------
    mov rsi, msg_ata_test_start
    call uart_print_str

    ; Register ATA device
    lea rdi, [ata_swap_dev]
    call swap_register_device

    ; Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .ata_fail_alloc
    mov r14, rax

    ; Initialize page content
    mov rdi, r14
    mov rsi, msg_ata_test_data
    mov rdx, 25
    call memcpy

    ; Create VMA
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .ata_fail_vma
    mov r15, rax

    ; Map the page
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07                   ; PRESENT | WRITABLE | USER
    call virt_map
    test rax, rax
    jz .ata_fail_map

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Verify it is in inactive list
    call page_list_get_inactive_count
    cmp rax, 1
    jne .ata_fail_inactive

    ; Clear Accessed bit in PTE
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .ata_fail_walk
    and qword [rax], ~0x20          ; clear Accessed (bit 5)

    ; Trigger Clock Eviction (now writing to ATA)
    call page_replace_clock_evict
    test rax, rax
    jz .ata_fail_evict

    ; Verify page is evicted
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .ata_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .ata_fail_still_present
    test rcx, 0x400                 ; swapped?
    jz .ata_fail_not_swapped

    ; Access page to trigger swap-in page fault
    mov rax, [0x20000000]

    ; Verify data
    mov rax, [0x20000000]
    mov rbx, 0x4154415F4B434F4D     ; 'MOCK_ATA' in little-endian ("MOCK_ATA_SWAP_DATA")
    cmp rax, rbx
    jne .ata_fail_data_corrupt

    ; Cleanup
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax

    mov rdi, 0x20000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    mov rsi, msg_ata_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; NVMe Swap Device Test
    ; -------------------------------------------------------------
    mov rsi, msg_nvme_test_start
    call uart_print_str

    ; Register NVMe device
    lea rdi, [nvme_swap_dev]
    call swap_register_device

    ; Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .nvme_fail_alloc
    mov r14, rax

    ; Initialize page content
    mov rdi, r14
    mov rsi, msg_nvme_test_data
    mov rdx, 25
    call memcpy

    ; Create VMA
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .nvme_fail_vma
    mov r15, rax

    ; Map the page
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .nvme_fail_map

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Verify it is in inactive list
    call page_list_get_inactive_count
    cmp rax, 1
    jne .nvme_fail_inactive

    ; Clear Accessed bit
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .nvme_fail_walk
    and qword [rax], ~0x20

    ; Trigger Clock Eviction (now writing to NVMe)
    call page_replace_clock_evict
    test rax, rax
    jz .nvme_fail_evict

    ; Verify page is evicted
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .nvme_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .nvme_fail_still_present
    test rcx, 0x400                 ; swapped?
    jz .nvme_fail_not_swapped

    ; Access page to trigger swap-in page fault
    mov rax, [0x20000000]

    ; Verify data
    mov rax, [0x20000000]
    mov rbx, 0x4D564E5F4B434F4D     ; 'MOCK_NVM' in little-endian ("MOCK_NVME_SWAP_DATA")
    cmp rax, rbx
    jne .nvme_fail_data_corrupt

    ; Cleanup
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax

    mov rdi, 0x20000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    mov rsi, msg_nvme_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; 8. Run VMM Page-Out Daemon (kswapd) Watermark test
    ; -------------------------------------------------------------
    mov rsi, msg_kswapd_test_start
    call uart_print_str

    ; Step A: Register the default mock RAM swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Step B: Map user page to put it in the active list, then move to inactive
    call phys_alloc_page
    test rax, rax
    jz .kswapd_fail_alloc_setup
    mov r14, rax

    mov rdi, r14
    mov rsi, msg_kswapd_test_data
    mov rdx, 25
    call memcpy

    ; Create VMA
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .kswapd_fail_vma_setup
    mov r15, rax

    ; Map
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .kswapd_fail_map_setup

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed bit in PTE
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .kswapd_fail_walk_setup
    and qword [rax], ~0x20          ; clear Accessed

    ; Step C: Artificially set low watermark to a high value to force trigger
    mov rax, [phys_state + phys_state_t.free_pages]
    mov rbx, rax
    add rbx, 10                     ; rbx = low watermark
    mov [kswapd_low_watermark], rbx
    add rbx, 10                     ; rbx = high watermark
    mov [kswapd_high_watermark], rbx

    ; Step D: Perform a physical page allocation.
    ; This should automatically trigger kswapd_check_and_reclaim!
    call phys_alloc_page
    test rax, rax
    jz .kswapd_fail_alloc_trigger
    mov r13, rax                    ; r13 = allocated physical page address

    ; Step E: Verify kswapd successfully evicted our page!
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .kswapd_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .kswapd_fail_still_present
    test rcx, 0x400                 ; swapped?
    jz .kswapd_fail_not_swapped

    ; Step F: Verify data swap-in still works
    mov rax, [0x20000000]           ; should transparently swap-in!
    
    ; Verify data
    mov rax, [0x20000000]
    mov rbx, 0x57534B4B5F434F4D     ; 'MOCK_KSW' in little-endian ("MOCK_KSWAPD_SWAP_DATA")
    cmp rax, rbx
    jne .kswapd_fail_data_corrupt

    ; Step G: Reset watermarks back to 0 to prevent further triggers
    mov qword [kswapd_low_watermark], 0
    mov qword [kswapd_high_watermark], 0

    ; Step H: Cleanup both mapped page and the allocated page
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax                    ; get new physical frame

    mov rdi, 0x20000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    mov rdi, r13
    call phys_free_page             ; free page allocated during trigger

    ; kswapd Test PASSED!
    mov rsi, msg_kswapd_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; 9. Run VMM Zswap Compressed Cache Test
    ; -------------------------------------------------------------
    mov rsi, msg_zswap_test_start
    call uart_print_str

    ; Step A: Register the default mock RAM swap device (clean state)
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Verify that initial zswap compressed pages telemetry is 0
    mov rax, [zswap_compressed_pages]
    test rax, rax
    jnz .zswap_fail_init_telemetry

    ; --- Part 1: Compressible Page Test ---
    ; Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .zswap_fail_alloc1
    mov r14, rax                    ; R14 = physical address

    ; Initialize the page content with a highly compressible pattern (repeated 0xAA)
    mov rdi, r14
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    ; Set a recognizable signature at the start to verify data integrity later
    mov rdi, r14
    mov rsi, msg_zswap_comp_sig
    mov rdx, 17                     ; length of "COMPRESSIBLE_SIG" (16 + null)
    call memcpy

    ; Create a VMA: start=0x30000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .zswap_fail_vma1
    mov r15, rax                    ; R15 = VMA pointer

    ; Map 0x30000000 to the physical page
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .zswap_fail_map1

    ; Move page to inactive list to prepare for eviction
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed bit in PTE to ensure eviction choice
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .zswap_fail_walk1
    and qword [rax], ~0x20          ; clear PAGE_ACCESSED

    ; Trigger Clock Eviction (which will try Zswap first)
    call page_replace_clock_evict
    test rax, rax
    jz .zswap_fail_evict1

    ; Verify Page is Evicted and Swapped to Zswap Cache
    ; 1. PTE Present bit should be 0
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .zswap_fail_walk_ev1
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .zswap_fail_still_present1

    ; 2. PTE PAGE_SWAPPED (bit 10) should be 1
    test rcx, 0x400                 ; PAGE_SWAPPED
    jz .zswap_fail_not_swapped1

    ; 3. PTE PAGE_ZSWAPPED (bit 11) should be 1
    test rcx, 0x800                 ; PAGE_ZSWAPPED
    jz .zswap_fail_not_zswapped1

    ; 4. Zswap telemetry should show 1 compressed page
    mov rax, [zswap_compressed_pages]
    cmp rax, 1
    jne .zswap_fail_telemetry1

    mov rsi, msg_zswap_evicted_ok
    call uart_print_str

    ; Access page to trigger transparent swap-in page fault (decompression)
    mov rax, [0x30000000]

    ; Verify data integrity after decompression
    mov rsi, 0x30000000             ; RSI = virtual address
    mov rbx, 0x53534552504D4F43     ; 'COMPRESS' in little-endian ("COMPRESSIBLE_SIG")
    cmp [rsi], rbx
    jne .zswap_fail_data_corrupt1

    ; Verify zswap telemetry returns to 0
    mov rax, [zswap_compressed_pages]
    test rax, rax
    jnz .zswap_fail_telemetry_res1

    ; Clean up Part 1
    mov rdi, 0x30000000
    call virt_translate
    mov r14, rax                    ; get new physical frame address

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r15
    call vma_destroy

    mov rsi, msg_zswap_comp_passed
    call uart_print_str


    ; --- Part 2: Uncompressible Page Test ---
    ; Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .zswap_fail_alloc2
    mov r14, rax

    ; Initialize page with an uncompressible ascending byte sequence (0, 1, 2, ... 255 repeating)
    mov rdi, r14
    xor rcx, rcx
.fill_uncompressible:
    cmp rcx, 4096
    jge .fill_uncomp_done
    mov rdx, rcx
    and rdx, 0xFF                   ; byte value sequence 0-255
    mov [rdi + rcx], dl
    inc rcx
    jmp .fill_uncompressible
.fill_uncomp_done:

    ; Set signature at start to verify data integrity
    mov rdi, r14
    mov rsi, msg_zswap_uncomp_sig
    mov rdx, 19                     ; length of "UNCOMPRESSIBLE_SIG" (18 + null)
    call memcpy

    ; Create VMA
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .zswap_fail_vma2
    mov r15, rax

    ; Map
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .zswap_fail_map2

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed bit in PTE
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .zswap_fail_walk2
    and qword [rax], ~0x20          ; clear Accessed

    ; Trigger clock eviction (which will attempt zswap, fail/bypass to disk swap)
    call page_replace_clock_evict
    test rax, rax
    jz .zswap_fail_evict2

    ; Verify Page is Evicted directly to Swap Disk (zswap bypass)
    ; 1. PTE Present bit should be 0
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .zswap_fail_walk_ev2
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .zswap_fail_still_present2

    ; 2. PTE PAGE_SWAPPED (bit 10) should be 1
    test rcx, 0x400
    jz .zswap_fail_not_swapped2

    ; 3. PTE PAGE_ZSWAPPED (bit 11) should be 0
    test rcx, 0x800
    jnz .zswap_fail_is_zswapped2

    ; 4. Zswap telemetry should be 0 (no pages compressed in zswap)
    mov rax, [zswap_compressed_pages]
    test rax, rax
    jnz .zswap_fail_telemetry2

    mov rsi, msg_zswap_disk_evicted_ok
    call uart_print_str

    ; Access page to trigger transparent swap-in page fault (from disk)
    mov rax, [0x30000000]

    ; Verify data integrity
    mov rsi, 0x30000000
    mov rbx, 0x4D4F434E55             ; 'UNCOM' in little-endian ("UNCOMPRESSIBLE_SIG")
    mov rax, [rsi]
    and rax, 0xFFFFFFFFFF             ; compare 5 bytes
    cmp rax, rbx
    jne .zswap_fail_data_corrupt2

    ; Clean up Part 2
    mov rdi, 0x30000000
    call virt_translate
    mov r14, rax

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r15
    call vma_destroy

    ; Zswap Test Suite PASSED!
    mov rsi, msg_zswap_test_passed
    call uart_print_str

    jmp .zram_test_start

.zram_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_zram_test_start
    call uart_print_str

    ; 1. Initialize ZRAM and register zram_swap_dev
    call zram_init

    lea rdi, [zram_swap_dev]
    call swap_register_device

    ; Verify that initial zram compressed pages telemetry is 0
    mov rax, [zram_compressed_pages]
    test rax, rax
    jnz .zram_fail_init_telemetry

    ; 2. Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .zram_fail_alloc
    mov r14, rax                    ; R14 = physical address

    ; 3. Fill with compressible data (repeated 0x55) and signature "ZRAM_LZ4_COMPRESSIBLE_PATTERN"
    mov rdi, r14
    mov al, 0x55
    mov rcx, 4096
    cld
    rep stosb

    mov rdi, r14
    mov rsi, msg_zram_sig
    mov rdx, 30                     ; length of "ZRAM_LZ4_COMPRESSIBLE_PATTERN"
    call memcpy

    ; 4. Create VMA at 0x30000000 and map
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .zram_fail_vma
    mov r15, rax                    ; R15 = VMA pointer

    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .zram_fail_map

    ; Move page to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed in PTE
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .zram_fail_walk
    and qword [rax], ~0x20          ; clear Accessed

    ; 5. Trigger Clock Eviction (which will try current_swap_device, i.e., ZRAM)
    call page_replace_clock_evict
    test rax, rax
    jz .zram_fail_evict

    ; 6. Verify that page is swapped to ZRAM
    ; PTE Present should be 0
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .zram_fail_walk_ev
    
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .zram_fail_still_present

    ; PTE PAGE_SWAPPED should be 1
    test rcx, 0x400                 ; PAGE_SWAPPED
    jz .zram_fail_not_swapped

    ; Telemetry should be 1
    mov rax, [zram_compressed_pages]
    cmp rax, 1
    jne .zram_fail_telemetry

    mov rsi, msg_zram_evicted_ok
    call uart_print_str

    ; 7. Access page to trigger page fault (decompression)
    mov rax, [0x30000000]

    ; 8. Verify decompressed data integrity
    mov rsi, 0x30000000
    mov rbx, 0x5F345A4C5F4D4152     ; "RAM_LZ4_"
    cmp [rsi], rbx
    jne .zram_fail_data_corrupt
    
    mov rbx, 0x504D4F435F454C42     ; "BLE_PATT"
    cmp [rsi + 8], rbx
    jne .zram_fail_data_corrupt

    ; Telemetry should return to 0
    mov rax, [zram_compressed_pages]
    test rax, rax
    jnz .zram_fail_telemetry_res

    ; Clean up
    mov rdi, 0x30000000
    call virt_translate
    mov r14, rax                    ; get new physical frame

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r15
    call vma_destroy

    ; Register back mock_swap_dev to restore default
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; ZRAM Test Suite PASSED!
    mov rsi, msg_zram_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .zpool_balance_test_start

.zpool_balance_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_zpool_balance_test_start
    call uart_print_str

    ; 1. Preserve original free_pages and total_pages
    mov r14, [phys_state + phys_state_t.free_pages]
    mov r15, [phys_state + phys_state_t.total_pages]

    ; Configure simulated physical state base: total_pages = 1000
    mov qword [phys_state + phys_state_t.total_pages], 1000

    ; --- Case 1: High Memory (> 50%) ---
    mov qword [phys_state + phys_state_t.free_pages], 600       ; 60% free
    call zpool_balance
    cmp qword [zswap_max_slots], 256
    jne .fail_high
    cmp qword [zram_max_slots], 256
    jne .fail_high

    ; --- Case 2: Moderate Memory (20% < free memory <= 50%) ---
    mov qword [phys_state + phys_state_t.free_pages], 350       ; 35% free
    call zpool_balance
    cmp qword [zswap_max_slots], 128
    jne .fail_mid
    cmp qword [zram_max_slots], 128
    jne .fail_mid

    ; --- Case 3: Low Memory (<= 20%) ---
    mov qword [phys_state + phys_state_t.free_pages], 150       ; 15% free
    call zpool_balance
    cmp qword [zswap_max_slots], 64
    jne .fail_low
    cmp qword [zram_max_slots], 64
    jne .fail_low

    ; --- Case 4: Rejection Verification (ZRAM) ---
    ; Manually set limit to 64 and telemetry to 64
    mov qword [zram_max_slots], 64
    mov qword [zram_compressed_pages], 64

    ; Allocate a source page for compression input
    call phys_alloc_page
    test rax, rax
    jz .fail_reject_zram_alloc
    mov r12, rax                    ; save page address

    ; Call zram_write_page with a valid slot index (e.g., 64)
    mov rdi, 64                     ; slot index
    mov rsi, r12                    ; source physical page
    call zram_write_page
    test rax, rax                   ; should return 0 (rejection)
    jnz .fail_reject_zram

    ; Free the page we allocated
    mov rdi, r12
    call phys_free_page

    ; --- Case 5: Rejection Verification (Zswap) ---
    ; Manually set limit to 64 and telemetry to 64
    mov qword [zswap_max_slots], 64
    mov qword [zswap_compressed_pages], 64

    ; Allocate source page
    call phys_alloc_page
    test rax, rax
    jz .fail_reject_zswap_alloc
    mov r12, rax

    ; Call zswap_compress_and_store
    mov rdi, r12
    call zswap_compress_and_store
    cmp rax, -1                     ; should return -1 (rejection)
    jne .fail_reject_zswap

    ; Free the page
    mov rdi, r12
    call phys_free_page

    ; 2. Restore original physical state
    mov [phys_state + phys_state_t.free_pages], r14
    mov [phys_state + phys_state_t.total_pages], r15

    ; Success!
    mov rsi, msg_zpool_balance_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .zpool_compact_test_start

.zpool_compact_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_zpool_compact_test_start
    call uart_print_str

    ; -------------------------------------------------------------
    ; Part 1: Zswap Compaction Test
    ; -------------------------------------------------------------
    ; Register clean mock RAM swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Set zswap max slots to 256 and clear telemetry
    mov qword [zswap_max_slots], 256
    mov qword [zswap_compressed_pages], 0

    ; --- Step A: Setup Page A (Virtual: 0x30000000, Pattern: 0xAA) ---
    call phys_alloc_page
    test rax, rax
    jz .compact_fail_alloc
    mov r12, rax                    ; r12 = Page A physical address

    mov rdi, r12
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    ; Set signature in Page A
    mov rdi, r12
    mov rsi, msg_zswap_comp_sig
    mov rdx, 17
    call memcpy

    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .compact_fail_vma
    mov r14, rax                    ; r14 = VMA A pointer

    mov rdi, 0x30000000
    mov rsi, r12
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .compact_fail_map

    mov rdi, r12
    call page_list_move_to_inactive

    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20          ; clear ACCESSED

    call page_replace_clock_evict
    test rax, rax
    jz .compact_fail_evict

    ; --- Step B: Setup Page B (Virtual: 0x40000000, Pattern: 0xBB) ---
    call phys_alloc_page
    test rax, rax
    jz .compact_fail_alloc
    mov r13, rax                    ; r13 = Page B physical address

    mov rdi, r13
    mov al, 0xBB
    mov rcx, 4096
    cld
    rep stosb

    ; Set signature in Page B
    mov rdi, r13
    mov qword [rdi], 0x4242424242424242 ; "BBBBBBBB"
    mov qword [rdi + 8], 0x4242424242424242

    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .compact_fail_vma
    mov r15, rax                    ; r15 = VMA B pointer

    mov rdi, 0x40000000
    mov rsi, r13
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .compact_fail_map

    mov rdi, r13
    call page_list_move_to_inactive

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20          ; clear ACCESSED

    call page_replace_clock_evict
    test rax, rax
    jz .compact_fail_evict

    ; --- Step C: Read/Swap-in Page A (frees slot 0) ---
    mov rax, [0x30000000]

    ; --- Step D: Run Zswap Compaction (migrates slot 1 to slot 0) ---
    call zswap_compact

    ; --- Step E: Verify metadata ---
    ; slot 0 must be in-use (1), slot 1 must be free (0)
    lea rcx, [zswap_in_use]
    mov al, [rcx + 0]
    cmp al, 1
    jne .fail_zswap_inuse
    mov al, [rcx + 1]
    cmp al, 0
    jne .fail_zswap_inuse

    ; --- Step F: Read/Swap-in Page B (decompresses from slot 0) ---
    mov rax, [0x40000000]

    ; Verify Page B data integrity
    mov rdi, 0x40000000
    mov rax, [rdi]
    mov rbx, 0x4242424242424242
    cmp rax, rbx
    jne .fail_zswap_data

    ; Clean up Part 1
    mov rdi, 0x30000000
    call virt_translate
    mov r12, rax
    mov rdi, 0x30000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r14
    call vma_destroy

    mov rdi, 0x40000000
    call virt_translate
    mov r13, rax
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r13
    call phys_free_page
    mov rdi, r15
    call vma_destroy


    ; -------------------------------------------------------------
    ; Part 2: ZRAM Compaction Test
    ; -------------------------------------------------------------
    ; Register ZRAM swap device
    call zram_init
    lea rdi, [zram_swap_dev]
    call swap_register_device

    ; Set zram max slots and clear telemetry
    mov qword [zram_max_slots], 256
    mov qword [zram_compressed_pages], 0

    ; --- Step A: Setup Page A (Virtual: 0x30000000, Pattern: 0xAA) ---
    call phys_alloc_page
    test rax, rax
    jz .compact_fail_alloc
    mov r12, rax

    mov rdi, r12
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    ; Set signature in Page A
    mov rdi, r12
    mov rsi, msg_zram_sig
    mov rdx, 30
    call memcpy

    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .compact_fail_vma
    mov r14, rax

    mov rdi, 0x30000000
    mov rsi, r12
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .compact_fail_map

    mov rdi, r12
    call page_list_move_to_inactive

    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20

    call page_replace_clock_evict
    test rax, rax
    jz .compact_fail_evict

    ; --- Step B: Setup Page B (Virtual: 0x40000000, Pattern: 0xBB) ---
    call phys_alloc_page
    test rax, rax
    jz .compact_fail_alloc
    mov r13, rax

    mov rdi, r13
    mov al, 0xBB
    mov rcx, 4096
    cld
    rep stosb

    ; Set signature in Page B
    mov rdi, r13
    mov qword [rdi], 0x4242424242424242
    mov qword [rdi + 8], 0x4242424242424242

    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .compact_fail_vma
    mov r15, rax

    mov rdi, 0x40000000
    mov rsi, r13
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .compact_fail_map

    mov rdi, r13
    call page_list_move_to_inactive

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20

    call page_replace_clock_evict
    test rax, rax
    jz .compact_fail_evict

    ; --- Step C: Read/Swap-in Page A ---
    mov rax, [0x30000000]

    ; --- Step D: Run ZRAM Compaction ---
    call zram_compact

    ; --- Step E: Verify metadata ---
    lea rcx, [zram_in_use]
    mov al, [rcx + 0]
    cmp al, 1
    jne .fail_zram_inuse
    mov al, [rcx + 1]
    cmp al, 0
    jne .fail_zram_inuse

    ; --- Step F: Read/Swap-in Page B ---
    mov rax, [0x40000000]

    ; Verify Page B data integrity
    mov rdi, 0x40000000
    mov rax, [rdi]
    mov rbx, 0x4242424242424242
    cmp rax, rbx
    jne .fail_zram_data

    ; Clean up Part 2
    mov rdi, 0x30000000
    call virt_translate
    mov r12, rax
    mov rdi, 0x30000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r14
    call vma_destroy

    mov rdi, 0x40000000
    call virt_translate
    mov r13, rax
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r13
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    ; Register back mock RAM device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Success!
    mov rsi, msg_zpool_compact_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .zpool_writeback_test_start

.zpool_writeback_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_zpool_writeback_test_start
    call uart_print_str

    ; -------------------------------------------------------------
    ; Part 1: Zswap Writeback Pipeline Test
    ; -------------------------------------------------------------
    ; Register clean mock RAM swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Set zswap max slots to 1 (simulate immediate limit) and clear telemetry
    mov qword [zswap_max_slots], 1
    mov qword [zswap_compressed_pages], 0

    ; --- Step A: Evict Page A (goes to Zswap slot 0) ---
    call phys_alloc_page
    test rax, rax
    jz .wb_fail_alloc
    mov r12, rax                    ; r12 = Page A physical address

    mov rdi, r12
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    mov rdi, r12
    mov rsi, msg_zswap_comp_sig
    mov rdx, 17
    call memcpy

    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .wb_fail_vma
    mov r14, rax                    ; r14 = VMA A pointer

    mov rdi, 0x30000000
    mov rsi, r12
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .wb_fail_map

    mov rdi, r12
    call page_list_move_to_inactive

    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20          ; clear ACCESSED

    call page_replace_clock_evict
    test rax, rax
    jz .wb_fail_evict

    ; --- Step B: Evict Page B (hits limit 1, triggers writeback of Page A) ---
    call phys_alloc_page
    test rax, rax
    jz .wb_fail_alloc
    mov r13, rax                    ; r13 = Page B physical address

    mov rdi, r13
    mov al, 0xBB
    mov rcx, 4096
    cld
    rep stosb

    ; Set recognizable data for Page B
    mov rdi, r13
    mov qword [rdi], 0x5555555555555555
    mov qword [rdi + 8], 0x5555555555555555

    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .wb_fail_vma
    mov r15, rax                    ; r15 = VMA B pointer

    mov rdi, 0x40000000
    mov rsi, r13
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .wb_fail_map

    mov rdi, r13
    call page_list_move_to_inactive

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20

    call page_replace_clock_evict
    test rax, rax
    jz .wb_fail_evict

    ; --- Step C: Verify Page A PTE updated (should be Swapped, not Zswapped) ---
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rcx, [rax]
    test rcx, 0x800                 ; PAGE_ZSWAPPED (bit 11) should be 0!
    jnz .fail_zswap_flags

    ; --- Step D: Read Page A (swaps-in from physical swap) ---
    mov rax, [0x30000000]

    ; Verify Page A contents
    mov rdi, 0x30000000
    mov rsi, msg_zswap_comp_sig
    mov rdx, 16                     ; compare 16 bytes signature
    call memcmp
    test rax, rax
    jnz .fail_zswap_data

    ; --- Step E: Read Page B (swaps-in from Zswap) ---
    mov rax, [0x40000000]

    ; Verify Page B data
    mov rdi, 0x40000000
    mov rax, [rdi]
    mov rbx, 0x5555555555555555
    cmp rax, rbx
    jne .fail_zswap_data

    ; Clean up Part 1
    mov rdi, 0x30000000
    call virt_translate
    mov r12, rax
    mov rdi, 0x30000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r14
    call vma_destroy

    mov rdi, 0x40000000
    call virt_translate
    mov r13, rax
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r13
    call phys_free_page
    mov rdi, r15
    call vma_destroy


    ; -------------------------------------------------------------
    ; Part 2: ZRAM Writeback Pipeline Test
    ; -------------------------------------------------------------
    ; Register ZRAM swap device
    call zram_init
    lea rdi, [zram_swap_dev]
    call swap_register_device

    ; Set zram max slots to 1 and clear telemetry
    mov qword [zram_max_slots], 1
    mov qword [zram_compressed_pages], 0

    ; --- Step A: Evict Page A (goes to ZRAM slot 0) ---
    call phys_alloc_page
    test rax, rax
    jz .wb_fail_alloc
    mov r12, rax

    mov rdi, r12
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    mov rdi, r12
    mov rsi, msg_zram_sig
    mov rdx, 30
    call memcpy

    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .wb_fail_vma
    mov r14, rax

    mov rdi, 0x30000000
    mov rsi, r12
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .wb_fail_map

    mov rdi, r12
    call page_list_move_to_inactive

    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20

    call page_replace_clock_evict
    test rax, rax
    jz .wb_fail_evict

    ; --- Step B: Evict Page B (hits limit 1, triggers writeback of Page A) ---
    call phys_alloc_page
    test rax, rax
    jz .wb_fail_alloc
    mov r13, rax

    mov rdi, r13
    mov al, 0xBB
    mov rcx, 4096
    cld
    rep stosb

    mov rdi, r13
    mov qword [rdi], 0x5555555555555555
    mov qword [rdi + 8], 0x5555555555555555

    mov rdi, 0x40000000
    mov rsi, r13
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .wb_fail_map

    mov rdi, r13
    call page_list_move_to_inactive

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20

    call page_replace_clock_evict
    test rax, rax
    jz .wb_fail_evict

    ; --- Step C: Verify Page A PTE updated (should have PAGE_ZRAM cleared) ---
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rcx, [rax]
    test rcx, 0x100                 ; PAGE_ZRAM (bit 8) should be 0!
    jnz .fail_zram_flags

    ; --- Step D: Read Page A (swaps-in from physical swap) ---
    mov rax, [0x30000000]

    ; Verify Page A contents
    mov rdi, 0x30000000
    mov rsi, msg_zram_sig
    mov rdx, 29
    call memcmp
    test rax, rax
    jnz .fail_zram_data

    ; --- Step E: Read Page B (swaps-in from ZRAM) ---
    mov rax, [0x40000000]

    ; Verify Page B data
    mov rdi, 0x40000000
    mov rax, [rdi]
    mov rbx, 0x5555555555555555
    cmp rax, rbx
    jne .fail_zram_data

    ; Clean up Part 2
    mov rdi, 0x30000000
    call virt_translate
    mov r12, rax
    mov rdi, 0x30000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r14
    call vma_destroy

    mov rdi, 0x40000000
    call virt_translate
    mov r13, rax
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r13
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    ; Restore clean mock swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Success!
    mov rsi, msg_zpool_writeback_test_passed
    call uart_print_str

    jmp .zpool_decomp_test_start

.zpool_decomp_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_zpool_decomp_test_start
    call uart_print_str

    ; Allocate Page A (pattern 0xAA)
    call phys_alloc_page
    test rax, rax
    jz .decomp_fail_alloc
    mov r12, rax                    ; r12 = Page A physical address

    mov rdi, r12
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    ; Set signature in Page A
    mov rdi, r12
    mov rsi, msg_zram_sig           ; use existing ZRAM test sig
    mov rdx, 30
    call memcpy

    ; Allocate Page B (pattern 0xBB)
    call phys_alloc_page
    test rax, rax
    jz .decomp_fail_alloc
    mov r13, rax                    ; r13 = Page B physical address

    mov rdi, r13
    mov al, 0xBB
    mov rcx, 4096
    cld
    rep stosb

    ; Set signature in Page B
    mov rdi, r13
    mov qword [rdi], 0x4242424242424242
    mov qword [rdi + 8], 0x4242424242424242

    ; Allocate temporary compression destinations
    call phys_alloc_page
    test rax, rax
    jz .decomp_fail_alloc
    mov r14, rax                    ; r14 = comp_A_page

    call phys_alloc_page
    test rax, rax
    jz .decomp_fail_alloc
    mov r15, rax                    ; r15 = comp_B_page

    ; Compress Page A (ZRAM LZ4)
    extern lz4_compress
    mov rdi, r12                    ; src
    mov rsi, r14                    ; dest (scratch page)
    mov rdx, 2048                   ; max size
    call lz4_compress
    test rax, rax
    jz .decomp_fail_comp
    mov r8, rax                     ; r8 = comp_size_A

    ; Compress Page B (ZRAM LZ4)
    push r8                         ; preserve comp_size_A
    mov rdi, r13                    ; src
    mov rsi, r15                    ; dest
    mov rdx, 2048
    call lz4_compress
    pop r8                          ; restore comp_size_A
    test rax, rax
    jz .decomp_fail_comp
    mov r9, rax                     ; r9 = comp_size_B

    ; Allocate destination uncompressed page frames
    call phys_alloc_page
    test rax, rax
    jz .decomp_fail_alloc
    mov [dest_phys_A], rax

    call phys_alloc_page
    test rax, rax
    jz .decomp_fail_alloc
    mov [dest_phys_B], rax

    ; --- Setup Request A (in BSS) ---
    lea rdx, [req_A]
    mov [rdx + zpool_decomp_req_t.src_addr], r14
    mov rax, [dest_phys_A]
    mov [rdx + zpool_decomp_req_t.dest_addr], rax
    mov [rdx + zpool_decomp_req_t.comp_size], r8
    mov qword [rdx + zpool_decomp_req_t.pool_type], 0 ; 0 = ZRAM (LZ4)
    mov qword [rdx + zpool_decomp_req_t.status], 0

    ; --- Setup Request B (in BSS) ---
    lea rdx, [req_B]
    mov [rdx + zpool_decomp_req_t.src_addr], r15
    mov rax, [dest_phys_B]
    mov [rdx + zpool_decomp_req_t.dest_addr], rax
    mov [rdx + zpool_decomp_req_t.comp_size], r9
    mov qword [rdx + zpool_decomp_req_t.pool_type], 0 ; 0 = ZRAM (LZ4)
    mov qword [rdx + zpool_decomp_req_t.status], 0

    ; --- Setup pointer array ---
    lea rdx, [req_ptrs]
    lea rax, [req_A]
    mov [rdx], rax
    lea rax, [req_B]
    mov [rdx + 8], rax

    ; Submit batch decompression
    mov rdi, rdx                    ; ptrs array
    mov rsi, 2                      ; count
    call zpool_batch_decompress_submit
    cmp rax, 2                      ; should successfully process 2 requests
    jne .decomp_fail_submit

    ; Verify status
    lea rdx, [req_A]
    mov rax, [rdx + zpool_decomp_req_t.status]
    cmp rax, 1
    jne .decomp_fail_status

    lea rdx, [req_B]
    mov rax, [rdx + zpool_decomp_req_t.status]
    cmp rax, 1
    jne .decomp_fail_status

    ; Verify decompressed data integrity
    mov rsi, [dest_phys_A]
    mov rdi, msg_zram_sig
    mov rdx, 30
    call memcmp
    test rax, rax
    jnz .decomp_fail_data

    mov rsi, [dest_phys_B]
    mov rax, [rsi]
    mov rbx, 0x4242424242424242
    cmp rax, rbx
    jne .decomp_fail_data

    ; Clean up all allocated pages
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call phys_free_page
    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call phys_free_page

    mov rdi, [dest_phys_A]
    call phys_free_page
    mov rdi, [dest_phys_B]
    call phys_free_page

    ; Success!
    mov rsi, msg_zpool_decomp_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .dbg_watch_test_start

.dbg_watch_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_dbg_watch_test_start
    call uart_print_str

    ; 1. Initialize dirty tracing
    call dbg_dirty_trace_init

    ; 2. Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .dbg_watch_fail_alloc
    mov [dbg_watch_phys_page], rax

    ; 3. Create a writable user VMA at 0x30000000
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .dbg_watch_fail_vma
    mov [dbg_watch_vma_ptr], rax

    ; 4. Map the physical page at 0x30000000
    mov rdi, 0x30000000
    mov rsi, [dbg_watch_phys_page]
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .dbg_watch_fail_map

    ; 5. Register page for dirty tracing
    mov rdi, 0x30000000
    call dbg_dirty_trace_register
    cmp rax, 1
    jne .dbg_watch_fail_register

    ; 6. Verify that page has been write-protected in PTE (PAGE_WRITABLE cleared)
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_watch_fail_walk
    mov rbx, [rax]
    test rbx, 2                     ; PAGE_WRITABLE (bit 1) should be 0!
    jnz .dbg_watch_fail_protected

    ; 7. Check that page is NOT dirty initially
    mov rdi, 0x30000000
    call dbg_dirty_trace_is_dirty
    test rax, rax
    jnz .dbg_watch_fail_dirty_init

    ; 8. Perform a write to the page to trigger the emulated dirty tracing page fault!
.dbg_write_ip:
    mov qword [0x30000000], 0x123456789ABCDEF0

    ; 9. Verify that the write succeeded
    mov rax, [0x30000000]
    mov rbx, 0x123456789ABCDEF0
    cmp rax, rbx
    jne .dbg_watch_fail_dirty_post

    ; 10. Check that page is now marked dirty
    mov rdi, 0x30000000
    call dbg_dirty_trace_is_dirty
    cmp rax, 1
    jne .dbg_watch_fail_dirty_post

    ; 11. Check that the logged RIP matches the instruction that did the write
    mov rdi, 0x30000000
    call dbg_dirty_trace_get_rip
    lea rdx, [.dbg_write_ip]
    cmp rax, rdx
    jne .dbg_watch_fail_rip_mismatch

    ; 12. Check that PAGE_WRITABLE was restored in the PTE
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_watch_fail_walk
    mov rbx, [rax]
    test rbx, 2                     ; PAGE_WRITABLE (bit 1) should be 1 now!
    jz .dbg_watch_fail_writable_post

    ; 13. Clear the dirty status
    mov rdi, 0x30000000
    call dbg_dirty_trace_clear_dirty
    cmp rax, 1
    jne .dbg_watch_fail_clear

    ; 14. Verify that page is clean, RIP is 0, and PAGE_WRITABLE is cleared again
    mov rdi, 0x30000000
    call dbg_dirty_trace_is_dirty
    test rax, rax
    jnz .dbg_watch_fail_dirty_clear

    mov rdi, 0x30000000
    call dbg_dirty_trace_get_rip
    test rax, rax
    jnz .dbg_watch_fail_rip_clear

    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_watch_fail_walk
    mov rbx, [rax]
    test rbx, 2                     ; PAGE_WRITABLE (bit 1) should be 0 again!
    jnz .dbg_watch_fail_protected_clear

    ; 15. Deregister, unmap, and free resources
    mov rdi, 0x30000000
    call dbg_dirty_trace_deregister
    cmp rax, 1
    jne .dbg_watch_fail_clear

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, [dbg_watch_phys_page]
    call phys_free_page

    mov rdi, [dbg_watch_vma_ptr]
    call vma_destroy

    ; Success!
    mov rsi, msg_dbg_watch_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .dbg_wp_test_start

.dbg_wp_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_dbg_wp_test_start
    call uart_print_str

    ; 1. Initialize watchpoints
    call dbg_watchpoint_init

    ; 2. Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .dbg_wp_fail_alloc
    mov [dbg_wp_phys_page], rax

    ; 3. Create a writable user VMA at 0x30000000
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .dbg_wp_fail_vma
    mov [dbg_wp_vma_ptr], rax

    ; 4. Map the physical page at 0x30000000
    mov rdi, 0x30000000
    mov rsi, [dbg_wp_phys_page]
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .dbg_wp_fail_map

    ; 5. Register page for watchpoint
    mov rdi, 0x30000000
    call dbg_watchpoint_register
    cmp rax, 1
    jne .dbg_wp_fail_register

    ; 6. Verify that page has been marked non-present in PTE (PAGE_PRESENT cleared)
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_wp_fail_walk
    mov rbx, [rax]
    test rbx, 1                     ; PAGE_PRESENT (bit 0) should be 0!
    jnz .dbg_wp_fail_non_present

    ; 7. Check that watchpoint has 0 hits initially
    mov rdi, 0x30000000
    call dbg_watchpoint_is_hit
    test rax, rax
    jnz .dbg_wp_fail_hit_init

    ; 8. Perform a READ access to trigger the watchpoint page fault!
.wp_read_ip:
    mov rax, [0x30000000]

    ; 9. Verify hit count incremented to 1
    mov rdi, 0x30000000
    call dbg_watchpoint_is_hit
    cmp rax, 1
    jne .dbg_wp_fail_hit_read

    ; 10. Verify recorded instruction pointer matches .wp_read_ip
    mov rdi, 0x30000000
    call dbg_watchpoint_get_last_rip
    lea rdx, [.wp_read_ip]
    cmp rax, rdx
    jne .dbg_wp_fail_rip_read

    ; 11. Verify transaction type is 0 (read)
    mov rdi, 0x30000000
    call dbg_watchpoint_get_last_type
    test rax, rax
    jnz .dbg_wp_fail_type_read

    ; 12. Verify that PTE has PRESENT set back to 1
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_wp_fail_walk
    mov rbx, [rax]
    test rbx, 1                     ; PAGE_PRESENT (bit 0) should be 1 now!
    jz .dbg_wp_fail_present_read

    ; 13. Rearm the watchpoint
    mov rdi, 0x30000000
    call dbg_watchpoint_rearm
    cmp rax, 1
    jne .dbg_wp_fail_rearm

    ; Verify it became non-present again
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    test rbx, 1
    jnz .dbg_wp_fail_non_present

    ; 14. Perform a WRITE access to trigger watchpoint page fault again!
.wp_write_ip:
    mov qword [0x30000000], 0xDEADBEEFCAFEBAB1

    ; Verify the write completed
    mov rax, [0x30000000]
    mov rbx, 0xDEADBEEFCAFEBAB1
    cmp rax, rbx
    jne .dbg_wp_fail_hit_write

    ; 15. Verify hit count incremented to 2
    mov rdi, 0x30000000
    call dbg_watchpoint_is_hit
    cmp rax, 2
    jne .dbg_wp_fail_hit_write

    ; 16. Verify recorded instruction pointer matches .wp_write_ip
    mov rdi, 0x30000000
    call dbg_watchpoint_get_last_rip
    lea rdx, [.wp_write_ip]
    cmp rax, rdx
    jne .dbg_wp_fail_rip_write

    ; 17. Verify transaction type is 1 (write)
    mov rdi, 0x30000000
    call dbg_watchpoint_get_last_type
    cmp rax, 1
    jne .dbg_wp_fail_type_write

    ; 18. Deregister watchpoint, unmap and free resources
    mov rdi, 0x30000000
    call dbg_watchpoint_deregister
    cmp rax, 1
    jne .dbg_wp_fail_deregister

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, [dbg_wp_phys_page]
    call phys_free_page

    mov rdi, [dbg_wp_vma_ptr]
    call vma_destroy

    ; Success!
    mov rsi, msg_dbg_wp_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .dbg_ift_test_start

.dbg_ift_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_dbg_ift_test_start
    call uart_print_str

    ; 1. Initialize IFT watchpoints
    call dbg_ift_init

    ; 2. Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .dbg_ift_fail_alloc
    mov [dbg_ift_phys_page], rax

    ; 3. Write ret (0xC3) to the start of the page
    mov rdi, rax
    mov byte [rdi], 0xC3

    ; 4. Create an executable user VMA at 0x40000000
    ; Flags: VMA_READ | VMA_EXEC | VMA_USER (0x0D)
    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0D
    call vma_create
    test rax, rax
    jz .dbg_ift_fail_vma
    mov [dbg_ift_vma_ptr], rax

    ; 5. Map the physical page at 0x40000000
    ; Flags: PAGE_PRESENT | PAGE_USER (0x05)
    mov rdi, 0x40000000
    mov rsi, [dbg_ift_phys_page]
    mov rdx, 0x05
    call virt_map
    test rax, rax
    jz .dbg_ift_fail_map

    ; 6. Register page for IFT watchpoint
    mov rdi, 0x40000000
    call dbg_ift_register
    cmp rax, 1
    jne .dbg_ift_fail_register

    ; 7. Verify that page has been marked NX in PTE
    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_ift_fail_walk
    mov rbx, [rax]
    mov rcx, PAGE_NX
    test rbx, rcx                   ; PAGE_NX (bit 63) should be 1
    jz .dbg_ift_fail_nx_set

    ; 8. Check that IFT has 0 hits initially
    mov rdi, 0x40000000
    call dbg_ift_is_hit
    test rax, rax
    jnz .dbg_ift_fail_hit_init

    ; 9. Attempt to call 0x40000000 to trigger instruction fetch fault!
    mov rax, 0x40000000
    call rax

    ; 10. Verify hit count incremented to 1
    mov rdi, 0x40000000
    call dbg_ift_is_hit
    cmp rax, 1
    jne .dbg_ift_fail_hit_exec

    ; 11. Verify recorded RIP matches 0x40000000
    mov rdi, 0x40000000
    call dbg_ift_get_last_rip
    mov rbx, 0x40000000
    cmp rax, rbx
    jne .dbg_ift_fail_rip_exec

    ; 12. Verify that PTE has NX set to 0 (executable again)
    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_ift_fail_walk
    mov rbx, [rax]
    mov rcx, PAGE_NX
    test rbx, rcx                   ; PAGE_NX should be 0 now!
    jnz .dbg_ift_fail_nx_cleared

    ; 13. Rearm the IFT watchpoint
    mov rdi, 0x40000000
    call dbg_ift_rearm
    cmp rax, 1
    jne .dbg_ift_fail_rearm

    ; Verify NX is set back to 1
    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    mov rcx, PAGE_NX
    test rbx, rcx
    jz .dbg_ift_fail_nx_rearmed

    ; 14. Attempt to call 0x40000000 again!
    mov rax, 0x40000000
    call rax

    ; 15. Verify hit count incremented to 2
    mov rdi, 0x40000000
    call dbg_ift_is_hit
    cmp rax, 2
    jne .dbg_ift_fail_hit_exec2

    ; 16. Verify recorded RIP is still 0x40000000
    mov rdi, 0x40000000
    call dbg_ift_get_last_rip
    mov rbx, 0x40000000
    cmp rax, rbx
    jne .dbg_ift_fail_rip_exec2

    ; 17. Deregister watchpoint, unmap and free resources
    mov rdi, 0x40000000
    call dbg_ift_deregister
    cmp rax, 1
    jne .dbg_ift_fail_deregister

    mov rdi, 0x40000000
    call virt_unmap

    mov rdi, [dbg_ift_phys_page]
    call phys_free_page

    mov rdi, [dbg_ift_vma_ptr]
    call vma_destroy

    ; Success!
    mov rsi, msg_dbg_ift_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .dbg_hist_test_start

.dbg_hist_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_dbg_hist_test_start
    call uart_print_str

    ; 1. Initialize access pattern histogram recorder
    call dbg_hist_init

    ; 2. Allocate physical page
    call phys_alloc_page
    test rax, rax
    jz .dbg_hist_fail_alloc
    mov [dbg_hist_phys_page], rax

    ; 3. Create a writable user VMA at 0x30000000
    ; Flags: VMA_READ | VMA_WRITE | VMA_USER (0x0B)
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .dbg_hist_fail_vma
    mov [dbg_hist_vma_ptr], rax

    ; 4. Map the physical page at 0x30000000
    ; Flags: PRESENT | WRITE | USER (0x07)
    mov rdi, 0x30000000
    mov rsi, [dbg_hist_phys_page]
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .dbg_hist_fail_map

    ; 5. Register page for access tracking
    mov rdi, 0x30000000
    call dbg_hist_register
    cmp rax, 1
    jne .dbg_hist_fail_register

    ; 6. Verify that page has been marked non-present in PTE
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_hist_fail_walk
    mov rbx, [rax]
    test rbx, 1                     ; PAGE_PRESENT (bit 0) should be 0
    jnz .dbg_hist_fail_non_present

    ; 7. Check initial counters are 0
    mov rdi, 0x30000000
    call dbg_hist_get_read_count
    test rax, rax
    jnz .dbg_hist_fail_count_init

    mov rdi, 0x30000000
    call dbg_hist_get_write_count
    test rax, rax
    jnz .dbg_hist_fail_count_init

    mov rdi, 0x30000000
    call dbg_hist_get_total_count
    test rax, rax
    jnz .dbg_hist_fail_count_init

    ; 8. Perform a READ access to trigger page fault!
    mov rax, [0x30000000]

    ; 9. Verify hit count updates (Read=1, Write=0, Total=1)
    mov rdi, 0x30000000
    call dbg_hist_get_read_count
    cmp rax, 1
    jne .dbg_hist_fail_read_count

    mov rdi, 0x30000000
    call dbg_hist_get_write_count
    test rax, rax
    jnz .dbg_hist_fail_write_count

    mov rdi, 0x30000000
    call dbg_hist_get_total_count
    cmp rax, 1
    jne .dbg_hist_fail_total_count

    ; 10. Verify that PTE has PRESENT restored to 1
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .dbg_hist_fail_walk
    mov rbx, [rax]
    test rbx, 1                     ; PAGE_PRESENT (bit 0) should be 1
    jz .dbg_hist_fail_present_restored

    ; 11. Rearm the histogram recorder
    mov rdi, 0x30000000
    call dbg_hist_rearm
    cmp rax, 1
    jne .dbg_hist_fail_rearm

    ; Verify non-present again
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    test rbx, 1
    jnz .dbg_hist_fail_non_present

    ; 12. Perform a WRITE access to trigger page fault!
    mov qword [0x30000000], 0x12345678ABCD

    ; 13. Verify hit count updates (Read=1, Write=1, Total=2)
    mov rdi, 0x30000000
    call dbg_hist_get_read_count
    cmp rax, 1
    jne .dbg_hist_fail_read_count2

    mov rdi, 0x30000000
    call dbg_hist_get_write_count
    cmp rax, 1
    jne .dbg_hist_fail_write_count2

    mov rdi, 0x30000000
    call dbg_hist_get_total_count
    cmp rax, 2
    jne .dbg_hist_fail_total_count2

    ; 14. Rearm again
    mov rdi, 0x30000000
    call dbg_hist_rearm
    cmp rax, 1
    jne .dbg_hist_fail_rearm

    ; 15. Perform another READ access
    mov rax, [0x30000000]

    ; 16. Verify hit count updates (Read=2, Write=1, Total=3)
    mov rdi, 0x30000000
    call dbg_hist_get_read_count
    cmp rax, 2
    jne .dbg_hist_fail_read_count3

    mov rdi, 0x30000000
    call dbg_hist_get_write_count
    cmp rax, 1
    jne .dbg_hist_fail_write_count3

    mov rdi, 0x30000000
    call dbg_hist_get_total_count
    cmp rax, 3
    jne .dbg_hist_fail_total_count3

    ; 17. Deregister, unmap and free
    mov rdi, 0x30000000
    call dbg_hist_deregister
    cmp rax, 1
    jne .dbg_hist_fail_deregister

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, [dbg_hist_phys_page]
    call phys_free_page

    mov rdi, [dbg_hist_vma_ptr]
    call vma_destroy

    ; Success!
    mov rsi, msg_dbg_hist_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .dbg_phys_wp_test_start

.dbg_phys_wp_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_dbg_phys_wp_test_start
    call uart_print_str

    ; 1. Initialize physical watchpoints
    call dbg_phys_wp_init

    ; 2. Allocate physical page
    call phys_alloc_page
    test rax, rax
    jz .dbg_phys_wp_fail_alloc
    mov [dbg_phys_wp_phys_page], rax
    mov r12, rax                    ; r12 = physical page frame address

    ; 3. Create Alias 1 VMA at 0x30000000
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .dbg_phys_wp_fail_vma1
    mov [dbg_phys_wp_vma1_ptr], rax

    ; 4. Create Alias 2 VMA at 0x40000000
    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .dbg_phys_wp_fail_vma2
    mov [dbg_phys_wp_vma2_ptr], rax

    ; 5. Map Alias 1
    mov rdi, 0x30000000
    mov rsi, r12
    mov rdx, 0x07                   ; P | W | U
    call virt_map
    test rax, rax
    jz .dbg_phys_wp_fail_map1

    ; 6. Map Alias 2
    mov rdi, 0x40000000
    mov rsi, r12
    mov rdx, 0x07                   ; P | W | U
    call virt_map
    test rax, rax
    jz .dbg_phys_wp_fail_map2

    ; 7. Register physical watchpoint
    mov rdi, r12
    call dbg_phys_wp_register
    cmp rax, 1
    jne .dbg_phys_wp_fail_register

    ; 8. Verify that PRESENT is 0 in BOTH page table entries
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .dbg_phys_wp_fail_walk
    mov rbx, [rax]
    test rbx, 1                     ; PRESENT should be 0
    jnz .dbg_phys_wp_fail_non_present

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .dbg_phys_wp_fail_walk
    mov rbx, [rax]
    test rbx, 1                     ; PRESENT should be 0
    jnz .dbg_phys_wp_fail_non_present

    ; 9. Check initial hit count is 0
    mov rdi, r12
    call dbg_phys_wp_get_hit_count
    test rax, rax
    jnz .dbg_phys_wp_fail_hit_init

    ; 10. Perform a READ access to Alias 1 to trigger fault!
.phys_read_ip:
    mov rax, [0x30000000]

    ; 11. Verify hit count is 1
    mov rdi, r12
    call dbg_phys_wp_get_hit_count
    cmp rax, 1
    jne .dbg_phys_wp_fail_hit_read

    ; 12. Verify last RIP matches .phys_read_ip
    mov rdi, r12
    call dbg_phys_wp_get_last_rip
    lea rdx, [.phys_read_ip]
    cmp rax, rdx
    jne .dbg_phys_wp_fail_rip_read

    ; 13. Verify last vaddr is 0x30000000
    mov rdi, r12
    call dbg_phys_wp_get_last_vaddr
    mov rdx, 0x30000000
    cmp rax, rdx
    jne .dbg_phys_wp_fail_vaddr_read

    ; 14. Verify access type is 0 (read)
    mov rdi, r12
    call dbg_phys_wp_get_last_type
    test rax, rax
    jnz .dbg_phys_wp_fail_type_read

    ; 15. Verify that PRESENT is restored to 1 in BOTH page table entries
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    test rbx, 1
    jz .dbg_phys_wp_fail_present_restored

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    test rbx, 1
    jz .dbg_phys_wp_fail_present_restored

    ; 16. Rearm the physical watchpoint
    mov rdi, r12
    call dbg_phys_wp_rearm
    cmp rax, 1
    jne .dbg_phys_wp_fail_rearm

    ; Verify PRESENT is 0 in BOTH entries again
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    test rbx, 1
    jnz .dbg_phys_wp_fail_non_present

    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    mov rbx, [rax]
    test rbx, 1
    jnz .dbg_phys_wp_fail_non_present

    ; 17. Perform a WRITE access to Alias 2 to trigger fault!
.phys_write_ip:
    mov qword [0x40000000], 0x12345678DEADBEEF

    ; 18. Verify hit count is 2
    mov rdi, r12
    call dbg_phys_wp_get_hit_count
    cmp rax, 2
    jne .dbg_phys_wp_fail_hit_write

    ; 19. Verify last RIP matches .phys_write_ip
    mov rdi, r12
    call dbg_phys_wp_get_last_rip
    lea rdx, [.phys_write_ip]
    cmp rax, rdx
    jne .dbg_phys_wp_fail_rip_write

    ; 20. Verify last vaddr is 0x40000000
    mov rdi, r12
    call dbg_phys_wp_get_last_vaddr
    mov rdx, 0x40000000
    cmp rax, rdx
    jne .dbg_phys_wp_fail_vaddr_write

    ; 21. Verify access type is 1 (write)
    mov rdi, r12
    call dbg_phys_wp_get_last_type
    cmp rax, 1
    jne .dbg_phys_wp_fail_type_write

    ; 22. Deregister watchpoint, unmap and free
    mov rdi, r12
    call dbg_phys_wp_deregister
    cmp rax, 1
    jne .dbg_phys_wp_fail_deregister

    mov rdi, 0x30000000
    call virt_unmap
    mov rdi, 0x40000000
    call virt_unmap

    mov rdi, [dbg_phys_wp_phys_page]
    call phys_free_page

    mov rdi, [dbg_phys_wp_vma1_ptr]
    call vma_destroy
    mov rdi, [dbg_phys_wp_vma2_ptr]
    call vma_destroy

    ; Success!
    mov rsi, msg_dbg_phys_wp_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .overcommit_test_start

    ; =========================================================================
    ; Overcommit Policy Engine Test
    ; =========================================================================
.overcommit_test_start:
    mov rsi, msg_overcommit_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; Let's get total physical pages from phys_state
    mov rax, [phys_state + phys_state_t.total_pages]
    mov r12, rax                    ; R12 = total_pages

    ; 1. Test OVERCOMMIT_ALWAYS (1)
    mov qword [overcommit_mode], 1
    
    ; Allocate a huge VMA: total_pages * 10 * 4096 bytes
    mov rdi, 0x1000000000           ; some high virtual address
    mov rsi, r12
    imul rsi, 10
    shl rsi, 12                     ; size in bytes = total_pages * 10 * 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .overcommit_fail_always
    
    ; Success. Destroy it.
    mov rdi, rax
    call vma_destroy

    ; 2. Test OVERCOMMIT_NEVER (0)
    mov qword [overcommit_mode], 0
    
    ; Allocate VMA of size total_pages - 10 pages (should succeed)
    mov rdi, 0x1000000000
    mov rsi, r12
    sub rsi, 10
    shl rsi, 12                     ; (total_pages - 10) * 4096 bytes
    mov rdx, 0x83
    call vma_create
    test rax, rax
    jz .overcommit_fail_never_succeed
    mov r13, rax                    ; R13 = VMA pointer

    ; Try allocating another 20 pages (should fail since it exceeds total physical pages)
    mov rdi, 0x2000000000
    mov rsi, 20
    shl rsi, 12
    mov rdx, 0x83
    call vma_create
    test rax, rax
    jnz .overcommit_fail_never_fail

    ; Destroy the first VMA
    mov rdi, r13
    call vma_destroy
    xor r13, r13

    ; 3. Test OVERCOMMIT_HEURISTIC (2)
    mov qword [overcommit_mode], 2
    mov qword [overcommit_ratio], 150 ; 150% of physical RAM
    
    ; Allowance is 1.5 * total_pages = (total_pages * 150) / 100
    ; Let's allocate VMA of size total_pages * 120 / 100 (1.2x physical RAM, should succeed)
    mov rax, r12
    imul rax, 120
    mov rcx, 100
    xor rdx, rdx
    div rcx                         ; RAX = total_pages * 1.2
    
    mov rdi, 0x1000000000
    mov rsi, rax
    shl rsi, 12                     ; size in bytes
    mov rdx, 0x83
    call vma_create
    test rax, rax
    jz .overcommit_fail_heuristic_succeed
    mov r13, rax

    ; Try allocating VMA of size total_pages * 180 / 100 (1.8x physical RAM, should fail)
    mov rax, r12
    imul rax, 5
    mov rdi, 0x3000000000
    mov rsi, rax
    shl rsi, 12
    mov rdx, 0x83
    call vma_create
    test rax, rax
    jnz .overcommit_fail_heuristic_fail

    ; Clean up
    mov rdi, r13
    call vma_destroy

    ; Restore default mode to HEURISTIC (2)
    mov qword [overcommit_mode], 2

    pop r14
    pop r13
    pop r12

    ; Success!
    mov rsi, msg_overcommit_test_passed
    call uart_print_str

    jmp .oom_score_test_start

.overcommit_fail_always:
    mov rsi, msg_overcommit_fail_always_str
    call uart_print_str
    jmp .panic_overcommit

.overcommit_fail_never_succeed:
    mov rsi, msg_overcommit_fail_never_succeed_str
    call uart_print_str
    jmp .panic_overcommit

.overcommit_fail_never_fail:
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_overcommit_fail_never_fail_str
    call uart_print_str
    jmp .panic_overcommit

.overcommit_fail_heuristic_succeed:
    mov rsi, msg_overcommit_fail_heuristic_succeed_str
    call uart_print_str
    jmp .panic_overcommit

.overcommit_fail_heuristic_fail:
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_overcommit_fail_heuristic_fail_str
    call uart_print_str
    jmp .panic_overcommit

.panic_overcommit:
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; OOM Score Calculator Test
    ; =========================================================================
.oom_score_test_start:
    mov rsi, msg_oom_score_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; Register Thread A
    mov rdi, 200
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_score_fail_register
    
    ; Calculate Thread A address inside thread_table
    imul rax, thread_t_size
    lea r12, [thread_table + rax]   ; R12 = Thread A pointer
    
    ; Set Thread A attributes
    mov qword [r12 + thread_t.mem_usage], 100
    mov qword [r12 + thread_t.time_alive], 10
    mov qword [r12 + thread_t.priority_weight], 5

    ; Register Thread B
    mov rdi, 201
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_score_fail_register
    
    ; Calculate Thread B address inside thread_table
    imul rax, thread_t_size
    lea r13, [thread_table + rax]   ; R13 = Thread B pointer
    
    ; Set Thread B attributes
    mov qword [r13 + thread_t.mem_usage], 50
    mov qword [r13 + thread_t.time_alive], 4
    mov qword [r13 + thread_t.priority_weight], 2

    ; 1. Calculate OOM Score for Thread A: should be 100 * 10 * 5 = 5000
    mov rdi, r12
    call virt_oom_calculate_score
    cmp rax, 5000
    jne .oom_score_fail_calc_a

    ; 2. Calculate OOM Score for Thread B: should be 50 * 4 * 2 = 400
    mov rdi, r13
    call virt_oom_calculate_score
    cmp rax, 400
    jne .oom_score_fail_calc_b

    ; 3. Select Victim: lowest score should be Thread B (400 < 5000)
    call virt_oom_select_victim     ; RAX = selected victim pointer
    cmp rax, r13
    jne .oom_score_fail_select_b

    ; 4. Increase Thread B's priority weight to 50
    ; Score B = 50 * 4 * 50 = 10000
    mov qword [r13 + thread_t.priority_weight], 50

    ; 5. Select Victim: lowest score should now be Thread A (5000 < 10000)
    call virt_oom_select_victim
    cmp rax, r12
    jne .oom_score_fail_select_a

    ; Deactivate the mock threads so they do not interfere with scheduling
    mov qword [r12 + thread_t.flags], 0
    mov qword [r13 + thread_t.flags], 0

    pop r14
    pop r13
    pop r12

    ; OOM Score Calculator Test Passed!
    mov rsi, msg_oom_score_test_passed
    call uart_print_str

    jmp .oom_killer_test_start

.oom_score_fail_register:
    mov rsi, msg_oom_score_fail_register_str
    call uart_print_str
    jmp .panic_oom_score

.oom_score_fail_calc_a:
    mov rsi, msg_oom_score_fail_calc_a_str
    call uart_print_str
    jmp .panic_oom_score

.oom_score_fail_calc_b:
    mov rsi, msg_oom_score_fail_calc_b_str
    call uart_print_str
    jmp .panic_oom_score

.oom_score_fail_select_b:
    mov rsi, msg_oom_score_fail_select_b_str
    call uart_print_str
    jmp .panic_oom_score

.oom_score_fail_select_a:
    mov rsi, msg_oom_score_fail_select_a_str
    call uart_print_str
    jmp .panic_oom_score

.panic_oom_score:
    ; Clean up flags before panic
    test r12, r12
    jz .skip_a
    mov qword [r12 + thread_t.flags], 0
.skip_a:
    test r13, r13
    jz .skip_b
    mov qword [r13 + thread_t.flags], 0
.skip_b:
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; OOM Killer Test
    ; =========================================================================
.oom_killer_test_start:
    mov rsi, msg_oom_killer_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; 1. Switch overcommit to strict mode (0)
    mov qword [overcommit_mode], 0

    ; 2. Register Thread V (Victim to be killed first)
    mov rdi, 300
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_kill_fail_register
    
    ; Get Thread V pointer
    imul rax, thread_t_size
    lea r12, [thread_table + rax]   ; R12 = Thread V pointer

    ; Set Thread V parameters
    mov qword [r12 + thread_t.mem_usage], 100
    mov qword [r12 + thread_t.time_alive], 2
    mov qword [r12 + thread_t.priority_weight], 1

    ; 3. Setup system reservations
    mov rax, [phys_state + phys_state_t.total_pages]
    mov r13, rax                    ; R13 = total_pages
    
    mov rax, r13
    sub rax, 50
    mov [virt_reserved_pages], rax  ; reserved = total_pages - 50

    ; 4. Try creating a VMA of size 80 pages
    mov rdi, 0x1000000000
    mov rsi, 80
    shl rsi, 12                     ; size in bytes
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .oom_kill_fail_alloc
    mov r14, rax                    ; R14 = VMA pointer

    ; 5. Verify Thread V is terminated
    mov rax, [r12 + thread_t.flags]
    test rax, 1
    jnz .oom_kill_fail_not_terminated

    ; Clean up
    mov rdi, r14
    call vma_destroy
    
    ; Restore overcommit default mode and settings
    mov qword [overcommit_mode], 2  ; heuristic
    mov qword [virt_reserved_pages], 0

    pop r14
    pop r13
    pop r12

    ; Success!
    mov rsi, msg_oom_killer_test_passed
    call uart_print_str

    jmp .oom_notifier_test_start

.oom_kill_fail_register:
    mov rsi, msg_oom_kill_fail_register_str
    call uart_print_str
    jmp .panic_oom_kill

.oom_kill_fail_alloc:
    mov rsi, msg_oom_kill_fail_alloc_str
    call uart_print_str
    jmp .panic_oom_kill

.oom_kill_fail_not_terminated:
    mov rdi, r14
    call vma_destroy
    mov rsi, msg_oom_kill_fail_not_terminated_str
    call uart_print_str
    jmp .panic_oom_kill

.panic_oom_kill:
    ; Clean up thread flags and reservations before panic
    test r12, r12
    jz .skip_v
    mov qword [r12 + thread_t.flags], 0
.skip_v:
    mov qword [overcommit_mode], 2  ; restore heuristic
    mov qword [virt_reserved_pages], 0
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; OOM Notifier Test
    ; =========================================================================
.oom_notifier_test_start:
    mov rsi, msg_oom_notifier_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; Clear the callback verification flag
    mov qword [oom_callback_flag], 0

    ; 1. Switch overcommit to strict mode (0)
    mov qword [overcommit_mode], 0

    ; 2. Register Thread N (Victim with notifier callback)
    mov rdi, 400
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_notify_fail_register
    
    ; Get Thread N pointer
    imul rax, thread_t_size
    lea r12, [thread_table + rax]   ; R12 = Thread N pointer

    ; Set Thread N parameters (mem_usage = 100 pages, score = 200)
    mov qword [r12 + thread_t.mem_usage], 100
    mov qword [r12 + thread_t.time_alive], 2
    mov qword [r12 + thread_t.priority_weight], 1

    ; 3. Register OOM notifier callback for Thread N
    mov rdi, r12
    lea rsi, [oom_notifier_callback]
    call virt_oom_register_notifier

    ; 4. Setup system reservations
    mov rax, [phys_state + phys_state_t.total_pages]
    mov r13, rax                    ; R13 = total_pages
    
    mov rax, r13
    sub rax, 50
    mov [virt_reserved_pages], rax  ; reserved = total_pages - 50

    ; 5. Try creating a VMA of size 80 pages (triggers OOM -> calls callback -> kills Thread N)
    mov rdi, 0x1000000000
    mov rsi, 80
    shl rsi, 12                     ; size in bytes
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .oom_notify_fail_alloc
    mov r14, rax                    ; R14 = VMA pointer

    ; 6. Verify Thread N is terminated
    mov rax, [r12 + thread_t.flags]
    test rax, 1
    jnz .oom_notify_fail_not_terminated

    ; 7. Verify that the OOM notifier callback was executed (oom_callback_flag == 1)
    mov rax, [oom_callback_flag]
    cmp rax, 1
    jne .oom_notify_fail_callback_not_run

    ; Clean up VMA
    mov rdi, r14
    call vma_destroy
    
    ; Restore overcommit default mode and settings
    mov qword [overcommit_mode], 2  ; heuristic
    mov qword [virt_reserved_pages], 0

    pop r14
    pop r13
    pop r12

    ; Success!
    mov rsi, msg_oom_notifier_test_passed
    call uart_print_str

    jmp .oom_cgroup_test_start

    ; =========================================================================
    ; Memory Cgroup Limits Test
    ; =========================================================================
.oom_cgroup_test_start:
    mov rsi, msg_oom_cgroup_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Create Memory Cgroup 500
    mov rdi, 500                    ; ID
    mov rsi, 150                    ; Hard Limit (pages)
    mov rdx, 100                    ; Soft Limit (pages)
    call virt_memcg_create
    test rax, rax
    jz .oom_cgroup_fail_create
    mov r12, rax                    ; R12 = cgroup pointer

    ; 2. Register Thread A (ID = 501)
    mov rdi, 501
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_cgroup_fail_register
    imul rax, thread_t_size
    lea r13, [thread_table + rax]   ; R13 = Thread A pointer

    ; Set Thread A attributes
    mov qword [r13 + thread_t.mem_usage], 100
    mov qword [r13 + thread_t.time_alive], 2
    mov qword [r13 + thread_t.priority_weight], 2

    ; Attach Thread A to cgroup
    mov rdi, r13
    mov rsi, r12
    call virt_memcg_attach

    ; 3. Register Thread B (ID = 502) (victim)
    mov rdi, 502
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_cgroup_fail_register
    imul rax, thread_t_size
    lea r14, [thread_table + rax]   ; R14 = Thread B pointer

    ; Set Thread B attributes
    mov qword [r14 + thread_t.mem_usage], 20
    mov qword [r14 + thread_t.time_alive], 5
    mov qword [r14 + thread_t.priority_weight], 1

    ; Attach Thread B to cgroup
    mov rdi, r14
    mov rsi, r12
    call virt_memcg_attach

    ; 4. Attach current thread (Thread 100, index 0) to cgroup
    lea rdi, [thread_table]
    mov rsi, r12
    call virt_memcg_attach

    ; Setup thread 100 attributes so it doesn't get killed
    lea rdi, [thread_table]
    mov qword [rdi + thread_t.mem_usage], 10
    mov qword [rdi + thread_t.time_alive], 1000
    mov qword [rdi + thread_t.priority_weight], 1000

    ; Set initial cgroup usage to 10 + 100 + 20 = 130 pages
    mov qword [r12 + mem_cgroup_t.usage], 130

    ; 5. Test Soft Limit Reclaim (Usage 130 + 10 = 140 pages, exceeds soft limit 100 but <= hard limit 150)
    ; This should trigger kswapd reclaim, print warning, but succeed.
    mov rdi, 0x1000000000
    mov rsi, 10
    shl rsi, 12                     ; 10 pages in bytes
    mov rdx, 0x83                   ; VMA flags
    call vma_create
    test rax, rax
    jz .oom_cgroup_fail_soft_alloc
    mov r15, rax                    ; R15 = first VMA pointer

    ; Verify usage was charged (130 + 10 = 140 pages)
    mov rax, [r12 + mem_cgroup_t.usage]
    cmp rax, 140
    jne .oom_cgroup_fail_soft_charge

    ; 6. Test Hard Limit localized OOM (Usage 140 + 30 = 170 pages, exceeds hard limit 150)
    ; This must run cgroup OOM killer, target and kill Thread B (lowest score 100),
    ; reclaim its 20 pages (usage drops to 120), then succeed and allocate VMA.
    mov rdi, 0x2000000000
    mov rsi, 30
    shl rsi, 12                     ; 30 pages in bytes
    mov rdx, 0x83                   ; VMA flags
    call vma_create
    test rax, rax
    jz .oom_cgroup_fail_hard_alloc
    mov r13, rax                    ; R13 = second VMA pointer

    ; Verify Thread B is terminated
    mov rax, [r14 + thread_t.flags]
    test rax, 1
    jnz .oom_cgroup_fail_not_killed

    ; Verify Thread A is NOT terminated
    mov rax, 4
    imul rax, thread_t_size
    lea rax, [thread_table + rax]
    mov rcx, [rax + thread_t.flags]
    test rcx, 1
    jz .oom_cgroup_fail_killed_wrong

    ; Verify final cgroup usage is (140 - 20) + 30 = 150 pages
    mov rax, [r12 + mem_cgroup_t.usage]
    cmp rax, 150
    jne .oom_cgroup_fail_final_charge

    ; 7. Clean up
    ; Destroy VMAs
    mov rdi, r15
    call vma_destroy
    mov rdi, r13                    ; second VMA
    call vma_destroy

    ; Detach current thread
    lea rdi, [thread_table]
    mov rsi, 0
    call virt_memcg_attach

    ; Destroy cgroup
    mov rdi, r12
    call virt_memcg_destroy

    ; Deactivate Thread A
    mov rax, 4
    imul rax, thread_t_size
    lea rax, [thread_table + rax]
    mov qword [rax + thread_t.flags], 0

    ; Reset thread count to 4 (Thread 100, 101, 102, and 400 from notifier test)
    mov qword [thread_count], 4

    pop r15
    pop r14
    pop r13
    pop r12

    ; Success!
    mov rsi, msg_oom_cgroup_test_passed
    call uart_print_str

    jmp .oom_retry_test_start

    ; =========================================================================
    ; Allocation Retry with Reclaim Test
    ; =========================================================================
.oom_retry_test_start:
    mov rsi, msg_oom_retry_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; 1. Switch overcommit to strict mode (0)
    mov qword [overcommit_mode], 0

    ; 2. Register Thread V (ID = 601)
    mov rdi, 601
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_retry_fail_register
    imul rax, thread_t_size
    lea r12, [thread_table + rax]   ; R12 = Thread V pointer

    ; Set Thread V attributes
    mov qword [r12 + thread_t.mem_usage], 50
    mov qword [r12 + thread_t.time_alive], 2
    mov qword [r12 + thread_t.priority_weight], 1

    ; 3. Setup system reservations
    mov rax, [phys_state + phys_state_t.total_pages]
    mov r13, rax                    ; R13 = total_pages
    
    mov rax, r13
    sub rax, 30
    mov [virt_reserved_pages], rax  ; reserved = total_pages - 30

    ; Enable mock retry trigger: set virt_alloc_retry_mock = 1
    mov qword [virt_alloc_retry_mock], 1

    ; 4. Try allocating VMA of size 50 pages (triggers reclaim -> mock subtracts 50 pages -> succeeds)
    mov rdi, 0x1000000000
    mov rsi, 50
    shl rsi, 12                     ; 50 pages
    mov rdx, 0x83                   ; VMA flags
    call vma_create
    test rax, rax
    jz .oom_retry_fail_alloc
    mov r14, rax                    ; R14 = VMA pointer

    ; Reset mock trigger
    mov qword [virt_alloc_retry_mock], 0

    ; 5. Verify Thread V is still active
    mov rax, [r12 + thread_t.flags]
    test rax, 1
    jz .oom_retry_fail_killed

    ; 6. Clean up
    mov rdi, r14
    call vma_destroy

    ; Restore overcommit defaults
    mov qword [overcommit_mode], 2  ; heuristic
    mov qword [virt_reserved_pages], 0

    ; Deactivate Thread V
    mov qword [r12 + thread_t.flags], 0
    mov qword [thread_count], 4     ; restore thread_count

    pop r14
    pop r13
    pop r12

    jmp .oom_psi_test_start

    ; =========================================================================
    ; Pressure Stall Information (PSI) Test
    ; =========================================================================
.oom_psi_test_start:
    mov rsi, msg_oom_psi_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; --- PART A: System-Wide PSI test ---
    ; 1. Get current thread (Thread 100, index 0)
    call sched_get_current_thread
    test rax, rax
    jz .oom_psi_fail_init
    mov r12, rax                    ; R12 = current thread pointer

    ; 2. Verify initial sys PSI values (should be 0 or small)
    call virt_psi_get_sys_metrics   ; RAX = some, RDX = full
    mov r13, rax                    ; R13 = initial sys some
    mov r14, rdx                    ; R14 = initial sys full

    ; 3. Stall current thread on memory
    mov rdi, r12
    mov rsi, 1                      ; stalled
    call virt_psi_update_thread_state

    ; 4. Spin to accumulate cycle delta
    mov rcx, 100000
.spin_sys:
    dec rcx
    jnz .spin_sys

    ; 5. Unstall current thread
    mov rdi, r12
    mov rsi, 0                      ; unstalled
    call virt_psi_update_thread_state

    ; 6. Query sys PSI metrics and verify they increased
    call virt_psi_get_sys_metrics
    cmp rax, r13
    jbe .oom_psi_fail_sys_some
    cmp rdx, r14
    jbe .oom_psi_fail_sys_full

    ; --- PART B: Per-Cgroup PSI test ---
    ; 1. Create cgroup 600
    mov rdi, 600                    ; ID
    mov rsi, 150                    ; hard limit
    mov rdx, 100                    ; soft limit
    call virt_memcg_create
    test rax, rax
    jz .oom_psi_fail_cgroup_create
    mov r15, rax                    ; R15 = cgroup pointer

    ; 2. Register Thread A (ID = 650)
    mov rdi, 650
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_psi_fail_register
    imul rax, thread_t_size
    lea r13, [thread_table + rax]   ; R13 = Thread A pointer

    ; Set active & attach Thread A
    mov qword [r13 + thread_t.mem_usage], 10
    mov qword [r13 + thread_t.time_alive], 2
    mov qword [r13 + thread_t.priority_weight], 1
    mov rdi, r13
    mov rsi, r15
    call virt_memcg_attach

    ; 3. Register Thread B (ID = 651)
    mov rdi, 651
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread
    cmp rax, -1
    je .oom_psi_fail_register
    imul rax, thread_t_size
    lea r14, [thread_table + rax]   ; R14 = Thread B pointer

    ; Set active & attach Thread B
    mov qword [r14 + thread_t.mem_usage], 10
    mov qword [r14 + thread_t.time_alive], 2
    mov qword [r14 + thread_t.priority_weight], 1
    mov rdi, r14
    mov rsi, r15
    call virt_memcg_attach

    ; 4. Stall Thread A (now 1 out of 2 active threads in cgroup 600 is stalled -> SOME pressure)
    mov rdi, r13
    mov rsi, 1                      ; stalled
    call virt_psi_update_thread_state

    ; Spin
    mov rcx, 100000
.spin_cg_some:
    dec rcx
    jnz .spin_cg_some

    ; Query and verify SOME > 0 and FULL == 0
    mov rdi, r15
    call virt_psi_get_cgroup_metrics ; RAX = some, RDX = full
    test rax, rax
    jz .oom_psi_fail_cg_some_zero
    test rdx, rdx
    jnz .oom_psi_fail_cg_full_nonzero

    ; Save current SOME total
    mov r12, rax

    ; 5. Stall Thread B (now both active threads in cgroup are stalled -> FULL pressure)
    mov rdi, r14
    mov rsi, 1                      ; stalled
    call virt_psi_update_thread_state

    ; Spin
    mov rcx, 100000
.spin_cg_full:
    dec rcx
    jnz .spin_cg_full

    ; Query and verify SOME increased, and FULL > 0
    mov rdi, r15
    call virt_psi_get_cgroup_metrics ; RAX = some, RDX = full
    cmp rax, r12
    jbe .oom_psi_fail_cg_some_noinc
    test rdx, rdx
    jz .oom_psi_fail_cg_full_zero

    ; 6. Unstall both threads
    mov rdi, r13
    mov rsi, 0
    call virt_psi_update_thread_state
    mov rdi, r14
    mov rsi, 0
    call virt_psi_update_thread_state

    ; 7. Clean up
    ; Detach threads from cgroup
    mov rdi, r13
    mov rsi, 0
    call virt_memcg_attach
    mov rdi, r14
    mov rsi, 0
    call virt_memcg_attach

    ; Deactivate Thread A and B
    mov qword [r13 + thread_t.flags], 0
    mov qword [r14 + thread_t.flags], 0

    ; Destroy cgroup
    mov rdi, r15
    call virt_memcg_destroy

    ; Reset thread count
    mov qword [thread_count], 4

    pop r15
    pop r14
    pop r13
    pop r12

    ; Success!
    mov rsi, msg_oom_psi_test_passed
    call uart_print_str

    jmp .watermark_test_start

    ; =========================================================================
    ; Memory Watermarks Test
    ; =========================================================================
.watermark_test_start:
    mov rsi, msg_watermark_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; Ensure NUMA local bitmaps are active
    mov rax, [numa_local_bitmaps_active]
    test rax, rax
    jnz .numa_already_active
    call numa_init_local_bitmaps
.numa_already_active:

    ; 1. Configure watermarks for Node 0
    mov rdi, 0                      ; Node 0
    mov rsi, 10                     ; min = 10 pages
    mov rdx, 20                     ; low = 20 pages
    mov rcx, 30                     ; high = 30 pages
    call numa_set_watermarks
    cmp rax, 1
    jne .watermark_fail_config

    ; Verify watermarks are set correctly
    mov rax, 0
    imul rax, numa_node_t_size
    lea r12, [numa_nodes + rax]     ; R12 = Node 0 descriptor
    cmp qword [r12 + numa_node_t.pages_min], 10
    jne .watermark_fail_val
    cmp qword [r12 + numa_node_t.pages_low], 20
    jne .watermark_fail_val
    cmp qword [r12 + numa_node_t.pages_high], 30
    jne .watermark_fail_val

    ; 2. Setup mock swap device & inactive page candidate for Node 0 clock eviction
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .watermark_fail_alloc_setup
    mov r13, rax                    ; R13 = physical page address

    ; Map it at 0x20000000
    mov rdi, 0x20000000
    mov rsi, r13
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .watermark_fail_map_setup

    ; Move to inactive list & clear Accessed bit to make it evictable
    mov rdi, r13
    call page_list_move_to_inactive
    
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .watermark_fail_walk_setup
    and qword [rax], ~0x20          ; clear Accessed

    ; 3. Test kswapd wakeup (background reclaim)
    ; Set free_pages to 15 (below low watermark 20, above min watermark 10)
    mov qword [r12 + numa_node_t.free_pages], 15

    ; Trigger page allocation (requires 1 page). This should drop it to 14, 
    ; triggering kswapd background reclaim sweep on Node 0 which evicts 0x20000000.
    mov rdi, 0                      ; Node 0
    mov rsi, 1                      ; 1 page
    call phys_alloc_pages_node
    test rax, rax
    jz .watermark_fail_kswapd_alloc
    mov r14, rax                    ; R14 = allocated page

    ; Verify that the inactive page at 0x20000000 was successfully evicted!
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .watermark_fail_pte
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .watermark_fail_present     ; must NOT be present
    test rcx, 0x400                 ; swapped?
    jz .watermark_fail_swapped

    ; Free the page allocated for kswapd trigger
    mov rdi, r14
    call phys_free_page

    ; 4. Test direct reclaim
    ; Set up another page for clock eviction
    call phys_alloc_page
    test rax, rax
    jz .watermark_fail_alloc_setup
    mov r13, rax

    mov rdi, 0x30000000
    mov rsi, r13
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .watermark_fail_map_setup

    mov rdi, r13
    call page_list_move_to_inactive
    
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    and qword [rax], ~0x20          ; clear Accessed

    ; Set Node 0 free pages to 5 (below min watermark 10)
    mov qword [r12 + numa_node_t.free_pages], 5
    ; Trigger allocation of 1 page. This should drop it to 4 (below min 10),
    ; triggering direct reclaim, which evicts 0x30000000.
    mov rdi, 0                      ; Node 0
    mov rsi, 1                      ; 1 page
    call phys_alloc_pages_node
    test rax, rax
    jz .watermark_fail_direct_alloc
    mov r14, rax

    ; Verify page at 0x30000000 was evicted
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    mov rcx, [rax]
    test rcx, 1
    jnz .watermark_fail_present
    test rcx, 0x400
    jz .watermark_fail_swapped

    ; Free allocated page
    mov rdi, r14
    call phys_free_page

    ; 5. Test allocation rejection
    ; Set Node 0 free pages to 5 (below min 10) and ensure replacement list is empty
    ; so direct reclaim fails to free anything.
    mov qword [r12 + numa_node_t.free_pages], 5
    
    ; Allocate page should fail (return 0)
    mov rdi, 0                      ; Node 0
    mov rsi, 1
    call phys_alloc_pages_node
    test rax, rax
    jnz .watermark_fail_reject      ; should have been rejected!

    ; 6. Clean up
    ; Reset Node 0 watermarks back to default
    mov rdi, 0
    mov rsi, 128
    mov rdx, 256
    mov rcx, 512
    call numa_set_watermarks

    ; Restore actual free page count from global bitmap recount
    mov rsi, [r12 + numa_node_t.bitmap_addr]
    mov rax, [r12 + numa_node_t.end_page]
    sub rax, [r12 + numa_node_t.start_page]
    mov rcx, rax
    xor r8, r8
    xor r9, r9
.recount:
    cmp r9, rcx
    jae .recount_done
    mov rax, r9
    shr rax, 3
    mov rbx, r9
    and rbx, 7
    bt [rsi + rax], rbx
    jc .recount_next
    inc r8
.recount_next:
    inc r9
    jmp .recount
.recount_done:
    mov [r12 + numa_node_t.free_pages], r8

    ; Unmap test VMAs if any
    mov rdi, 0x20000000
    call virt_unmap
    mov rdi, 0x30000000
    call virt_unmap

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_watermark_test_passed
    call uart_print_str

    jmp .proactive_reclaim_test_start

.watermark_fail_config:
    mov rsi, msg_watermark_fail_config_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_val:
    mov rsi, msg_watermark_fail_val_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_alloc_setup:
    mov rsi, msg_watermark_fail_alloc_setup_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_map_setup:
    mov rsi, msg_watermark_fail_map_setup_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_walk_setup:
    mov rsi, msg_watermark_fail_walk_setup_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_kswapd_alloc:
    mov rsi, msg_watermark_fail_kswapd_alloc_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_pte:
    mov rsi, msg_watermark_fail_pte_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_present:
    mov rsi, msg_watermark_fail_present_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_swapped:
    mov rsi, msg_watermark_fail_swapped_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_direct_alloc:
    mov rsi, msg_watermark_fail_direct_alloc_str
    call uart_print_str
    jmp .panic_watermark

.watermark_fail_reject:
    mov rsi, msg_watermark_fail_reject_str
    call uart_print_str
    jmp .panic_watermark

.panic_watermark:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.proactive_reclaim_test_start:
    mov rsi, msg_proactive_reclaim_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; Register mock swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Allocate physical page 1
    call phys_alloc_page
    test rax, rax
    jz .proactive_fail_alloc_setup
    mov r13, rax                    ; R13 = physical page 1 address

    ; Map page 1 at 0x20000000
    mov rdi, 0x20000000
    mov rsi, r13
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .proactive_fail_map_setup

    ; Move page 1 to inactive list & clear Accessed bit
    mov rdi, r13
    call page_list_move_to_inactive

    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .proactive_fail_walk_setup
    and qword [rax], ~0x20          ; clear Accessed

    ; Allocate physical page 2
    call phys_alloc_page
    test rax, rax
    jz .proactive_fail_alloc_setup
    mov r14, rax                    ; R14 = physical page 2 address

    ; Map page 2 at 0x30000000
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .proactive_fail_map_setup

    ; Move page 2 to inactive list & clear Accessed bit
    mov rdi, r14
    call page_list_move_to_inactive

    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .proactive_fail_walk_setup
    and qword [rax], ~0x20          ; clear Accessed

    ; Test virt_proactive_reclaim(1)
    mov rdi, 1                      ; target_pages = 1
    call virt_proactive_reclaim
    cmp rax, 1                      ; should return actual page count reclaimed (1)
    jne .proactive_fail_direct_reclaim

    ; Verify that page 1 (0x20000000) was successfully evicted!
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .proactive_fail_pte
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .proactive_fail_present     ; must NOT be present
    test rcx, 0x400                 ; swapped?
    jz .proactive_fail_swapped

    ; Test virt_proactive_reclaim_node(0, 1)
    mov rdi, 0                      ; node_id = 0
    mov rsi, 1                      ; target_pages = 1
    call virt_proactive_reclaim_node
    cmp rax, 1                      ; should return 1 page reclaimed
    jne .proactive_fail_direct_reclaim_node

    ; Verify that page 2 (0x30000000) was successfully evicted!
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .proactive_fail_pte
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .proactive_fail_present     ; must NOT be present
    test rcx, 0x400                 ; swapped?
    jz .proactive_fail_swapped

    ; Clean up virt mappings for first 2 test pages
    mov rdi, 0x20000000
    call virt_unmap
    mov rdi, 0x30000000
    call virt_unmap

    ; Test allocator check for proactive reclaim
    ; Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .proactive_fail_alloc_setup
    mov r13, rax                    ; R13 = physical page address

    ; Map it at 0x40000000
    mov rdi, 0x40000000
    mov rsi, r13
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .proactive_fail_map_setup

    ; Move to inactive list & clear Accessed bit
    mov rdi, r13
    call page_list_move_to_inactive
    
    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .proactive_fail_walk_setup
    and qword [rax], ~0x20          ; clear Accessed

    ; Configure watermarks: Node 0 watermarks: min = 5, low = 10, high = 20
    mov rdi, 0                      ; Node 0
    mov rsi, 5
    mov rdx, 10
    mov rcx, 20
    call numa_set_watermarks
    cmp rax, 1
    jne .proactive_fail_config

    ; Set Node 0 proactive headroom to 15 pages
    mov rdi, 0                      ; Node 0
    mov rsi, 15                     ; headroom = 15 pages
    call numa_set_proactive_headroom
    cmp rax, 1
    jne .proactive_fail_config

    ; Get Node 0 descriptor
    mov rax, 0
    imul rax, numa_node_t_size
    lea r12, [numa_nodes + rax]     ; R12 = Node 0 descriptor

    ; Set free_pages to 14 (below proactive headroom 15, above pages_low 10)
    mov qword [r12 + numa_node_t.free_pages], 14

    ; Trigger page allocation (requires 1 page). Drops free pages to 13,
    ; breaching proactive headroom (13 < 15), triggers background proactive reclaim,
    ; which evicts page at 0x40000000.
    mov rdi, 0                      ; Node 0
    mov rsi, 1                      ; 1 page
    call phys_alloc_pages_node
    test rax, rax
    jz .proactive_fail_kswapd_alloc
    mov r15, rax                    ; R15 = allocated page

    ; Verify that the inactive page at 0x40000000 was successfully evicted!
    mov rdi, 0x40000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .proactive_fail_pte
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .proactive_fail_present     ; must NOT be present
    test rcx, 0x400                 ; swapped?
    jz .proactive_fail_swapped

    ; Free the page allocated for proactive trigger
    mov rdi, r15
    call phys_free_page

    ; Clean up virt mapping
    mov rdi, 0x40000000
    call virt_unmap

    ; Reset Node 0 watermarks and proactive headroom back to default
    mov rdi, 0
    mov rsi, 128
    mov rdx, 256
    mov rcx, 512
    call numa_set_watermarks

    mov rdi, 0
    mov rsi, 0                      ; clear proactive headroom
    call numa_set_proactive_headroom

    ; Restore actual free page count from global bitmap recount
    mov rsi, [r12 + numa_node_t.bitmap_addr]
    mov rax, [r12 + numa_node_t.end_page]
    sub rax, [r12 + numa_node_t.start_page]
    mov rcx, rax
    xor r8, r8
    xor r9, r9
.proactive_recount:
    cmp r9, rcx
    jae .proactive_recount_done
    mov rax, r9
    shr rax, 3
    mov rbx, r9
    and rbx, 7
    bt [rsi + rax], rbx
    jc .proactive_recount_next
    inc r8
.proactive_recount_next:
    inc r9
    jmp .proactive_recount
.proactive_recount_done:
    mov [r12 + numa_node_t.free_pages], r8

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_proactive_reclaim_test_passed
    call uart_print_str

    jmp .balloon_test_start

.proactive_fail_config:
    mov rsi, msg_proactive_fail_config_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_alloc_setup:
    mov rsi, msg_proactive_fail_alloc_setup_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_map_setup:
    mov rsi, msg_proactive_fail_map_setup_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_walk_setup:
    mov rsi, msg_proactive_fail_walk_setup_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_direct_reclaim:
    mov rsi, msg_proactive_fail_direct_reclaim_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_direct_reclaim_node:
    mov rsi, msg_proactive_fail_direct_reclaim_node_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_kswapd_alloc:
    mov rsi, msg_proactive_fail_kswapd_alloc_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_pte:
    mov rsi, msg_proactive_fail_pte_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_present:
    mov rsi, msg_proactive_fail_present_str
    call uart_print_str
    jmp .panic_proactive

.proactive_fail_swapped:
    mov rsi, msg_proactive_fail_swapped_str
    call uart_print_str
    jmp .panic_proactive

.panic_proactive:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.balloon_test_start:
    mov rsi, msg_balloon_test_start
    call uart_print_str

    ; Assert initial telemetry is zero
    mov rax, [sys_balloon_target_pages]
    test rax, rax
    jnz .balloon_fail_init

    mov rax, [sys_balloon_current_pages]
    test rax, rax
    jnz .balloon_fail_init

    ; Set target to 4 pages (forces inflation of 4 pages)
    mov rdi, 4
    call virt_balloon_set_target

    ; Assert target is 4
    mov rax, [sys_balloon_target_pages]
    cmp rax, 4
    jne .balloon_fail_inflate

    ; Assert current is 4
    mov rax, [sys_balloon_current_pages]
    cmp rax, 4
    jne .balloon_fail_inflate

    ; Set target to 2 pages (forces deflation of 2 pages)
    mov rdi, 2
    call virt_balloon_set_target

    ; Assert target is 2
    mov rax, [sys_balloon_target_pages]
    cmp rax, 2
    jne .balloon_fail_deflate

    ; Assert current is 2
    mov rax, [sys_balloon_current_pages]
    cmp rax, 2
    jne .balloon_fail_deflate

    ; Set target to 0 pages (deflates remaining pages)
    mov rdi, 0
    call virt_balloon_set_target

    ; Assert target is 0
    mov rax, [sys_balloon_target_pages]
    test rax, rax
    jnz .balloon_fail_deflate_all

    ; Assert current is 0
    mov rax, [sys_balloon_current_pages]
    test rax, rax
    jnz .balloon_fail_deflate_all

    mov rsi, msg_balloon_test_passed
    call uart_print_str

    jmp .throttling_test_start

.balloon_fail_init:
    mov rsi, msg_balloon_fail_init_str
    call uart_print_str
    jmp .panic

.balloon_fail_inflate:
    mov rsi, msg_balloon_fail_inflate_str
    call uart_print_str
    jmp .panic

.balloon_fail_deflate:
    mov rsi, msg_balloon_fail_deflate_str
    call uart_print_str
    jmp .panic

.balloon_fail_deflate_all:
    mov rsi, msg_balloon_fail_deflate_all_str
    call uart_print_str
    jmp .panic

.throttling_test_start:
    mov rsi, msg_throttling_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Create cgroup
    ; ID = 50, hard_limit = 100, soft_limit = 50
    mov rdi, 50
    mov rsi, 100
    mov rdx, 50
    call virt_memcg_create
    test rax, rax
    jz .throttling_fail_create
    mov r12, rax                    ; R12 = cgroup pointer

    ; 2. Set high_limit to 5 pages
    mov rdi, r12
    mov rsi, 5
    call virt_memcg_set_high_limit

    ; 3. Attach current thread
    call sched_get_current_thread
    test rax, rax
    jz .throttling_fail_thread
    mov r13, rax                    ; R13 = thread pointer

    mov rdi, r13
    mov rsi, r12
    call virt_memcg_attach

    ; 4. Allocate VMA 1: 4 pages (16384 bytes) at 0x80000000.
    ; This should NOT trigger the throttle.
    mov rdi, 0x80000000
    mov rsi, 16384
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .throttling_fail_vma1
    mov r14, rax                    ; R14 = VMA 1 pointer

    ; 5. Allocate VMA 2: 2 pages (8192 bytes) at 0x80004000.
    ; Total usage becomes 6 pages, which exceeds high_limit of 5 pages.
    ; This MUST trigger the warning and throttling.
    mov rdi, 0x80004000
    mov rsi, 8192
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .throttling_fail_vma2
    mov r15, rax                    ; R15 = VMA 2 pointer

    ; 6. Clean up
    ; Detach thread
    mov rdi, r13
    mov rsi, 0
    call virt_memcg_attach

    ; Destroy VMAs
    mov rdi, r14
    call vma_destroy
    mov rdi, r15
    call vma_destroy

    ; Destroy cgroup
    mov rdi, r12
    call virt_memcg_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_throttling_test_passed
    call uart_print_str

    jmp .page_cache_test_start

.throttling_fail_create:
    mov rsi, msg_throttling_fail_create_str
    call uart_print_str
    jmp .panic_throttling

.throttling_fail_thread:
    mov rsi, msg_throttling_fail_thread_str
    call uart_print_str
    jmp .panic_throttling

.throttling_fail_vma1:
    mov rsi, msg_throttling_fail_vma1_str
    call uart_print_str
    jmp .panic_throttling

.throttling_fail_vma2:
    mov rsi, msg_throttling_fail_vma2_str
    call uart_print_str
    jmp .panic_throttling

.panic_throttling:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.page_cache_test_start:
    mov rsi, msg_page_cache_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; Initialize Page Cache
    call virt_page_cache_init

    ; Create a mock file: size = 8192 bytes (2 pages)
    mov rdi, 8192
    extern mock_file_create
    call mock_file_create
    test rax, rax
    jz .page_cache_fail_read        ; treat as read failure/alloc failure
    mov r12, rax                    ; R12 = file pointer

    ; Prepare temporary stack buffer for reading
    sub rsp, 16
    mov r13, rsp                    ; R13 = buffer pointer

    ; Test 1: Page Cache Miss (First Read)
    mov rdi, r12                    ; file_ptr
    mov rsi, 0                      ; offset
    mov rdx, r13                    ; dest_buf
    mov rcx, 16                     ; count = 16 bytes
    call virt_file_read
    cmp rax, 16
    jne .page_cache_fail_read

    ; Assert counters: hits = 0, misses = 1
    cmp qword [sys_page_cache_hits], 0
    jne .page_cache_fail_counters1
    cmp qword [sys_page_cache_misses], 1
    jne .page_cache_fail_counters1

    ; Test 2: Page Cache Hit (Second Read)
    mov rdi, r12
    mov rsi, 0
    mov rdx, r13
    mov rcx, 16
    call virt_file_read
    cmp rax, 16
    jne .page_cache_fail_read

    ; Assert counters: hits = 1, misses = 1
    cmp qword [sys_page_cache_hits], 1
    jne .page_cache_fail_counters2
    cmp qword [sys_page_cache_misses], 1
    jne .page_cache_fail_counters2

    ; Test 3: Write and Page Cache Miss (Offset 4096, page 2)
    mov qword [r13], 0xAA55AA55AA55AA55
    mov rdi, r12
    mov rsi, 4096
    mov rdx, r13
    mov rcx, 8
    call virt_file_write
    cmp rax, 8
    jne .page_cache_fail_write

    ; Assert counters: hits = 1, misses = 2 (page 2 lookup miss)
    cmp qword [sys_page_cache_hits], 1
    jne .page_cache_fail_counters3
    cmp qword [sys_page_cache_misses], 2
    jne .page_cache_fail_counters3

    ; Test 4: Write sync back to storage
    extern virt_page_cache_sync
    call virt_page_cache_sync

    ; Verify that the block page at index 1 is not null and has our data synced
    mov rax, [r12 + mock_file_t.blocks + 8]  ; block 1 (offset 4096)
    test rax, rax
    jz .page_cache_fail_sync
    cmp qword [rax], 0xAA55AA55AA55AA55
    jne .page_cache_fail_sync_data

    ; Clean up
    add rsp, 16
    mov rdi, r12
    extern mock_file_destroy
    call mock_file_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_page_cache_test_passed
    call uart_print_str

    jmp .readahead_test_start

.page_cache_fail_read:
    add rsp, 16
    mov rsi, msg_page_cache_fail_read_str
    call uart_print_str
    jmp .panic_page_cache

.page_cache_fail_counters1:
    add rsp, 16
    mov rsi, msg_page_cache_fail_counters1_str
    call uart_print_str
    jmp .panic_page_cache

.page_cache_fail_counters2:
    add rsp, 16
    mov rsi, msg_page_cache_fail_counters2_str
    call uart_print_str
    jmp .panic_page_cache

.page_cache_fail_write:
    add rsp, 16
    mov rsi, msg_page_cache_fail_write_str
    call uart_print_str
    jmp .panic_page_cache

.page_cache_fail_counters3:
    add rsp, 16
    mov rsi, msg_page_cache_fail_counters3_str
    call uart_print_str
    jmp .panic_page_cache

.page_cache_fail_sync:
    add rsp, 16
    mov rsi, msg_page_cache_fail_sync_str
    call uart_print_str
    jmp .panic_page_cache

.page_cache_fail_sync_data:
    add rsp, 16
    mov rsi, msg_page_cache_fail_sync_data_str
    call uart_print_str
    jmp .panic_page_cache

.panic_page_cache:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.readahead_test_start:
    mov rsi, msg_readahead_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; Initialize page cache (clears old contents and stats)
    call virt_page_cache_init

    ; Create mock file of size 16384 bytes (4 pages)
    mov rdi, 16384
    call mock_file_create
    test rax, rax
    jz .readahead_fail_create
    mov r12, rax                    ; r12 = mock file pointer

    ; Prepare temporary stack buffer for reading
    sub rsp, 16
    mov r13, rsp                    ; r13 = buffer pointer

    ; Set configurable readahead window size to 2 pages
    mov qword [sys_readahead_window_size], 2

    ; Reset prefetch counter
    mov qword [sys_readahead_prefetched_pages], 0

    ; Read 16 bytes at offset 0 (triggers page fault & readahead prefetching)
    mov rdi, r12
    mov rsi, 0
    mov rdx, r13
    mov rcx, 16
    call virt_file_read
    cmp rax, 16
    jne .readahead_fail_read

    ; Assert that exactly 2 pages (at offsets 4096 and 8192) were prefetched
    cmp qword [sys_readahead_prefetched_pages], 2
    jne .readahead_fail_prefetched

    ; Reset page cache statistics to verify sequential read hits
    mov qword [sys_page_cache_hits], 0
    mov qword [sys_page_cache_misses], 0

    ; Read 16 bytes from offset 4096 (which should be in cache due to prefetch)
    mov rdi, r12
    mov rsi, 4096
    mov rdx, r13
    mov rcx, 16
    call virt_file_read
    cmp rax, 16
    jne .readahead_fail_read

    ; Assert hit count is 1 and miss count is 0
    cmp qword [sys_page_cache_hits], 1
    jne .readahead_fail_hits
    cmp qword [sys_page_cache_misses], 0
    jne .readahead_fail_misses

    ; Clean up mock file and stack
    add rsp, 16
    mov rdi, r12
    call mock_file_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_readahead_test_passed
    call uart_print_str

    jmp .writeback_test_start

.readahead_fail_create:
    mov rsi, msg_readahead_fail_create_str
    call uart_print_str
    jmp .panic_readahead

.readahead_fail_read:
    add rsp, 16
    mov rsi, msg_readahead_fail_read_str
    call uart_print_str
    jmp .panic_readahead

.readahead_fail_prefetched:
    add rsp, 16
    mov rsi, msg_readahead_fail_prefetched_str
    call uart_print_str
    jmp .panic_readahead

.readahead_fail_hits:
    add rsp, 16
    mov rsi, msg_readahead_fail_hits_str
    call uart_print_str
    jmp .panic_readahead

.readahead_fail_misses:
    add rsp, 16
    mov rsi, msg_readahead_fail_misses_str
    call uart_print_str
    jmp .panic_readahead

.panic_readahead:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.writeback_test_start:
    mov rsi, msg_writeback_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Initialize page cache (clears old contents and stats)
    call virt_page_cache_init

    ; 2. Configure writeback throttling parameters
    mov qword [sys_writeback_dirty_limit], 2
    mov qword [sys_writeback_throttle_delay], 1000      ; Fast delay for testing
    mov qword [sys_writeback_throttled_pages], 0

    ; 3. Create mock file of size 16384 bytes (4 pages)
    mov rdi, 16384
    call mock_file_create
    test rax, rax
    jz .writeback_fail_create
    mov r12, rax                    ; r12 = mock file pointer

    ; Prepare temporary stack buffer for writing
    sub rsp, 16
    mov r13, rsp                    ; r13 = buffer pointer
    mov qword [r13], 0x1122334455667788

    ; 4. Perform 3 writes to different offsets to create 3 dirty pages
    ; Write page 0 (offset 0)
    mov rdi, r12
    mov rsi, 0
    mov rdx, r13
    mov rcx, 8
    call virt_file_write
    cmp rax, 8
    jne .writeback_fail_write

    ; Write page 1 (offset 4096)
    mov rdi, r12
    mov rsi, 4096
    mov rdx, r13
    mov rcx, 8
    call virt_file_write
    cmp rax, 8
    jne .writeback_fail_write

    ; Write page 2 (offset 8192)
    mov rdi, r12
    mov rsi, 8192
    mov rdx, r13
    mov rcx, 8
    call virt_file_write
    cmp rax, 8
    jne .writeback_fail_write

    ; 5. Verify throttled counter is 0 before sync
    cmp qword [sys_writeback_throttled_pages], 0
    jne .writeback_fail_throttled_init

    ; 6. Call virt_page_cache_sync
    ; Flushes 3 pages.
    ; Page 1: 3 dirty pages remaining > 2 limit -> throttled. (throttled_pages becomes 1)
    ; Page 2: 2 dirty pages remaining <= 2 limit -> not throttled.
    ; Page 3: 1 dirty page remaining <= 2 limit -> not throttled.
    call virt_page_cache_sync

    ; 7. Assert that exactly 1 page was throttled
    cmp qword [sys_writeback_throttled_pages], 1
    jne .writeback_fail_throttled_post

    ; Clean up mock file and stack
    add rsp, 16
    mov rdi, r12
    call mock_file_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_writeback_test_passed
    call uart_print_str

    jmp .direct_test_start

.writeback_fail_create:
    mov rsi, msg_writeback_fail_create_str
    call uart_print_str
    jmp .panic_writeback

.writeback_fail_write:
    add rsp, 16
    mov rsi, msg_writeback_fail_write_str
    call uart_print_str
    jmp .panic_writeback

.writeback_fail_throttled_init:
    add rsp, 16
    mov rsi, msg_writeback_fail_throttled_init_str
    call uart_print_str
    jmp .panic_writeback

.writeback_fail_throttled_post:
    add rsp, 16
    mov rsi, msg_writeback_fail_throttled_post_str
    call uart_print_str
    jmp .panic_writeback

.panic_writeback:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.direct_test_start:
    mov rsi, msg_direct_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Initialize page cache
    call virt_page_cache_init

    ; 2. Create mock file of size 16384 bytes
    mov rdi, 16384
    call mock_file_create
    test rax, rax
    jz .direct_fail_create
    mov r12, rax                    ; r12 = mock file pointer

    ; 3. Allocate and map page-aligned virtual buffer at 0x80000000
    ; Create VMA at 0x80000000 (size 4096, flags = VMA_READ | VMA_WRITE)
    mov rdi, 0x80000000
    mov rsi, 4096
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .direct_fail_vma
    mov r14, rax                    ; r14 = VMA pointer

    ; Allocate physical page frame
    call phys_alloc_page
    test rax, rax
    jz .direct_fail_alloc
    mov r15, rax                    ; r15 = physical page

    ; Map virtual address 0x80000000 to physical page
    mov rdi, 0x80000000
    mov rsi, r15
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .direct_fail_map

    ; 4. Enable sys_o_direct
    mov qword [sys_o_direct], 1

    ; Reset telemetry counters
    mov qword [sys_page_cache_hits], 0
    mov qword [sys_page_cache_misses], 0

    ; 5. Read 4096 bytes at offset 0 directly to 0x80000000
    mov rdi, r12
    mov rsi, 0
    mov rdx, 0x80000000
    mov rcx, 4096
    call virt_file_read
    cmp rax, 4096
    jne .direct_fail_read

    ; 6. Assert that cache hits and misses are both 0 (completely bypassed)
    cmp qword [sys_page_cache_hits], 0
    jne .direct_fail_bypass
    cmp qword [sys_page_cache_misses], 0
    jne .direct_fail_bypass

    ; 7. Disable sys_o_direct to test cached mode
    mov qword [sys_o_direct], 0

    ; Read 4096 bytes at offset 0 (cached mode)
    mov rdi, r12
    mov rsi, 0
    mov rdx, 0x80000000
    mov rcx, 4096
    call virt_file_read
    cmp rax, 4096
    jne .direct_fail_read

    ; Assert that it results in a cache miss (proving that direct read did not populate the cache)
    cmp qword [sys_page_cache_misses], 1
    jne .direct_fail_populate

    ; 8. Clean up resources
    mov rdi, 0x80000000
    call virt_unmap

    mov rdi, r15
    call phys_free_page

    mov rdi, r14
    call vma_destroy

    mov rdi, r12
    call mock_file_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_direct_test_passed
    call uart_print_str

    jmp .mglru_test_start

.direct_fail_create:
    mov rsi, msg_direct_fail_create_str
    call uart_print_str
    jmp .panic_direct

.direct_fail_vma:
    mov rsi, msg_direct_fail_vma_str
    call uart_print_str
    jmp .panic_direct

.direct_fail_alloc:
    mov rsi, msg_direct_fail_alloc_str
    call uart_print_str
    jmp .panic_direct

.direct_fail_map:
    mov rsi, msg_direct_fail_map_str
    call uart_print_str
    jmp .panic_direct

.direct_fail_read:
    mov rdi, 0x80000000
    call virt_unmap
    mov rdi, r15
    call phys_free_page
    mov rdi, r14
    call vma_destroy
    mov rdi, r12
    call mock_file_destroy
    mov rsi, msg_direct_fail_read_str
    call uart_print_str
    jmp .panic_direct

.direct_fail_bypass:
    mov rdi, 0x80000000
    call virt_unmap
    mov rdi, r15
    call phys_free_page
    mov rdi, r14
    call vma_destroy
    mov rdi, r12
    call mock_file_destroy
    mov rsi, msg_direct_fail_bypass_str
    call uart_print_str
    jmp .panic_direct

.direct_fail_populate:
    mov rdi, 0x80000000
    call virt_unmap
    mov rdi, r15
    call phys_free_page
    mov rdi, r14
    call vma_destroy
    mov rdi, r12
    call mock_file_destroy
    mov rsi, msg_direct_fail_populate_str
    call uart_print_str
    jmp .panic_direct

.panic_direct:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.mglru_test_start:
    mov rsi, msg_mglru_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Reset MGLRU system
    call virt_mglru_init

    ; Enable MGLRU
    mov qword [sys_mglru_enabled], 1

    ; 2. Create VMA at 0x30000000 (size 8192, 2 pages)
    mov rdi, 0x30000000
    mov rsi, 8192
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .mglru_fail_vma
    mov r12, rax                    ; r12 = VMA pointer

    ; 3. Map Page A (0x30000000) and Page B (0x30001000)
    ; Alloc & Map Page A
    call phys_alloc_page
    test rax, rax
    jz .mglru_fail_alloc
    mov r13, rax                    ; r13 = Page A phys
    mov rdi, 0x30000000
    mov rsi, r13
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .mglru_fail_map

    ; Alloc & Map Page B
    call phys_alloc_page
    test rax, rax
    jz .mglru_fail_alloc
    mov r14, rax                    ; r14 = Page B phys
    mov rdi, 0x30001000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .mglru_fail_map

    ; 4. Verify both pages are added to the youngest Gen 3 initially
    ; Gen 3 count should be 2, Gen 0 count should be 0
    cmp qword [sys_mglru_count + 3 * 8], 2
    jne .mglru_fail_init_count
    cmp qword [sys_mglru_count + 0 * 8], 0
    jne .mglru_fail_init_count

    ; 5. Access Page A to set Accessed bit in PTE
    mov al, [0x30000000]

    ; 6. Age the pages 3 times (Gen 3 -> 2 -> 1 -> 0)
    call virt_mglru_age
    call virt_mglru_age
    call virt_mglru_age

    ; Verify both pages shifted to Gen 0
    ; Gen 3 count should be 0, Gen 0 count should be 2
    cmp qword [sys_mglru_count + 3 * 8], 0
    jne .mglru_fail_age_count
    cmp qword [sys_mglru_count + 0 * 8], 2
    jne .mglru_fail_age_count

    ; Register clean mock RAM swap device for eviction
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Reset telemetry
    mov qword [sys_mglru_promotions], 0
    mov qword [sys_mglru_reclaims], 0

    ; 7. Trigger eviction (invokes MGLRU reclamation)
    ; Page B (Accessed=0) is evicted. Page A (Accessed=1) is promoted to Gen 3.
    call page_replace_clock_evict
    test rax, rax
    jz .mglru_fail_evict

    ; 8. Verify outcomes
    ; Reclaims telemetry should be 1
    cmp qword [sys_mglru_reclaims], 1
    jne .mglru_fail_telemetry
    ; Promotions telemetry should be 1
    cmp qword [sys_mglru_promotions], 1
    jne .mglru_fail_telemetry

    ; Page B must be evicted (PTE not present, swapped is 1)
    mov rdi, 0x30001000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .mglru_fail_pte
    mov rcx, [rax]
    test rcx, 1                     ; present bit (bit 0)
    jnz .mglru_fail_present_evicted
    test rcx, 0x400                 ; swapped bit (bit 10)
    jz .mglru_fail_not_swapped

    ; Page A must be promoted (PTE present, Gen 3 count = 1, Gen 0 count = 0)
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .mglru_fail_pte
    mov rcx, [rax]
    test rcx, 1
    jz .mglru_fail_not_present_promoted

    cmp qword [sys_mglru_count + 3 * 8], 1
    jne .mglru_fail_final_count
    cmp qword [sys_mglru_count + 0 * 8], 0
    jne .mglru_fail_final_count

    ; 9. Clean up resources
    ; Disable MGLRU
    mov qword [sys_mglru_enabled], 0

    ; Unmap and free Page A
    mov rdi, 0x30000000
    call virt_unmap
    mov rdi, r13
    call phys_free_page

    ; Since Page B was evicted and freed, its PTE contains slot. We unmap virtual address.
    mov rdi, 0x30001000
    call virt_unmap

    mov rdi, r12
    call vma_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_mglru_test_passed
    call uart_print_str

    jmp .folio_test_start

.mglru_fail_vma:
    mov rsi, msg_mglru_fail_vma_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_alloc:
    mov rsi, msg_mglru_fail_alloc_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_map:
    mov rsi, msg_mglru_fail_map_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_init_count:
    mov rsi, msg_mglru_fail_init_count_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_age_count:
    mov rsi, msg_mglru_fail_age_count_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_evict:
    mov rsi, msg_mglru_fail_evict_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_telemetry:
    mov rsi, msg_mglru_fail_telemetry_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_pte:
    mov rsi, msg_mglru_fail_pte_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_present_evicted:
    mov rsi, msg_mglru_fail_present_evicted_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_not_swapped:
    mov rsi, msg_mglru_fail_not_swapped_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_not_present_promoted:
    mov rsi, msg_mglru_fail_not_present_promoted_str
    call uart_print_str
    jmp .panic_mglru

.mglru_fail_final_count:
    mov rsi, msg_mglru_fail_final_count_str
    call uart_print_str
    jmp .panic_mglru

.panic_mglru:
    mov qword [sys_mglru_enabled], 0
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.folio_test_start:
    mov rsi, msg_folio_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Initialize page cache
    call virt_page_cache_init

    ; 2. Configure sys_folio_size to 16384 (16KB, 4 pages)
    mov qword [sys_folio_size], 16384

    ; Reset telemetry
    mov qword [sys_page_cache_hits], 0
    mov qword [sys_page_cache_misses], 0
    mov qword [sys_page_cache_count], 0

    ; 3. Create mock file of size 16384 bytes
    mov rdi, 16384
    call mock_file_create
    test rax, rax
    jz .folio_fail_create
    mov r12, rax                    ; r12 = mock file pointer

    ; Prepare temporary stack buffer for reading/writing
    sub rsp, 16
    mov r13, rsp                    ; r13 = buffer

    ; 4. Read 8 bytes from offset 0
    mov rdi, r12
    mov rsi, 0
    mov rdx, r13
    mov rcx, 8
    call virt_file_read
    cmp rax, 8
    jne .folio_fail_read

    ; Cache misses must be 1 (first read allocates folio)
    cmp qword [sys_page_cache_misses], 1
    jne .folio_fail_misses_init
    ; Cache count must be 1 (only 1 folio allocated)
    cmp qword [sys_page_cache_count], 1
    jne .folio_fail_count_init

    ; 5. Read 8 bytes from offset 4096 (second page inside folio)
    mov rdi, r12
    mov rsi, 4096
    mov rdx, r13
    mov rcx, 8
    call virt_file_read
    cmp rax, 8
    jne .folio_fail_read

    ; Cache hits must be 1
    cmp qword [sys_page_cache_hits], 1
    jne .folio_fail_hits

    ; 6. Read 8 bytes from offset 8192 (third page inside folio)
    mov rdi, r12
    mov rsi, 8192
    mov rdx, r13
    mov rcx, 8
    call virt_file_read
    cmp rax, 8
    jne .folio_fail_read

    ; Cache hits must be 2
    cmp qword [sys_page_cache_hits], 2
    jne .folio_fail_hits

    ; 7. Write 8 bytes to offset 12288 (fourth page inside folio)
    mov qword [r13], 0x8877665544332211
    mov rdi, r12
    mov rsi, 12288
    mov rdx, r13
    mov rcx, 8
    call virt_file_write
    cmp rax, 8
    jne .folio_fail_write

    ; 8. Synchronize dirty folio back to mock disk
    call virt_page_cache_sync

    ; 9. Clean up and restore sys_folio_size
    mov qword [sys_folio_size], 4096 ; restore default

    add rsp, 16
    mov rdi, r12
    call mock_file_destroy

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_folio_test_passed
    call uart_print_str

    jmp .kmem_acc_test_start

.folio_fail_create:
    mov rsi, msg_folio_fail_create_str
    call uart_print_str
    jmp .panic_folio

.folio_fail_read:
    add rsp, 16
    mov rsi, msg_folio_fail_read_str
    call uart_print_str
    jmp .panic_folio

.folio_fail_misses_init:
    add rsp, 16
    mov rsi, msg_folio_fail_misses_init_str
    call uart_print_str
    jmp .panic_folio

.folio_fail_count_init:
    add rsp, 16
    mov rsi, msg_folio_fail_count_init_str
    call uart_print_str
    jmp .panic_folio

.folio_fail_hits:
    add rsp, 16
    mov rsi, msg_folio_fail_hits_str
    call uart_print_str
    jmp .panic_folio

.folio_fail_write:
    add rsp, 16
    mov rsi, msg_folio_fail_write_str
    call uart_print_str
    jmp .panic_folio

.panic_folio:
    mov qword [sys_folio_size], 4096
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.kmem_acc_test_start:
    mov rsi, msg_kmem_acc_test_start
    call uart_print_str

    push r12
    push r13
    push r14
    push r15

    ; 1. Create a cgroup with ID = 2, hard_limit = 1000 pages, soft_limit = 500 pages
    mov rdi, 2                      ; ID
    mov rsi, 1000                   ; hard limit
    mov rdx, 500                    ; soft limit
    extern virt_memcg_create
    call virt_memcg_create
    test rax, rax
    jz .kmem_acc_fail_create_cg
    mov r12, rax                    ; R12 = cgroup pointer

    ; 2. Attach current thread to this cgroup
    lea rdi, [thread_table]
    mov rsi, r12
    extern virt_memcg_attach
    call virt_memcg_attach

    ; Reset kmem statistics of mock cgroup (in case of garbage)
    mov qword [r12 + mem_cgroup_t.kmem_usage], 0
    mov qword [r12 + mem_cgroup_t.kmem_pages], 0
    mov qword [r12 + mem_cgroup_t.usage], 0

    ; 3. Allocate heap slab block of 8192 bytes
    mov rdi, 8192
    call heap_alloc
    test rax, rax
    jz .kmem_acc_fail_alloc_heap
    mov r13, rax                    ; R13 = offsetted heap pointer

    ; 4. Assert that cgroup kmem_usage is 8192 bytes
    mov rax, [r12 + mem_cgroup_t.kmem_usage]
    cmp rax, 8192
    jne .kmem_acc_fail_usage_val

    ; Assert that cgroup usage is 2 pages (8192 / 4096)
    mov rax, [r12 + mem_cgroup_t.usage]
    cmp rax, 2
    jne .kmem_acc_fail_pages_val

    ; 5. Map a virtual address at 0x90000000 to trigger a page table allocation
    ; Note: this will map virtual address 0x90000000 to physical frame 0x10000000 with user/writable flags.
    ; This will invoke pgtable allocation.
    mov rdi, 0x90000000
    mov rsi, 0x10000000
    mov rdx, 0x07                   ; PRESENT | WRITE | USER
    call virt_map
    test rax, rax
    jz .kmem_acc_fail_map

    ; Assert that cgroup kmem_usage has increased by at least one page table page (4096 bytes)
    ; New kmem_usage = 8192 + 4096 = 12288 bytes (or more if multiple page table levels are allocated).
    mov rax, [r12 + mem_cgroup_t.kmem_usage]
    cmp rax, 12288
    jb .kmem_acc_fail_pgtable_charge

    ; Assert that cgroup usage is at least 3 pages (8192 + 4096 = 12288 bytes -> 3 pages)
    mov rax, [r12 + mem_cgroup_t.usage]
    cmp rax, 3
    jb .kmem_acc_fail_pgtable_charge

    ; 6. Free the heap memory
    mov rdi, r13
    call heap_free

    ; Assert that cgroup kmem_usage dropped back by 8192 bytes
    ; It should be kmem_usage_after_map - 8192.
    ; Let's verify that it is exactly kmem_usage_after_map - 8192.
    ; Since pgtable allocation is 4096 (1 page), kmem_usage should now be 4096 bytes.
    mov rax, [r12 + mem_cgroup_t.kmem_usage]
    cmp rax, 4096
    jne .kmem_acc_fail_uncharge_val

    ; Assert that cgroup usage is now 1 page
    mov rax, [r12 + mem_cgroup_t.usage]
    cmp rax, 1
    jne .kmem_acc_fail_uncharge_pages

    ; 7. Unmap the virtual page to prevent leaks and cleanup
    mov rdi, 0x90000000
    call virt_unmap

    ; Dissociate current thread from cgroup
    lea rdi, [thread_table]
    mov qword [rdi + thread_t.cgroup_ptr], 0

    ; Free mock cgroup structure using heap_free
    ; (Since heap_free uncharges, it will uncharge the remaining 4096 bytes of page table frame, dropping kmem to 0).
    mov rdi, r12
    call heap_free

    pop r15
    pop r14
    pop r13
    pop r12

    mov rsi, msg_kmem_acc_test_passed
    call uart_print_str

    jmp .mtrr_test_start

.kmem_acc_fail_create_cg:
    mov rsi, msg_kmem_acc_fail_create_cg_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_alloc_heap:
    mov rsi, msg_kmem_acc_fail_alloc_heap_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_usage_val:
    mov rdi, r13
    call heap_free
    mov rsi, msg_kmem_acc_fail_usage_val_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_pages_val:
    mov rdi, r13
    call heap_free
    mov rsi, msg_kmem_acc_fail_pages_val_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_map:
    mov rdi, r13
    call heap_free
    mov rsi, msg_kmem_acc_fail_map_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_pgtable_charge:
    mov rdi, 0x90000000
    call virt_unmap
    mov rdi, r13
    call heap_free
    mov rsi, msg_kmem_acc_fail_pgtable_charge_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_uncharge_val:
    mov rdi, 0x90000000
    call virt_unmap
    mov rsi, msg_kmem_acc_fail_uncharge_val_str
    call uart_print_str
    jmp .panic_kmem_acc

.kmem_acc_fail_uncharge_pages:
    mov rdi, 0x90000000
    call virt_unmap
    mov rsi, msg_kmem_acc_fail_uncharge_pages_str
    call uart_print_str
    jmp .panic_kmem_acc

.panic_kmem_acc:
    lea rdi, [thread_table]
    mov qword [rdi + thread_t.cgroup_ptr], 0
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic







.oom_psi_fail_init:
    mov rsi, msg_oom_psi_fail_init_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_sys_some:
    mov rsi, msg_oom_psi_fail_sys_some_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_sys_full:
    mov rsi, msg_oom_psi_fail_sys_full_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_cgroup_create:
    mov rsi, msg_oom_psi_fail_cgroup_create_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_register:
    mov rsi, msg_oom_psi_fail_register_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_cg_some_zero:
    mov rdi, r15
    call virt_memcg_destroy
    mov rsi, msg_oom_psi_fail_cg_some_zero_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_cg_full_nonzero:
    mov rdi, r15
    call virt_memcg_destroy
    mov rsi, msg_oom_psi_fail_cg_full_nonzero_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_cg_some_noinc:
    mov rdi, r15
    call virt_memcg_destroy
    mov rsi, msg_oom_psi_fail_cg_some_noinc_str
    call uart_print_str
    jmp .panic_oom_psi

.oom_psi_fail_cg_full_zero:
    mov rdi, r15
    call virt_memcg_destroy
    mov rsi, msg_oom_psi_fail_cg_full_zero_str
    call uart_print_str
    jmp .panic_oom_psi

.panic_oom_psi:
    mov qword [thread_count], 4
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.oom_retry_fail_register:
    mov rsi, msg_oom_retry_fail_register_str
    call uart_print_str
    jmp .panic_oom_retry

.oom_retry_fail_alloc:
    mov qword [virt_alloc_retry_mock], 0
    mov rsi, msg_oom_retry_fail_alloc_str
    call uart_print_str
    jmp .panic_oom_retry

.oom_retry_fail_killed:
    mov qword [virt_alloc_retry_mock], 0
    mov rdi, r14
    call vma_destroy
    mov rsi, msg_oom_retry_fail_killed_str
    call uart_print_str
    jmp .panic_oom_retry

.panic_oom_retry:
    mov qword [overcommit_mode], 2  ; restore heuristic
    mov qword [virt_reserved_pages], 0
    test r12, r12
    jz .skip_retry_thread
    mov qword [r12 + thread_t.flags], 0
.skip_retry_thread:
    mov qword [thread_count], 4
    pop r14
    pop r13
    pop r12
    jmp .panic

.oom_cgroup_fail_create:
    mov rsi, msg_oom_cgroup_fail_create_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_register:
    mov rsi, msg_oom_cgroup_fail_register_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_soft_alloc:
    mov rsi, msg_oom_cgroup_fail_soft_alloc_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_soft_charge:
    mov rdi, r15
    call vma_destroy
    mov rsi, msg_oom_cgroup_fail_soft_charge_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_hard_alloc:
    mov rdi, r15
    call vma_destroy
    mov rsi, msg_oom_cgroup_fail_hard_alloc_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_not_killed:
    mov rdi, r15
    call vma_destroy
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_oom_cgroup_fail_not_killed_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_killed_wrong:
    mov rdi, r15
    call vma_destroy
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_oom_cgroup_fail_killed_wrong_str
    call uart_print_str
    jmp .panic_oom_cgroup

.oom_cgroup_fail_final_charge:
    mov rdi, r15
    call vma_destroy
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_oom_cgroup_fail_final_charge_str
    call uart_print_str
    jmp .panic_oom_cgroup

.panic_oom_cgroup:
    ; Detach cgroup from thread 100
    lea rdi, [thread_table]
    mov rsi, 0
    call virt_memcg_attach
    
    ; Deactivate Thread A and B if possible
    mov rax, 4
    imul rax, thread_t_size
    lea rax, [thread_table + rax]
    mov qword [rax + thread_t.flags], 0
    mov rax, 5
    imul rax, thread_t_size
    lea rax, [thread_table + rax]
    mov qword [rax + thread_t.flags], 0
    
    mov qword [thread_count], 4
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.oom_notify_fail_register:
    mov rsi, msg_oom_notify_fail_register_str
    call uart_print_str
    jmp .panic_oom_notify

.oom_notify_fail_alloc:
    mov rsi, msg_oom_notify_fail_alloc_str
    call uart_print_str
    jmp .panic_oom_notify

.oom_notify_fail_not_terminated:
    mov rdi, r14
    call vma_destroy
    mov rsi, msg_oom_notify_fail_not_terminated_str
    call uart_print_str
    jmp .panic_oom_notify

.oom_notify_fail_callback_not_run:
    mov rdi, r14
    call vma_destroy
    mov rsi, msg_oom_notify_fail_callback_not_run_str
    call uart_print_str
    jmp .panic_oom_notify

.panic_oom_notify:
    ; Clean up thread flags and reservations before panic
    test r12, r12
    jz .skip_n
    mov qword [r12 + thread_t.flags], 0
.skip_n:
    mov qword [overcommit_mode], 2  ; restore heuristic
    mov qword [virt_reserved_pages], 0
    pop r14
    pop r13
    pop r12
    jmp .panic

; -----------------------------------------------------------------------------
; oom_notifier_callback â€” Graceful shutdown callback executed by OOM Notifier
; -----------------------------------------------------------------------------
.oom_notifier_callback:
    mov rsi, msg_oom_callback_executed
    call uart_print_str
    mov qword [oom_callback_flag], 1
    ret

.dbg_phys_wp_fail_alloc:
    mov rsi, msg_dbg_phys_wp_fail_alloc_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_vma1:
    mov rsi, msg_dbg_phys_wp_fail_vma1_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_vma2:
    mov rsi, msg_dbg_phys_wp_fail_vma2_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_map1:
    mov rsi, msg_dbg_phys_wp_fail_map1_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_map2:
    mov rsi, msg_dbg_phys_wp_fail_map2_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_register:
    mov rsi, msg_dbg_phys_wp_fail_register_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_walk:
    mov rsi, msg_dbg_phys_wp_fail_walk_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_non_present:
    mov rsi, msg_dbg_phys_wp_fail_non_present_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_hit_init:
    mov rsi, msg_dbg_phys_wp_fail_hit_init_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_hit_read:
    mov rsi, msg_dbg_phys_wp_fail_hit_read_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_rip_read:
    mov rsi, msg_dbg_phys_wp_fail_rip_read_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_vaddr_read:
    mov rsi, msg_dbg_phys_wp_fail_vaddr_read_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_type_read:
    mov rsi, msg_dbg_phys_wp_fail_type_read_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_present_restored:
    mov rsi, msg_dbg_phys_wp_fail_present_restored_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_rearm:
    mov rsi, msg_dbg_phys_wp_fail_rearm_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_hit_write:
    mov rsi, msg_dbg_phys_wp_fail_hit_write_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_rip_write:
    mov rsi, msg_dbg_phys_wp_fail_rip_write_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_vaddr_write:
    mov rsi, msg_dbg_phys_wp_fail_vaddr_write_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_type_write:
    mov rsi, msg_dbg_phys_wp_fail_type_write_str
    call uart_print_str
    jmp .panic_phys_wp

.dbg_phys_wp_fail_deregister:
    mov rsi, msg_dbg_phys_wp_fail_deregister_str
    call uart_print_str
    jmp .panic_phys_wp

.panic_phys_wp:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic


.dbg_hist_fail_alloc:
    mov rsi, msg_dbg_hist_fail_alloc_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_vma:
    mov rsi, msg_dbg_hist_fail_vma_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_map:
    mov rsi, msg_dbg_hist_fail_map_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_register:
    mov rsi, msg_dbg_hist_fail_register_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_walk:
    mov rsi, msg_dbg_hist_fail_walk_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_non_present:
    mov rsi, msg_dbg_hist_fail_non_present_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_count_init:
    mov rsi, msg_dbg_hist_fail_count_init_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_read_count:
    mov rsi, msg_dbg_hist_fail_read_count_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_write_count:
    mov rsi, msg_dbg_hist_fail_write_count_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_total_count:
    mov rsi, msg_dbg_hist_fail_total_count_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_present_restored:
    mov rsi, msg_dbg_hist_fail_present_restored_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_rearm:
    mov rsi, msg_dbg_hist_fail_rearm_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_read_count2:
    mov rsi, msg_dbg_hist_fail_read_count2_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_write_count2:
    mov rsi, msg_dbg_hist_fail_write_count2_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_total_count2:
    mov rsi, msg_dbg_hist_fail_total_count2_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_read_count3:
    mov rsi, msg_dbg_hist_fail_read_count3_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_write_count3:
    mov rsi, msg_dbg_hist_fail_write_count3_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_total_count3:
    mov rsi, msg_dbg_hist_fail_total_count3_str
    call uart_print_str
    jmp .panic_hist

.dbg_hist_fail_deregister:
    mov rsi, msg_dbg_hist_fail_deregister_str
    call uart_print_str
    jmp .panic_hist

.panic_hist:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic


.dbg_ift_fail_alloc:
    mov rsi, msg_dbg_ift_fail_alloc_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_vma:
    mov rsi, msg_dbg_ift_fail_vma_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_map:
    mov rsi, msg_dbg_ift_fail_map_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_register:
    mov rsi, msg_dbg_ift_fail_register_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_walk:
    mov rsi, msg_dbg_ift_fail_walk_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_nx_set:
    mov rsi, msg_dbg_ift_fail_nx_set_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_hit_init:
    mov rsi, msg_dbg_ift_fail_hit_init_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_hit_exec:
    mov rsi, msg_dbg_ift_fail_hit_exec_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_rip_exec:
    mov rsi, msg_dbg_ift_fail_rip_exec_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_nx_cleared:
    mov rsi, msg_dbg_ift_fail_nx_cleared_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_rearm:
    mov rsi, msg_dbg_ift_fail_rearm_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_nx_rearmed:
    mov rsi, msg_dbg_ift_fail_nx_rearmed_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_hit_exec2:
    mov rsi, msg_dbg_ift_fail_hit_exec2_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_rip_exec2:
    mov rsi, msg_dbg_ift_fail_rip_exec2_str
    call uart_print_str
    jmp .panic_ift

.dbg_ift_fail_deregister:
    mov rsi, msg_dbg_ift_fail_deregister_str
    call uart_print_str
    jmp .panic_ift

.panic_ift:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic


.dbg_wp_fail_alloc:
    mov rsi, msg_dbg_wp_fail_alloc_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_vma:
    mov rsi, msg_dbg_wp_fail_vma_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_map:
    mov rsi, msg_dbg_wp_fail_map_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_register:
    mov rsi, msg_dbg_wp_fail_register_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_walk:
    mov rsi, msg_dbg_wp_fail_walk_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_non_present:
    mov rsi, msg_dbg_wp_fail_non_present_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_hit_init:
    mov rsi, msg_dbg_wp_fail_hit_init_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_hit_read:
    mov rsi, msg_dbg_wp_fail_hit_read_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_rip_read:
    mov rsi, msg_dbg_wp_fail_rip_read_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_type_read:
    mov rsi, msg_dbg_wp_fail_type_read_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_present_read:
    mov rsi, msg_dbg_wp_fail_present_read_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_rearm:
    mov rsi, msg_dbg_wp_fail_rearm_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_hit_write:
    mov rsi, msg_dbg_wp_fail_hit_write_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_rip_write:
    mov rsi, msg_dbg_wp_fail_rip_write_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_type_write:
    mov rsi, msg_dbg_wp_fail_type_write_str
    call uart_print_str
    jmp .panic_wp

.dbg_wp_fail_deregister:
    mov rsi, msg_dbg_wp_fail_deregister_str
    call uart_print_str
    jmp .panic_wp

.panic_wp:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.decomp_fail_alloc:
    mov rsi, msg_zram_fail_alloc_str
    call uart_print_str
    jmp .panic_decomp

.decomp_fail_comp:
    mov rsi, msg_zpool_decomp_fail_comp_str
    call uart_print_str
    jmp .panic_decomp

.decomp_fail_submit:
    mov rsi, msg_zpool_decomp_fail_submit_str
    call uart_print_str
    jmp .panic_decomp

.decomp_fail_status:
    mov rsi, msg_zpool_decomp_fail_status_str
    call uart_print_str
    jmp .panic_decomp

.decomp_fail_data:
    mov rsi, msg_zpool_decomp_fail_data_str
    call uart_print_str
    jmp .panic_decomp

.panic_decomp:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.wb_fail_alloc:
    mov rsi, msg_zram_fail_alloc_str
    call uart_print_str
    jmp .panic_wb

.wb_fail_vma:
    mov rsi, msg_zram_fail_vma_str
    call uart_print_str
    jmp .panic_wb

.wb_fail_map:
    mov rsi, msg_zram_fail_map_str
    call uart_print_str
    jmp .panic_wb

.wb_fail_evict:
    mov rsi, msg_zram_fail_evict_str
    call uart_print_str
    jmp .panic_wb

.fail_zswap_flags:
    mov rsi, msg_zpool_writeback_fail_zswap_flags_str
    call uart_print_str
    jmp .panic_wb

.fail_zswap_data_wb:
    mov rsi, msg_zpool_writeback_fail_zswap_data_str
    call uart_print_str
    jmp .panic_wb

.fail_zram_flags:
    mov rsi, msg_zpool_writeback_fail_zram_flags_str
    call uart_print_str
    jmp .panic_wb

.fail_zram_data_wb:
    mov rsi, msg_zpool_writeback_fail_zram_data_str
    call uart_print_str
    jmp .panic_wb

.panic_wb:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.compact_fail_alloc:
    mov rsi, msg_zram_fail_alloc_str
    call uart_print_str
    jmp .panic_compact

.compact_fail_vma:
    mov rsi, msg_zram_fail_vma_str
    call uart_print_str
    jmp .panic_compact

.compact_fail_map:
    mov rsi, msg_zram_fail_map_str
    call uart_print_str
    jmp .panic_compact

.compact_fail_evict:
    mov rsi, msg_zram_fail_evict_str
    call uart_print_str
    jmp .panic_compact

.fail_zswap_inuse:
    mov rsi, msg_zpool_compact_fail_zswap_inuse_str
    call uart_print_str
    jmp .panic_compact

.fail_zswap_data_compact:
    mov rsi, msg_zpool_compact_fail_zswap_data_str
    call uart_print_str
    jmp .panic_compact

.fail_zram_inuse:
    mov rsi, msg_zpool_compact_fail_zram_inuse_str
    call uart_print_str
    jmp .panic_compact

.fail_zram_data_compact:
    mov rsi, msg_zpool_compact_fail_zram_data_str
    call uart_print_str
    jmp .panic_compact

.panic_compact:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.fail_high:
    mov rsi, msg_zpool_balance_fail_high_str
    call uart_print_str
    jmp .panic_balance

.fail_mid:
    mov rsi, msg_zpool_balance_fail_mid_str
    call uart_print_str
    jmp .panic_balance

.fail_low:
    mov rsi, msg_zpool_balance_fail_low_str
    call uart_print_str
    jmp .panic_balance

.fail_reject_zram_alloc:
    mov rsi, msg_zram_fail_alloc_str
    call uart_print_str
    jmp .panic_balance

.fail_reject_zram:
    ; Clean up page if it succeeded or failed but allocated
    mov rdi, r12
    call phys_free_page
    mov rsi, msg_zpool_balance_fail_reject_zram_str
    call uart_print_str
    jmp .panic_balance

.fail_reject_zswap_alloc:
    mov rsi, msg_zram_fail_alloc_str
    call uart_print_str
    jmp .panic_balance

.fail_reject_zswap:
    mov rdi, r12
    call phys_free_page
    mov rsi, msg_zpool_balance_fail_reject_zswap_str
    call uart_print_str
    jmp .panic_balance

.panic_balance:
    ; Restore original state
    mov [phys_state + phys_state_t.free_pages], r14
    mov [phys_state + phys_state_t.total_pages], r15
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.zram_fail_init_telemetry:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_init_telemetry_str
    call uart_print_str
    jmp .panic

.zram_fail_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_alloc_str
    call uart_print_str
    jmp .panic

.zram_fail_vma:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_vma_str
    call uart_print_str
    jmp .panic

.zram_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_map_str
    call uart_print_str
    jmp .panic

.zram_fail_walk:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_walk_str
    call uart_print_str
    jmp .panic

.zram_fail_evict:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_evict_str
    call uart_print_str
    jmp .panic

.zram_fail_walk_ev:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.zram_fail_still_present:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_still_present_str
    call uart_print_str
    jmp .panic

.zram_fail_not_swapped:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_not_swapped_str
    call uart_print_str
    jmp .panic

.zram_fail_telemetry:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_telemetry_str
    call uart_print_str
    jmp .panic

.zram_fail_data_corrupt:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_data_corrupt_str
    call uart_print_str
    jmp .panic

.zram_fail_telemetry_res:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_zram_fail_telemetry_res_str
    call uart_print_str
    jmp .panic

    ; -------------------------------------------------------------
    ; 10. Run VMM MTRR Cache Programming Test
    ; -------------------------------------------------------------
    mov rsi, msg_mtrr_test_start
    call uart_print_str

    ; Step A: Verify MTRRs are supported on this processor
    call mtrr_supported
    test rax, rax
    jz .mtrr_skip_test              ; if not supported, skip gracefully

    ; Step B: Print variable count
    call mtrr_get_vcnt
    mov rsi, msg_mtrr_vcnt_str
    call uart_print_str
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; Step C: Set Variable MTRR slot 0 to Write-Combining (1)
    ; Base: 0xE0000000, Size: 16MB (0x1000000)
    mov rdi, 0                      ; slot 0
    mov rsi, 0xE0000000             ; base physical address
    mov rdx, 0x1000000              ; size (16MB)
    mov rcx, 1                      ; type: Write-Combining (WC)
    call mtrr_set_variable
    test rax, rax
    jz .mtrr_fail_set

    ; Step D: Retrieve and verify variable range
    mov rdi, 0                      ; slot 0
    call mtrr_get_variable          ; RAX=1, RSI=base, RDX=size, RCX=type
    test rax, rax
    jz .mtrr_fail_get_active

    ; Verify base address
    cmp rsi, 0xE0000000
    jne .mtrr_fail_base

    ; Verify size
    cmp rdx, 0x1000000
    jne .mtrr_fail_size

    ; Verify memory type
    cmp rcx, 1
    jne .mtrr_fail_type

    ; Step E: Disable variable MTRR slot 0 to clean up
    mov rdi, 0
    call mtrr_disable_variable
    test rax, rax
    jz .mtrr_fail_disable

    ; Step F: Verify slot is indeed disabled now
    mov rdi, 0
    call mtrr_get_variable
    test rax, rax
    jnz .mtrr_fail_still_active

    ; MTRR Programming Test PASSED!
    mov rsi, msg_mtrr_test_passed
    call uart_print_str
    jmp .run_pat_test

.mtrr_skip_test:
    mov rsi, msg_mtrr_skipped_str
    call uart_print_str
    jmp .run_pat_test

.run_pat_test:
    ; -------------------------------------------------------------
    ; 11. Run VMM PAT Cache Configuration Test
    ; -------------------------------------------------------------
    mov rsi, msg_pat_test_start
    call uart_print_str

    ; Step A: Verify PAT is supported on this processor
    call pat_supported
    test rax, rax
    jz .pat_skip_test

    ; Step B: Read and verify default PAT MSR value
    call pat_get_msr                ; RAX = current PAT MSR value
    test rax, rax
    jz .pat_fail_get

    ; Save the default PAT value in R12
    mov r12, rax

    ; Step C: Assert default indices for key memory types
    ; Index for Write-Back (WB = 6) should be 0
    mov rdi, 6
    call pat_find_entry
    cmp rax, 0
    jne .pat_fail_wb_index

    ; Index for Write-Through (WT = 4) should be 1
    mov rdi, 4
    call pat_find_entry
    cmp rax, 1
    jne .pat_fail_wt_index

    ; Index for Write-Combining (WC = 1) should be 5
    mov rdi, 1
    call pat_find_entry
    cmp rax, 5
    jne .pat_fail_wc_index

    ; Index for Uncached (UC = 0) should be 3
    mov rdi, 0
    call pat_find_entry
    cmp rax, 3
    jne .pat_fail_uc_index

    ; Step D: Modify PAT to check writing capability
    ; We construct a custom PAT layout:
    ; Swap PAT4 (WP=5) and PAT5 (WC=1):
    ; Default EDX:EAX = 0x00070105_00070406
    ; Custom EDX:EAX  = 0x00070501_00070406
    mov rdi, 0x0007050100070406
    call pat_set_msr
    test rax, rax
    jz .pat_fail_set

    ; Step E: Verify swap succeeded
    ; Now, Write-Combining (WC = 1) should be found at index 4 (instead of 5)
    mov rdi, 1
    call pat_find_entry
    cmp rax, 4
    jne .pat_fail_wc_swap

    ; Write-Protect (WP = 5) should be found at index 5 (instead of 4)
    mov rdi, 5
    call pat_find_entry
    cmp rax, 5
    jne .pat_fail_wp_swap

    ; Step F: Restore original default PAT value
    mov rdi, r12
    call pat_set_msr
    test rax, rax
    jz .pat_fail_restore

    ; Verify that WC is restored back to index 5
    mov rdi, 1
    call pat_find_entry
    cmp rax, 5
    jne .pat_fail_restore_verify

    ; PAT Configuration Test PASSED!
    mov rsi, msg_pat_test_passed
    call uart_print_str
    jmp .run_fb_test

.run_fb_test:
    mov rsi, msg_fb_test_start_str
    call uart_print_str

    call fb_init
    cmp rax, 2                      ; skipped gracefully (no framebuffer)
    je .fb_skip_test
    test rax, rax
    jz .fb_fail_init

    call fb_benchmark
    test rax, rax
    jz .fb_fail_bench

    mov rsi, msg_fb_test_passed_str
    call uart_print_str
    jmp .run_heap_test

.fb_skip_test:
    mov rsi, msg_fb_skipped_str
    call uart_print_str
    jmp .run_heap_test


.fb_fail_init:
    mov rsi, msg_fb_fail_init_str
    call uart_print_str
    jmp .panic

.fb_fail_bench:
    mov rsi, msg_fb_fail_bench_str
    call uart_print_str
    jmp .panic

.run_heap_test:
    mov rsi, msg_heap_test_start
    call uart_print_str

    ; Step A: Verify that heap_active_allocator is 1 (free-list active)
    mov al, [heap_active_allocator]
    cmp al, 1
    jne .heap_fail_active

    ; Step B: Allocate three consecutive blocks of 64 bytes: A, B, C
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc
    mov r12, rax                    ; R12 = pointer A

    test rax, 15
    jnz .heap_fail_align

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc2
    mov r13, rax                    ; R13 = pointer B

    test rax, 15
    jnz .heap_fail_align2

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc3
    mov r14, rax                    ; R14 = pointer C

    test rax, 15
    jnz .heap_fail_align3

    ; Step C: Assert spacing between consecutive blocks
    ; Header size heap_block_t_size is 32 bytes. Payload is 64 bytes.
    ; Thus, B - A must be exactly 96 bytes (64 + 32).
    ; Likewise, C - B must be exactly 96 bytes.
    mov rax, r13
    sub rax, r12                    ; RAX = B - A
    cmp rax, 96
    jne .heap_fail_spacing

    mov rax, r14
    sub rax, r13                    ; RAX = C - B
    cmp rax, 96
    jne .heap_fail_spacing

    ; Step D: Free the middle block B to create a hole in the free list
    mov rdi, r13
    call heap_free

    ; Step E: Allocate a 16-byte block (below the splitting threshold of B)
    ; B size is 64 bytes. 16-byte aligned payload = 16.
    ; Splitting threshold minimum size = aligned_size (16) + header_size (32) + 16 = 64 bytes.
    ; Since B size (64) >= 64, it MUST split block B!
    ; Allocating 16 bytes from B (64 bytes) splits it into:
    ; - Allocated block: 16 bytes (pointer = B)
    ; - Remaining free block: 64 - 16 - 32 = 16 bytes (header at B + 16, pointer = B + 48)
    mov rdi, 16
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc_split
    mov r15, rax                    ; R15 = pointer to split block

    ; Verify that R15 (new allocation) returned exactly R13 (pointer B)
    cmp r15, r13
    jne .heap_fail_split_ptr

    ; Step F: Allocate another 16 bytes (should consume the split free block at B + 48)
    mov rdi, 16
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc_split2
    mov rbx, rax                    ; RBX = pointer to split remainder

    ; Verify the address of split remainder is B + 48 (R13 + 48)
    mov rax, r13
    add rax, 48
    cmp rbx, rax
    jne .heap_fail_split_rem

    ; Step G: Free all allocations to check coalescing
    mov rdi, r12                    ; free A
    call heap_free

    mov rdi, r15                    ; free split part 1 (B start)
    call heap_free

    mov rdi, rbx                    ; free split part 2 (B remainder)
    call heap_free

    mov rdi, r14                    ; free C
    call heap_free

    ; Step H: Allocate 256 bytes (requires merging A, B, and C)
    ; Contiguous free space from A start to C end:
    ; A payload (64) + B header (32) + B payload (64) + C header (32) + C payload (64) = 256 bytes.
    mov rdi, 256
    call heap_alloc
    test rax, rax
    jz .heap_fail_coalesce
    mov rbx, rax

    ; Verify it starts exactly at pointer A (R12)
    cmp rbx, r12
    jne .heap_fail_coalesce_ptr

    ; Free the coalesced block
    mov rdi, rbx
    call heap_free

    ; Heap Allocator Test PASSED!
    mov rsi, msg_heap_test_passed
    call uart_print_str
    jmp .run_defrag_test

.run_defrag_test:
    mov rsi, msg_defrag_test_start
    call uart_print_str

    ; Step A: Allocate three consecutive 64-byte blocks: A, B, C
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .defrag_fail_alloc_A
    mov [ptr_A], rax

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .defrag_fail_alloc_B
    mov [ptr_B], rax

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .defrag_fail_alloc_C
    mov [ptr_C], rax

    ; Step B: Register the pointer variables
    mov rdi, ptr_A
    call heap_register_relocatable
    test rax, rax
    jz .defrag_fail_reg

    mov rdi, ptr_B
    call heap_register_relocatable
    test rax, rax
    jz .defrag_fail_reg

    mov rdi, ptr_C
    call heap_register_relocatable
    test rax, rax
    jz .defrag_fail_reg

    ; Save block addresses for assertions
    mov r12, [ptr_A]                ; R12 = A's original payload address
    mov r13, [ptr_B]                ; R13 = B's original payload address
    mov r14, [ptr_C]                ; R14 = C's original payload address

    ; Step C: Free middle block B to create a hole
    mov rdi, [ptr_B]
    call heap_free

    ; Step D: Perform Compaction!
    call heap_compact
    test rax, rax
    jz .defrag_fail_compact

    ; Step E: Assertions
    ; 1. ptr_A must still point to A's original payload address
    mov rax, [ptr_A]
    cmp rax, r12
    jne .defrag_fail_assert_A

    ; 2. ptr_C must now point to B's original payload address (relocated payload)
    mov rax, [ptr_C]
    cmp rax, r13
    jne .defrag_fail_assert_C

    ; Step F: Clean up and unregister variables
    mov rdi, ptr_A
    call heap_unregister_relocatable
    mov rdi, ptr_B
    call heap_unregister_relocatable
    mov rdi, ptr_C
    call heap_unregister_relocatable

    ; Free compacted blocks A and C
    mov rdi, [ptr_A]
    call heap_free
    mov rdi, [ptr_C]
    call heap_free

    ; Heap Defragmenter Test PASSED!
    mov rsi, msg_defrag_test_passed
    call uart_print_str
    jmp .run_slab_test

.defrag_fail_alloc_A:
    mov rsi, msg_defrag_fail_alloc_A_str
    call uart_print_str
    jmp .panic

.defrag_fail_alloc_B:
    mov rsi, msg_defrag_fail_alloc_B_str
    call uart_print_str
    jmp .panic

.defrag_fail_alloc_C:
    mov rsi, msg_defrag_fail_alloc_C_str
    call uart_print_str
    jmp .panic

.defrag_fail_reg:
    mov rsi, msg_defrag_fail_reg_str
    call uart_print_str
    jmp .panic

.defrag_fail_compact:
    mov rsi, msg_defrag_fail_compact_str
    call uart_print_str
    jmp .panic

.defrag_fail_assert_A:
    mov rsi, msg_defrag_fail_assert_A_str
    call uart_print_str
    jmp .panic

.defrag_fail_assert_C:
    mov rsi, msg_defrag_fail_assert_C_str
    call uart_print_str
    jmp .panic

.run_slab_test:
    mov rsi, msg_slab_test_start
    call uart_print_str

    ; --- 1. Verify kmem_cache_file ---
    ; Check name is initialized to non-null and starts with 'kmem'
    mov rax, [kmem_cache_file + kmem_cache_t.name]
    test rax, rax
    jz .slab_fail_name
    mov ebx, [rax]
    cmp ebx, 0x6D656D6B             ; 'kmem' in little endian (0x6B, 0x6D, 0x65, 0x6D)
    jne .slab_fail_name

    ; Check object size is 256
    mov rax, [kmem_cache_file + kmem_cache_t.obj_size]
    cmp rax, 256
    jne .slab_fail_size

    ; Check alignment is 8
    mov rax, [kmem_cache_file + kmem_cache_t.align_size]
    cmp rax, 8
    jne .slab_fail_align

    ; Check list heads are 0
    mov rax, [kmem_cache_file + kmem_cache_t.slabs_full]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_file + kmem_cache_t.slabs_part]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_file + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_lists

    ; --- 2. Verify kmem_cache_task ---
    ; Check name starts with 'kmem'
    mov rax, [kmem_cache_task + kmem_cache_t.name]
    test rax, rax
    jz .slab_fail_name
    mov ebx, [rax]
    cmp ebx, 0x6D656D6B
    jne .slab_fail_name

    ; Check object size is 512
    mov rax, [kmem_cache_task + kmem_cache_t.obj_size]
    cmp rax, 512
    jne .slab_fail_size

    ; Check alignment is 16
    mov rax, [kmem_cache_task + kmem_cache_t.align_size]
    cmp rax, 16
    jne .slab_fail_align

    ; Check list heads are 0
    mov rax, [kmem_cache_task + kmem_cache_t.slabs_full]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_task + kmem_cache_t.slabs_part]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_task + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_lists

    ; --- 3. Verify kmem_cache_vma ---
    ; Check name starts with 'kmem'
    mov rax, [kmem_cache_vma + kmem_cache_t.name]
    test rax, rax
    jz .slab_fail_name
    mov ebx, [rax]
    cmp ebx, 0x6D656D6B
    jne .slab_fail_name

    ; Check object size is 64
    mov rax, [kmem_cache_vma + kmem_cache_t.obj_size]
    cmp rax, 64
    jne .slab_fail_size

    ; Check alignment is 8
    mov rax, [kmem_cache_vma + kmem_cache_t.align_size]
    cmp rax, 8
    jne .slab_fail_align

    ; Check list heads are 0
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_full]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_part]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_lists

    ; Slab Allocator Cache Definitions Test PASSED!
    mov rsi, msg_slab_test_passed
    call uart_print_str

    ; =========================================================================
    ; 10.2 Slab Lists Tracking & Grow Test
    ; =========================================================================
    mov rsi, msg_slab_grow_test_start
    call uart_print_str

    ; Grow kmem_cache_vma (size 64, align 8)
    mov rdi, kmem_cache_vma
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail

    ; R12 = pointer to grown slab
    mov r12, rax

    ; Check if the slab was linked into kmem_cache_vma.slabs_free
    mov r13, [kmem_cache_vma + kmem_cache_t.slabs_free]
    cmp r13, r12
    jne .slab_fail_free_list

    ; Verify slab magic, obj_count, and used_count
    mov rax, [r12 + slab_t.magic]
    cmp rax, 0x51AB51AB
    jne .slab_fail_magic

    mov rax, [r12 + slab_t.obj_count]
    cmp rax, 63
    jne .slab_fail_count

    mov rax, [r12 + slab_t.used_count]
    test rax, rax
    jnz .slab_fail_used

    ; Verify free_head is mem_start (slab + 56)
    mov rax, [r12 + slab_t.free_head]
    mov rbx, r12
    add rbx, 56
    cmp rax, rbx
    jne .slab_fail_free_head

    ; Verify first object points to next object (slab + 56 + 64)
    mov rcx, [rax]
    mov rdx, rbx
    add rdx, 64
    cmp rcx, rdx
    jne .slab_fail_free_chain

    ; Manually transition from slabs_free to slabs_part
    mov rdi, kmem_cache_vma
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r12
    call kmem_slab_unlink

    ; Check slabs_free is now empty (0)
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_transition

    ; Link to slabs_part
    mov rdi, kmem_cache_vma
    mov rsi, kmem_cache_t.slabs_part
    mov rdx, r12
    call kmem_slab_link

    ; Check slabs_part has the slab
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_part]
    cmp rax, r12
    jne .slab_fail_transition

    ; Verify slab's links are updated (next/prev are 0 since list is single-item)
    mov rax, [r12 + slab_t.next]
    test rax, rax
    jnz .slab_fail_transition
    mov rax, [r12 + slab_t.prev]
    test rax, rax
    jnz .slab_fail_transition

    ; Clean up: unlink from slabs_part and free back to general heap
    mov rdi, kmem_cache_vma
    mov rsi, kmem_cache_t.slabs_part
    mov rdx, r12
    call kmem_slab_unlink

    mov rdi, r12
    call heap_free

    ; Reset lists
    mov qword [kmem_cache_vma + kmem_cache_t.slabs_free], 0
    mov qword [kmem_cache_vma + kmem_cache_t.slabs_part], 0
    mov qword [kmem_cache_vma + kmem_cache_t.slabs_full], 0

    ; Slab Lists Tracking Test PASSED!
    mov rsi, msg_slab_grow_test_passed
    call uart_print_str
    jmp .run_slab_ctor_test

.slab_grow_fail:
    mov rsi, msg_slab_fail_grow_str
    call uart_print_str
    jmp .panic

.slab_fail_free_list:
    mov rsi, msg_slab_fail_free_list_str
    call uart_print_str
    jmp .panic

.slab_fail_magic:
    mov rsi, msg_slab_fail_magic_str
    call uart_print_str
    jmp .panic

.slab_fail_count:
    mov rsi, msg_slab_fail_count_str
    call uart_print_str
    jmp .panic

.slab_fail_used:
    mov rsi, msg_slab_fail_used_str
    call uart_print_str
    jmp .panic

.slab_fail_free_head:
    mov rsi, msg_slab_fail_free_head_str
    call uart_print_str
    jmp .panic

.slab_fail_free_chain:
    mov rsi, msg_slab_fail_free_chain_str
    call uart_print_str
    jmp .panic

.slab_fail_transition:
    mov rsi, msg_slab_fail_transition_str
    call uart_print_str
    jmp .panic

.slab_fail_name:
    mov rsi, msg_slab_fail_name_str
    call uart_print_str
    jmp .panic

.slab_fail_size:
    mov rsi, msg_slab_fail_size_str
    call uart_print_str
    jmp .panic

.slab_fail_align:
    mov rsi, msg_slab_fail_align_str
    call uart_print_str
    jmp .panic

.slab_fail_lists:
    mov rsi, msg_slab_fail_lists_str
    call uart_print_str
    jmp .panic

.run_slab_ctor_test:
    mov rsi, msg_slab_ctor_test_start
    call uart_print_str

    ; Create a dynamic cache for verifying constructor execution
    mov rdi, msg_test_cache_name
    mov rsi, 64                     ; obj_size = 64
    mov rdx, 8                      ; align_size = 8
    mov rcx, .test_ctor             ; ctor = .test_ctor
    mov r8, 0                       ; dtor = NULL
    call kmem_cache_create
    test rax, rax
    jz .slab_grow_fail
    mov r12, rax                    ; R12 = kmem_cache_t pointer

    ; Grow the cache via kmem_slab_grow
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r13, rax                    ; R13 = slab pointer

    ; Assert grown slab's free_head is non-null
    mov r14, [r13 + slab_t.free_head]
    test r14, r14
    jz .slab_fail_ctor

    ; Assert first object retains the constructor-initialized state at offset 8
    mov rax, 0x123456789ABCDEF0
    cmp [r14 + 8], rax
    jne .slab_fail_ctor

    ; Assert second object is also initialized correctly
    mov r15, [r14]                  ; R15 = pointer to second object
    test r15, r15
    jz .slab_fail_ctor_chain

    cmp [r15 + 8], rax
    jne .slab_fail_ctor

    ; Clean up: unlink slab from slabs_free list and free resources
    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r13
    call kmem_slab_unlink

    mov rdi, r13
    call heap_free

    mov rdi, r12
    call heap_free

    mov rsi, msg_slab_ctor_test_passed
    call uart_print_str
    jmp .run_slab_reap_test

.test_ctor:
    mov qword [rdi + 8], 0x123456789ABCDEF0
    ret

.slab_fail_ctor:
    mov rsi, msg_slab_fail_ctor_str
    call uart_print_str
    jmp .panic

.slab_fail_ctor_chain:
    mov rsi, msg_slab_fail_ctor_chain_str
    call uart_print_str
    jmp .panic

.run_slab_reap_test:
    mov rsi, msg_slab_reap_test_start
    call uart_print_str

    ; Step A: Grow an empty slab in kmem_cache_vma
    mov rdi, kmem_cache_vma
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r12, rax                    ; R12 = pointer to grown slab

    ; Verify it is in slabs_free list of kmem_cache_vma
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    cmp rax, r12
    jne .slab_reap_fail_setup

    ; Step B: Artificially configure watermarks to force kswapd trigger
    mov rax, [phys_state + phys_state_t.free_pages]
    mov r13, rax                    ; R13 = initial free pages count
    
    mov rbx, rax
    inc rbx                         ; RBX = current_free + 1
    mov [kswapd_low_watermark], rbx
    mov [kswapd_high_watermark], rbx

    ; Step C: Trigger kswapd
    call kswapd_check_and_reclaim

    ; Step D: Verify that the empty slab in kmem_cache_vma was reaped
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_reap_fail_eviction

    ; Verify that physical free pages count increased by 1 (the reaped slab/page)
    mov rax, [phys_state + phys_state_t.free_pages]
    mov rbx, r13
    inc rbx
    cmp rax, rbx
    jne .slab_reap_fail_count

    ; Step E: Reset watermarks back to 0
    mov qword [kswapd_low_watermark], 0
    mov qword [kswapd_high_watermark], 0

    ; Slab Reaping Test PASSED!
    mov rsi, msg_slab_reap_test_passed
    call uart_print_str
    jmp .run_slab_color_test

.slab_reap_fail_setup:
    mov rsi, msg_slab_reap_fail_setup_str
    call uart_print_str
    jmp .panic

.slab_reap_fail_eviction:
    mov rsi, msg_slab_reap_fail_eviction_str
    call uart_print_str
    jmp .panic

.slab_reap_fail_count:
    mov rsi, msg_slab_reap_fail_count_str
    call uart_print_str
    jmp .panic

.run_slab_color_test:
    mov rsi, msg_slab_color_test_start
    call uart_print_str

    ; Create a cache with obj_size = 256, align_size = 8
    mov rdi, msg_test_color_cache_name
    mov rsi, 256
    mov rdx, 8
    mov rcx, 0                      ; ctor = NULL
    mov r8, 0                       ; dtor = NULL
    call kmem_cache_create
    test rax, rax
    jz .slab_grow_fail
    mov r12, rax                    ; R12 = cache pointer

    ; Verify that colour_max calculation was correct (expected 3)
    mov rax, [r12 + kmem_cache_t.colour_max]
    cmp rax, 3
    jne .slab_color_fail_max

    ; Grow first slab
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r13, rax                    ; R13 = slab 1

    ; Grow second slab
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r14, rax                    ; R14 = slab 2

    ; Grow third slab
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r15, rax                    ; R15 = slab 3

    ; Calculate relative offsets of mem_start within slab pages
    mov rax, [r13 + slab_t.mem_start]
    sub rax, r13                    ; RAX = offset 1
    
    mov rbx, [r14 + slab_t.mem_start]
    sub rbx, r14                    ; RBX = offset 2
    
    mov rcx, [r15 + slab_t.mem_start]
    sub rcx, r15                    ; RCX = offset 3

    ; Assertions: offset2 should be offset1 + 64
    mov rdx, rax
    add rdx, 64
    cmp rbx, rdx
    jne .slab_color_fail_offset

    ; Assertions: offset3 should be offset1 + 128
    mov rdx, rax
    add rdx, 128
    cmp rcx, rdx
    jne .slab_color_fail_offset

    ; Clean up the dynamically grown slabs by unlinking and freeing
    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r13
    call kmem_slab_unlink
    mov rdi, r13
    call heap_free

    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r14
    call kmem_slab_unlink
    mov rdi, r14
    call heap_free

    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r15
    call kmem_slab_unlink
    mov rdi, r15
    call heap_free

    ; Free the cache descriptor itself
    mov rdi, r12
    call heap_free

    ; Slab Cache Coloring Test PASSED!
    mov rsi, msg_slab_color_test_passed
    call uart_print_str
    jmp .run_buddy_init_test

.slab_color_fail_max:
    mov rsi, msg_slab_color_fail_max_str
    call uart_print_str
    jmp .panic

.slab_color_fail_offset:
    mov rsi, msg_slab_color_fail_offset_str
    call uart_print_str
    jmp .panic

.run_buddy_init_test:
    mov rsi, msg_buddy_test_start
    call uart_print_str

    ; Step A: Allocate memory for the test buddy allocator
    ; We allocate 10MB + 8MB = 18MB (18,874,368 bytes) to allow 8MB alignment
    mov rdi, 18874368
    call heap_alloc
    test rax, rax
    jz .buddy_fail_alloc
    mov r12, rax                    ; R12 = raw heap block pointer

    ; Align the start address to 8MB boundary
    mov r13, r12
    add r13, 8388607
    mov r14, 8388607
    not r14
    and r13, r14                    ; R13 = aligned start address (A)

    ; Initialize the buddy allocator: A (R13), size = 10MB (10,485,760 bytes)
    mov rdi, r13
    mov rsi, 10485760
    call buddy_init

    ; Verify buddy configuration variables
    mov rax, [buddy_start_addr]
    cmp rax, r13
    jne .buddy_fail_config

    mov rax, [buddy_end_addr]
    mov rbx, r13
    add rbx, 10485760
    cmp rax, rbx
    jne .buddy_fail_config

    ; Verify free list heads:
    ; Expected:
    ; buddy_free_heads[11] = A (R13)
    ; buddy_free_heads[9]  = A + 8MB (R13 + 8,388,608)
    ; All other free list heads must be NULL (0).
    xor rcx, rcx                    ; RCX = order (0 to 11)
.verify_list_loop:
    cmp rcx, 12
    jae .verify_list_done

    lea rax, [buddy_free_heads]
    mov rbx, [rax + rcx * 8]        ; RBX = buddy_free_heads[RCX]

    cmp rcx, 11
    je .check_order_11
    cmp rcx, 9
    je .check_order_9

    ; For other orders, head must be NULL
    test rbx, rbx
    jnz .buddy_fail_lists
    jmp .next_verify

.check_order_11:
    cmp rbx, r13
    jne .buddy_fail_lists
    jmp .next_verify

.check_order_9:
    mov rdx, r13
    add rdx, 8388608                ; 8MB
    cmp rbx, rdx
    jne .buddy_fail_lists

.next_verify:
    inc rcx
    jmp .verify_list_loop

.verify_list_done:
    ; Verify metadata array:
    ; page count = 10MB / 4KB = 2560 pages
    ; index 0 (A) must be 0x8B (free, order 11)
    ; index 2048 (A + 8MB) must be 0x89 (free, order 9)
    mov rdx, [buddy_metadata]
    test rdx, rdx
    jz .buddy_fail_metadata

    mov al, [rdx + 0]
    cmp al, 0x8B
    jne .buddy_fail_metadata

    mov al, [rdx + 2048]
    cmp al, 0x89
    jne .buddy_fail_metadata

    ; Clean up
    mov rdi, [buddy_metadata]
    call heap_free
    mov qword [buddy_metadata], 0

    mov rdi, r12
    call heap_free

    mov qword [buddy_start_addr], 0
    mov qword [buddy_end_addr], 0
    
    lea rdi, [buddy_free_heads]
    mov rcx, 12
    xor rax, rax
    cld
    rep stosq

    ; Buddy Allocator Initialization Test PASSED!
    mov rsi, msg_buddy_test_passed
    call uart_print_str
    jmp .run_buddy_split_test

.buddy_fail_alloc:
    mov rsi, msg_buddy_fail_alloc_str
    call uart_print_str
    jmp .panic

.buddy_fail_config:
    mov rsi, msg_buddy_fail_config_str
    call uart_print_str
    jmp .panic

.buddy_fail_lists:
    mov rsi, msg_buddy_fail_lists_str
    call uart_print_str
    jmp .panic

.buddy_fail_metadata:
    mov rsi, msg_buddy_fail_metadata_str
    call uart_print_str
    jmp .panic

.run_buddy_split_test:
    mov rsi, msg_buddy_split_test_start
    call uart_print_str

    ; Step A: Allocate memory for the test buddy allocator
    ; We allocate 10MB + 8MB = 18MB to allow 8MB alignment
    mov rdi, 18874368
    call heap_alloc
    test rax, rax
    jz .buddy_fail_alloc
    mov r12, rax                    ; R12 = raw heap block pointer

    ; Align the start address to 8MB boundary (A)
    mov r13, r12
    add r13, 8388607
    mov r14, 8388607
    not r14
    and r13, r14                    ; R13 = aligned start address (A)

    ; Initialize the buddy allocator: A (R13), size = 10MB (10,485,760 bytes)
    mov rdi, r13
    mov rsi, 10485760
    call buddy_init

    ; Step B: Allocate a block of Order 8 (1MB).
    mov rdi, 8                      ; requested order = 8
    call buddy_alloc
    test rax, rax
    jz .buddy_fail_split_alloc
    mov r15, rax                    ; R15 = allocated block pointer (expected A + 8MB)

    ; Verify that the allocated pointer is exactly A + 8MB (R13 + 8MB)
    mov rdx, r13
    add rdx, 8388608                ; RDX = A + 8MB
    cmp r15, rdx
    jne .buddy_fail_split_ptr

    ; Verify list heads after split:
    ; buddy_free_heads[11] must still be A (R13)
    ; buddy_free_heads[9]  must now be NULL (0)
    ; buddy_free_heads[8]  must now be A + 9MB (R13 + 9,437,184)
    ; All other free list heads must be NULL.
    xor rcx, rcx                    ; RCX = order
.verify_split_list_loop:
    cmp rcx, 12
    jae .verify_split_list_done

    lea rax, [buddy_free_heads]
    mov rbx, [rax + rcx * 8]        ; RBX = buddy_free_heads[RCX]

    cmp rcx, 11
    je .check_split_order_11
    cmp rcx, 8
    je .check_split_order_8

    ; For other orders, head must be NULL
    test rbx, rbx
    jnz .buddy_fail_split_lists
    jmp .next_split_verify

.check_split_order_11:
    cmp rbx, r13
    jne .buddy_fail_split_lists
    jmp .next_split_verify

.check_split_order_8:
    mov rdx, r13
    add rdx, 9437184                ; A + 9MB (8MB + 1MB)
    cmp rbx, rdx
    jne .buddy_fail_split_lists

.next_split_verify:
    inc rcx
    jmp .verify_split_list_loop

.verify_split_list_done:
    ; Verify metadata array:
    ; index 2048 (A + 8MB) must be 8 (allocated, Order 8)
    ; index 2304 (A + 9MB) must be 0x88 (free, Order 8)
    ; index 0 (A) must be 0x8B (free, Order 11)
    mov rdx, [buddy_metadata]
    test rdx, rdx
    jz .buddy_fail_split_metadata

    mov al, [rdx + 2048]
    cmp al, 8
    jne .buddy_fail_split_metadata

    mov al, [rdx + 2304]
    cmp al, 0x88
    jne .buddy_fail_split_metadata

    mov al, [rdx + 0]
    cmp al, 0x8B
    jne .buddy_fail_split_metadata

    ; Buddy Allocator Splitting Test PASSED!
    mov rsi, msg_buddy_split_test_passed
    call uart_print_str
    jmp .run_buddy_coalesce_test

.buddy_fail_split_alloc:
    mov rsi, msg_buddy_fail_split_alloc_str
    call uart_print_str
    jmp .panic

.buddy_fail_split_ptr:
    mov rsi, msg_buddy_fail_split_ptr_str
    call uart_print_str
    jmp .panic

.buddy_fail_split_lists:
    mov rsi, msg_buddy_fail_split_lists_str
    call uart_print_str
    jmp .panic

.buddy_fail_split_metadata:
    mov rsi, msg_buddy_fail_split_metadata_str
    call uart_print_str
    jmp .panic

.run_buddy_coalesce_test:
    mov rsi, msg_buddy_coalesce_test_start
    call uart_print_str

    ; Step A: Free the allocated Order 8 block (R15, which is A + 8MB)
    mov rdi, r15                    ; RDI = A + 8MB
    call buddy_free

    ; Step B: Verify list heads after coalescing:
    ; buddy_free_heads[11] = A (R13)
    ; buddy_free_heads[9]  = A + 8MB (R13 + 8,388,608)
    ; buddy_free_heads[8]  = NULL (0)
    ; All other heads must be NULL.
    xor rcx, rcx                    ; RCX = order
.verify_coal_list_loop:
    cmp rcx, 12
    jae .verify_coal_list_done

    lea rax, [buddy_free_heads]
    mov rbx, [rax + rcx * 8]        ; RBX = buddy_free_heads[RCX]

    cmp rcx, 11
    je .check_coal_order_11
    cmp rcx, 9
    je .check_coal_order_9

    ; For other orders, head must be NULL
    test rbx, rbx
    jnz .buddy_fail_coal_lists
    jmp .next_coal_verify

.check_coal_order_11:
    cmp rbx, r13
    jne .buddy_fail_coal_lists
    jmp .next_coal_verify

.check_coal_order_9:
    mov rdx, r13
    add rdx, 8388608                ; A + 8MB
    cmp rbx, rdx
    jne .buddy_fail_coal_lists

.next_coal_verify:
    inc rcx
    jmp .verify_coal_list_loop

.verify_coal_list_done:
    ; Step C: Verify metadata array after coalescing:
    ; index 2048 (A + 8MB) must be 0x89 (free, Order 9)
    ; index 2304 (A + 9MB) must be 0
    ; index 0 (A) must be 0x8B (free, Order 11)
    mov rdx, [buddy_metadata]
    test rdx, rdx
    jz .buddy_fail_coal_metadata

    mov al, [rdx + 2048]
    cmp al, 0x89
    jne .buddy_fail_coal_metadata

    mov al, [rdx + 2304]
    test al, al
    jnz .buddy_fail_coal_metadata

    mov al, [rdx + 0]
    cmp al, 0x8B
    jne .buddy_fail_coal_metadata

    ; Step D: Clean up resources
    mov rdi, [buddy_metadata]
    call heap_free
    mov qword [buddy_metadata], 0

    mov rdi, r12
    call heap_free

    mov qword [buddy_start_addr], 0
    mov qword [buddy_end_addr], 0

    lea rdi, [buddy_free_heads]
    mov rcx, 12
    xor rax, rax
    cld
    rep stosq

    ; Buddy Allocator Coalescing Test PASSED!
    mov rsi, msg_buddy_coalesce_test_passed
    call uart_print_str
    jmp .run_arena_test

.buddy_fail_coal_lists:
    mov rsi, msg_buddy_fail_coal_lists_str
    call uart_print_str
    jmp .panic

.buddy_fail_coal_metadata:
    mov rsi, msg_buddy_fail_coal_metadata_str
    call uart_print_str
    jmp .panic

.run_arena_test:
    mov rsi, msg_arena_test_start
    call uart_print_str

    ; Step A: Create an Arena of 1MB (1048576 bytes)
    mov rdi, 1048576
    call arena_create
    test rax, rax
    jz .arena_fail_create
    mov r12, rax                    ; R12 = arena pointer

    ; Verify arena configuration
    ; 1. start address must be 16-byte aligned
    mov rax, [r12 + arena_t.start]
    test rax, 15
    jnz .arena_fail_align

    ; 2. current pointer must equal start address
    mov rbx, [r12 + arena_t.current]
    cmp rax, rbx
    jne .arena_fail_config

    ; 3. end address must equal arena pointer + 1MB
    mov rcx, [r12 + arena_t.end]
    mov rdx, r12
    add rdx, 1048576
    cmp rcx, rdx
    jne .arena_fail_config

    ; Step B: Allocate block A (64 bytes)
    mov rdi, r12
    mov rsi, 64
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc
    mov r13, rax                    ; R13 = allocation A (expected at start address)

    ; Verify A's alignment
    test r13, 15
    jnz .arena_fail_align

    ; Verify A points to start address
    mov rax, [r12 + arena_t.start]
    cmp r13, rax
    jne .arena_fail_ptr

    ; Step C: Allocate block B (16 bytes)
    mov rdi, r12
    mov rsi, 16
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc
    mov r14, rax                    ; R14 = allocation B

    ; Verify B's alignment
    test r14, 15
    jnz .arena_fail_align

    ; Verify B is contiguous to A (A + 64)
    mov rax, r13
    add rax, 64
    cmp r14, rax
    jne .arena_fail_spacing

    ; Step D: Allocate block C (5 bytes)
    mov rdi, r12
    mov rsi, 5
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc
    mov r15, rax                    ; R15 = allocation C

    ; Verify C's alignment (must be 16-byte aligned)
    test r15, 15
    jnz .arena_fail_align

    ; Verify C spacing: should be at B + 16 (since 5 is padded to 16)
    mov rax, r14
    add rax, 16
    cmp r15, rax
    jne .arena_fail_spacing

    ; Step E: Test Checkpoint Save/Restore
    push rbp
    mov rdi, r12
    call arena_checkpoint_save
    test rax, rax
    jz .arena_fail_checkpoint_pop
    mov rbp, rax                    ; RBP = checkpoint pointer

    ; Verify checkpoint value matches current pointer
    mov rbx, [r12 + arena_t.current]
    cmp rbp, rbx
    jne .arena_fail_checkpoint_pop

    ; Allocate block D (100 bytes)
    mov rdi, r12
    mov rsi, 100
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc_pop

    ; Restore checkpoint
    mov rdi, r12
    mov rsi, rbp
    call arena_checkpoint_restore

    ; Verify current pointer is restored to checkpoint value (RBP)
    mov rax, [r12 + arena_t.current]
    cmp rax, rbp
    jne .arena_fail_checkpoint_pop
    pop rbp

    ; Step F: Test Out Of Memory (OOM) handling
    mov rdi, r12
    mov rsi, 1048576                ; request space larger than total arena
    call arena_alloc
    test rax, rax
    jnz .arena_fail_oom             ; should return 0 (NULL)

    ; Step G: Test Arena Reset
    mov rdi, r12
    call arena_reset
    mov rax, [r12 + arena_t.current]
    mov rbx, [r12 + arena_t.start]
    cmp rax, rbx
    jne .arena_fail_reset

    ; Step H: Test Thread-Local/Core-Local Arenas (Lock-Free)
    ; 1. Initialize local arena (2MB)
    mov rdi, 2097152
    call arena_init_local
    test rax, rax
    jz .arena_fail_local_init

    ; Verify it is bound to the core (stored in [gs:24])
    mov rbx, [gs:24]
    cmp rax, rbx
    jne .arena_fail_local_init

    ; 2. Allocate 128 bytes from local arena
    mov rdi, 128
    call arena_alloc_local
    test rax, rax
    jz .arena_fail_local_alloc

    ; Verify aligned pointer
    test rax, 15
    jnz .arena_fail_align

    ; 3. Reset local arena
    call arena_reset_local
    mov rdx, [gs:24]
    mov rax, [rdx + arena_t.current]
    mov rbx, [rdx + arena_t.start]
    cmp rax, rbx
    jne .arena_fail_local_reset

    ; 4. Destroy local arena
    call arena_destroy_local
    mov rax, [gs:24]
    test rax, rax
    jnz .arena_fail_local_destroy

    ; Step I: Destroy the 1MB arena
    mov rdi, r12
    call arena_destroy

    ; Arena & Region Allocator Test PASSED!
    mov rsi, msg_arena_test_passed
    call uart_print_str
    jmp .run_pool_test

.arena_fail_checkpoint_pop:
    pop rbp
.arena_fail_checkpoint:
    mov rsi, msg_arena_fail_checkpoint_str
    call uart_print_str
    jmp .panic

.arena_fail_alloc_pop:
    pop rbp
.arena_fail_alloc:
    mov rsi, msg_arena_fail_alloc_str
    call uart_print_str
    jmp .panic

.arena_fail_create:
    mov rsi, msg_arena_fail_create_str
    call uart_print_str
    jmp .panic

.arena_fail_config:
    mov rsi, msg_arena_fail_config_str
    call uart_print_str
    jmp .panic

.arena_fail_align:
    mov rsi, msg_arena_fail_align_str
    call uart_print_str
    jmp .panic

.arena_fail_ptr:
    mov rsi, msg_arena_fail_ptr_str
    call uart_print_str
    jmp .panic

.arena_fail_spacing:
    mov rsi, msg_arena_fail_spacing_str
    call uart_print_str
    jmp .panic

.arena_fail_oom:
    mov rsi, msg_arena_fail_oom_str
    call uart_print_str
    jmp .panic

.arena_fail_reset:
    mov rsi, msg_arena_fail_reset_str
    call uart_print_str
    jmp .panic

.arena_fail_local_init:
    mov rsi, msg_arena_fail_local_init_str
    call uart_print_str
    jmp .panic

.arena_fail_local_alloc:
    mov rsi, msg_arena_fail_local_alloc_str
    call uart_print_str
    jmp .panic

.arena_fail_local_reset:
    mov rsi, msg_arena_fail_local_reset_str
    call uart_print_str
    jmp .panic

.arena_fail_local_destroy:
    mov rsi, msg_arena_fail_local_destroy_str
    call uart_print_str
    jmp .panic

.run_pool_test:
    mov rsi, msg_pool_test_start
    call uart_print_str

    ; Step A: Create a pool of object size 32 and capacity 4
    mov rdi, 32
    mov rsi, 4
    call pool_create
    test rax, rax
    jz .pool_fail_create
    mov r12, rax                    ; R12 = pool descriptor pointer

    ; Verify pool configuration
    ; 1. obj_size must be 32
    mov rax, [r12 + pool_t.obj_size]
    cmp rax, 32
    jne .pool_fail_config

    ; 2. capacity must be 4
    mov rax, [r12 + pool_t.capacity]
    cmp rax, 4
    jne .pool_fail_config

    ; 3. count must be 0
    mov rax, [r12 + pool_t.count]
    test rax, rax
    jnz .pool_fail_config

    ; 4. free_head must equal memory pointer
    mov rax, [r12 + pool_t.free_head]
    mov rbx, [r12 + pool_t.memory]
    cmp rax, rbx
    jne .pool_fail_config

    ; Step B: Allocate slot 0
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc
    mov r13, rax                    ; R13 = slot 0 (expected at pool.memory)

    ; Verify slot 0 points to start of memory
    mov rbx, [r12 + pool_t.memory]
    cmp r13, rbx
    jne .pool_fail_ptr

    ; Step C: Allocate slot 1
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc
    mov r14, rax                    ; R14 = slot 1 (expected at slot 0 + 32)

    ; Verify slot 1 is contiguous
    mov rax, r13
    add rax, 32
    cmp r14, rax
    jne .pool_fail_ptr

    ; Step D: Allocate slot 2
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc
    mov r15, rax                    ; R15 = slot 2

    ; Step E: Allocate slot 3 (use pushed rbp)
    push rbp
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc_pop
    mov rbp, rax                    ; RBP = slot 3

    ; Step F: Verify OOM (5th allocation must return NULL)
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jnz .pool_fail_oom_pop

    ; Verify used count is 4
    mov rax, [r12 + pool_t.count]
    cmp rax, 4
    jne .pool_fail_count_pop

    ; Verify generation tag value is 4 (4 allocations)
    mov rax, [r12 + pool_t.free_tag]
    cmp rax, 4
    jne .pool_fail_tag_pop

    ; Step G: Free slot 1 (R14) and slot 3 (RBP)
    mov rdi, r12
    mov rsi, r14
    call pool_free

    mov rdi, r12
    mov rsi, rbp
    call pool_free

    ; Verify used count is 2
    mov rax, [r12 + pool_t.count]
    cmp rax, 2
    jne .pool_fail_count_pop

    ; Verify generation tag value is 6 (4 allocs + 2 frees)
    mov rax, [r12 + pool_t.free_tag]
    cmp rax, 6
    jne .pool_fail_tag_pop

    ; Verify free list structure:
    ; 1. free_head must now point to slot 3 (RBP)
    mov rax, [r12 + pool_t.free_head]
    cmp rax, rbp
    jne .pool_fail_free_list_pop

    ; 2. slot 3 (RBP) must point to slot 1 (R14) in its first 8 bytes
    mov rax, [rbp]
    cmp rax, r14
    jne .pool_fail_free_list_pop

    ; 3. slot 1 (R14) must point to NULL (0)
    mov rax, [r14]
    test rax, rax
    jnz .pool_fail_free_list_pop

    ; Step H: Allocate again and verify O(1) list head reuse
    mov rdi, r12
    call pool_alloc
    cmp rax, rbp                    ; must return slot 3 (RBP) first
    jne .pool_fail_reuse_pop

    mov rdi, r12
    call pool_alloc
    cmp rax, r14                    ; must return slot 1 (R14) next
    jne .pool_fail_reuse_pop

    ; Verify used count is back to 4
    mov rax, [r12 + pool_t.count]
    cmp rax, 4
    jne .pool_fail_count_pop

    ; Verify generation tag value is 8 (4 allocs + 2 frees + 2 re-allocs)
    mov rax, [r12 + pool_t.free_tag]
    cmp rax, 8
    jne .pool_fail_tag_pop

    ; Step I: Test bounds and alignment safety checks in pool_free
    ; 1. Free out-of-bounds address (R12, the descriptor)
    mov rdi, r12
    mov rsi, r12
    call pool_free
    mov rax, [r12 + pool_t.count]
    cmp rax, 4                      ; count must remain 4 (invalid free ignored)
    jne .pool_fail_safety_pop

    ; 2. Free misaligned address
    mov rax, [r12 + pool_t.memory]
    add rax, 15                     ; not aligned to 32 bytes
    mov rdi, r12
    mov rsi, rax
    call pool_free
    mov rax, [r12 + pool_t.count]
    cmp rax, 4                      ; count must remain 4 (invalid free ignored)
    jne .pool_fail_safety_pop

    ; Step J: Test Dynamic Pool Expansion (Subfeature 13.3)
    ; We currently have 4 slots allocated (capacity = 4, count = 4, free_head = NULL).
    ; Request a 5th allocation. This must trigger pool_grow.
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_grow_alloc
    mov r8, rax                     ; R8 = 5th slot (in the new 4KB page)

    ; Verify that pool capacity grew
    ; Expected capacity = 4 + (4080 / 32) = 4 + 127 = 131
    mov rax, [r12 + pool_t.capacity]
    cmp rax, 131
    jne .pool_fail_capacity_grow

    ; Verify used count is 5
    mov rax, [r12 + pool_t.count]
    cmp rax, 5
    jne .pool_fail_count_grow

    ; Request a 6th allocation
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_grow_alloc
    mov r9, rax                     ; R9 = 6th slot

    ; Verify used count is 6
    mov rax, [r12 + pool_t.count]
    cmp rax, 6
    jne .pool_fail_count_grow

    ; Free the 5th slot (R8)
    mov rdi, r12
    mov rsi, r8
    call pool_free

    ; Free the 6th slot (R9)
    mov rdi, r12
    mov rsi, r9
    call pool_free

    ; Verify used count is back to 4
    mov rax, [r12 + pool_t.count]
    cmp rax, 4
    jne .pool_fail_count_grow

    ; Verify that freeing invalid/misaligned slots inside the grown block is ignored
    ; Let's get an address inside the grown page that is misaligned: R8 + 15
    mov rsi, r8
    add rsi, 15
    mov rdi, r12
    call pool_free
    mov rax, [r12 + pool_t.count]
    cmp rax, 4                      ; count must remain 4
    jne .pool_fail_safety_pop

    pop rbp                         ; restore RBP

    ; Step K: Clean up pool using pool_destroy
    mov rdi, r12
    call pool_destroy

    ; Pool Allocator Test PASSED!
    mov rsi, msg_pool_test_passed
    call uart_print_str
    jmp .run_memcpy_test

.run_memcpy_test:
    mov rsi, msg_memcpy_test_start
    call uart_print_str

    push r12
    push r13

    ; Allocate source buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcpy_fail_alloc
    mov r12, rax                    ; R12 = Src buffer

    ; Allocate destination buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcpy_fail_alloc
    mov r13, rax                    ; R13 = Dst buffer

    ; Populate Src buffer with 0, 1, 2, ..., 127
    xor rcx, rcx
.populate_loop:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .populate_loop

    ; Run cases
    mov rcx, 0
    call .run_one_memcpy_case
    mov rcx, 1
    call .run_one_memcpy_case
    mov rcx, 7
    call .run_one_memcpy_case
    mov rcx, 15
    call .run_one_memcpy_case
    mov rcx, 16
    call .run_one_memcpy_case
    mov rcx, 23
    call .run_one_memcpy_case
    mov rcx, 31
    call .run_one_memcpy_case
    mov rcx, 32
    call .run_one_memcpy_case
    mov rcx, 35
    call .run_one_memcpy_case
    mov rcx, 64
    call .run_one_memcpy_case
    mov rcx, 100
    call .run_one_memcpy_case

    ; Free buffers
    mov rdi, r12
    call heap_free
    mov rdi, r13
    call heap_free

    pop r13
    pop r12

    ; memcpy Test PASSED!
    mov rsi, msg_memcpy_test_passed
    call uart_print_str
    jmp .run_memset_test

.run_memset_test:
    mov rsi, msg_memset_test_start
    call uart_print_str

    push r12
    push r13

    ; Allocate destination buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memset_fail_alloc
    mov r12, rax                    ; R12 = Dst buffer

    ; Run cases with fill value 0xAA (R13 = 0xAA)
    mov r13, 0xAA

    mov rcx, 0
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 1
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 7
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 15
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 16
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 23
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 31
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 32
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 35
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 64
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 100
    mov rsi, r13
    call .run_one_memset_case

    ; Run cases with fill value 0xFF (R13 = 0xFF)
    mov r13, 0xFF

    mov rcx, 7
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 32
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 35
    mov rsi, r13
    call .run_one_memset_case

    ; Free destination buffer
    mov rdi, r12
    call heap_free

    pop r13
    pop r12

    ; memset Test PASSED!
    mov rsi, msg_memset_test_passed
    call uart_print_str
    jmp .run_memzero_test

.run_memzero_test:
    mov rsi, msg_memzero_test_start
    call uart_print_str

    push r12
    push r13

    ; Allocate destination buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memzero_fail_alloc
    mov r12, rax                    ; R12 = Dst buffer

    ; Run cases
    mov rcx, 0
    call .run_one_memzero_case
    mov rcx, 1
    call .run_one_memzero_case
    mov rcx, 7
    call .run_one_memzero_case
    mov rcx, 15
    call .run_one_memzero_case
    mov rcx, 16
    call .run_one_memzero_case
    mov rcx, 23
    call .run_one_memzero_case
    mov rcx, 31
    call .run_one_memzero_case
    mov rcx, 32
    call .run_one_memzero_case
    mov rcx, 35
    call .run_one_memzero_case
    mov rcx, 64
    call .run_one_memzero_case
    mov rcx, 100
    call .run_one_memzero_case

    ; Free destination buffer
    mov rdi, r12
    call heap_free

    pop r13
    pop r12

    ; memzero Test PASSED!
    mov rsi, msg_memzero_test_passed
    call uart_print_str
    jmp .run_memcmp_test

.run_memcmp_test:
    mov rsi, msg_memcmp_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; Allocate Buffer 1
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcmp_fail_alloc
    mov r12, rax                    ; R12 = Buffer 1

    ; Allocate Buffer 2
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcmp_fail_alloc
    mov r13, rax                    ; R13 = Buffer 2

    ; Allocate Buffer 3
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcmp_fail_alloc
    mov r14, rax                    ; R14 = Buffer 3

    ; Populate all buffers with sequence 0..127
    xor rcx, rcx
.populate_loop_memcmp:
    mov [r12 + rcx], cl
    mov [r13 + rcx], cl
    mov [r14 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .populate_loop_memcmp

    ; Test 1: Compare identical buffers (R12 and R13)
    mov rcx, 0
    call .run_match_case
    mov rcx, 1
    call .run_match_case
    mov rcx, 7
    call .run_match_case
    mov rcx, 15
    call .run_match_case
    mov rcx, 16
    call .run_match_case
    mov rcx, 23
    call .run_match_case
    mov rcx, 31
    call .run_match_case
    mov rcx, 32
    call .run_match_case
    mov rcx, 35
    call .run_match_case
    mov rcx, 64
    call .run_match_case
    mov rcx, 100
    call .run_match_case

    ; Test 2: Mismatch in first chunk (index 5)
    mov byte [r14 + 5], 99
    mov rdi, r12
    mov rsi, r14
    mov rdx, 10
    call memcmp
    cmp rax, -94                    ; 5 - 99 = -94
    jne .memcmp_fail_mismatch_val

    mov rdi, r14
    mov rsi, r12
    mov rdx, 10
    call memcmp
    cmp rax, 94                     ; 99 - 5 = 94
    jne .memcmp_fail_mismatch_val
    mov byte [r14 + 5], 5           ; restore

    ; Test 3: Mismatch in second chunk (index 45)
    mov byte [r14 + 45], 2
    mov rdi, r12
    mov rsi, r14
    mov rdx, 50
    call memcmp
    cmp rax, 43                     ; 45 - 2 = 43
    jne .memcmp_fail_mismatch_val
    mov byte [r14 + 45], 45         ; restore

    ; Test 4: Mismatch in sub-32 remainder (index 75)
    mov byte [r14 + 75], 0
    mov rdi, r12
    mov rsi, r14
    mov rdx, 100
    call memcmp
    cmp rax, 75                     ; 75 - 0 = 75
    jne .memcmp_fail_mismatch_val
    mov byte [r14 + 75], 75         ; restore

    ; Test 5: Mismatch outside compared range (index 50 with size 10)
    mov byte [r14 + 50], 99
    mov rdi, r12
    mov rsi, r14
    mov rdx, 10
    call memcmp
    test rax, rax                   ; must be 0 (identical in first 10 bytes)
    jnz .memcmp_fail_mismatch_val
    mov byte [r14 + 50], 50         ; restore

    ; Free all buffers
    mov rdi, r12
    call heap_free
    mov rdi, r13
    call heap_free
    mov rdi, r14
    call heap_free

    pop r14
    pop r13
    pop r12

    ; memcmp Test PASSED!
    mov rsi, msg_memcmp_test_passed
    call uart_print_str
    jmp .run_memmove_test

.run_memmove_test:
    mov rsi, msg_memmove_test_start
    call uart_print_str

    push r12

    ; Allocate Buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memmove_fail_alloc
    mov r12, rax                    ; R12 = working buffer

    ; -------------------------------------------------------------------------
    ; Test Case A: Forward copy, non-overlapping
    ; -------------------------------------------------------------------------
    ; Reset buffer
    xor rcx, rcx
.reset_a:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .reset_a

    mov rdi, r12
    add rdi, 64                     ; RDI = dest = R12 + 64
    mov rsi, r12                    ; RSI = src = R12 + 0
    mov rdx, 32                     ; RDX = size = 32
    call memmove

    ; Verify return value
    mov rbx, r12
    add rbx, 64
    cmp rax, rbx
    jne .memmove_fail_ret

    ; Verify payload at dest
    xor rcx, rcx
.verify_a:
    mov al, [r12 + 64 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 32
    jb .verify_a

    ; -------------------------------------------------------------------------
    ; Test Case B: Reverse copy, overlapping (Dest > Src)
    ; -------------------------------------------------------------------------
    ; Reset buffer
    xor rcx, rcx
.reset_b:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .reset_b

    mov rdi, r12
    add rdi, 30                     ; RDI = dest = R12 + 30
    mov rsi, r12
    add rsi, 10                     ; RSI = src = R12 + 10
    mov rdx, 40                     ; RDX = size = 40 (overlapping)
    call memmove

    ; Verify return value
    mov rbx, r12
    add rbx, 30
    cmp rax, rbx
    jne .memmove_fail_ret

    ; Verify unchanged range [0..29]
    xor rcx, rcx
.verify_b_pre:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 30
    jb .verify_b_pre

    ; Verify moved payload [30..69] from [10..49]
    xor rcx, rcx
.verify_b_payload:
    mov al, [r12 + 30 + rcx]
    mov r8b, cl
    add r8b, 10
    cmp al, r8b
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 40
    jb .verify_b_payload

    ; Verify unchanged range [70..127]
    mov rcx, 70
.verify_b_post:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 128
    jb .verify_b_post

    ; -------------------------------------------------------------------------
    ; Test Case C: Forward copy, overlapping (Dest < Src)
    ; -------------------------------------------------------------------------
    ; Reset buffer
    xor rcx, rcx
.reset_c:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .reset_c

    mov rdi, r12
    add rdi, 10                     ; RDI = dest = R12 + 10
    mov rsi, r12
    add rsi, 30                     ; RSI = src = R12 + 30
    mov rdx, 40                     ; RDX = size = 40 (overlapping)
    call memmove

    ; Verify return value
    mov rbx, r12
    add rbx, 10
    cmp rax, rbx
    jne .memmove_fail_ret

    ; Verify unchanged range [0..9]
    xor rcx, rcx
.verify_c_pre:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 10
    jb .verify_c_pre

    ; Verify moved payload [10..49] from [30..69]
    xor rcx, rcx
.verify_c_payload:
    mov al, [r12 + 10 + rcx]
    mov r8b, cl
    add r8b, 30
    cmp al, r8b
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 40
    jb .verify_c_payload

    ; Verify unchanged range [50..127]
    mov rcx, 50
.verify_c_post:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 128
    jb .verify_c_post

    ; Free buffer
    mov rdi, r12
    call heap_free

    pop r12

    ; memmove Test PASSED!
    mov rsi, msg_memmove_test_passed
    call uart_print_str
    jmp .run_numa_test

.run_numa_test:
    mov rsi, msg_numa_test_start
    call uart_print_str

    ; 1. Verify range count is > 0
    mov rax, [numa_range_count]
    test rax, rax
    jz .numa_fail_count

    ; Print ranges
    mov rsi, msg_numa_ranges_found
    call uart_print_str

    push r12
    push r13
    push r14

    xor r12, r12                    ; r12 = index i = 0
.loop_print:
    mov rcx, [numa_range_count]
    cmp r12, rcx
    jae .done_print

    mov rax, r12
    imul rax, numa_range_t_size
    lea r13, [numa_ranges + rax]

    ; Print base
    mov rsi, msg_numa_range_base
    call uart_print_str
    mov rax, [r13 + numa_range_t.base]
    call uart_print_hex64

    ; Print length
    mov rsi, msg_numa_range_len
    call uart_print_str
    mov rax, [r13 + numa_range_t.length]
    call uart_print_hex64

    ; Print Node ID
    mov rsi, msg_numa_range_node
    call uart_print_str
    movzx rax, dword [r13 + numa_range_t.node_id]
    call uart_print_hex64

    mov rsi, msg_crlf
    call uart_print_str

    inc r12
    jmp .loop_print

.done_print:
    ; 2. Test address translation API: numa_get_node_by_phys
    ; Query address 0 (should return first node, usually Node 0)
    xor rdi, rdi
    call numa_get_node_by_phys
    ; We just verify it returns a valid node ID (rax should be a node ID like 0 or 1, etc.)
    ; We can also check that query beyond max memory defaults to Node 0.
    mov rdi, [phys_state + phys_state_t.max_phys_addr]
    add rdi, 0x1000                 ; just past max physical RAM
    call numa_get_node_by_phys
    test rax, rax
    jnz .numa_fail_lookup_pop       ; should fall back to 0 for out-of-bounds/unmapped addresses

    ; 3. Print numa_node_count
    mov rsi, msg_numa_node_count
    call uart_print_str
    mov rax, [numa_node_count]
    call uart_print_dec
    mov rsi, msg_crlf
    call uart_print_str

    ; 4. Print relative distance matrix
    mov rsi, msg_numa_matrix_header
    call uart_print_str

    xor r12, r12                    ; r12 = node_from = 0
.loop_node_from:
    mov rcx, [numa_node_count]
    cmp r12, rcx
    jae .done_matrix_print

    xor r13, r13                    ; r13 = node_to = 0
.loop_node_to:
    mov rcx, [numa_node_count]
    cmp r13, rcx
    jae .next_node_from

    ; Print "  Node "
    mov rsi, msg_numa_node_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_dec
    ; Print " -> "
    mov rsi, msg_numa_node_arrow
    call uart_print_str
    mov rax, r13
    call uart_print_dec
    ; Print ": "
    mov rsi, msg_numa_node_colon
    call uart_print_str

    ; Call numa_get_distance
    mov rdi, r12
    mov rsi, r13
    call numa_get_distance          ; RAX = distance
    call uart_print_dec
    
    mov rsi, msg_crlf
    call uart_print_str

    inc r13
    jmp .loop_node_to

.next_node_from:
    inc r12
    jmp .loop_node_from

.done_matrix_print:
    ; 5. Verify numa_get_distance bounds checking by querying invalid nodes and checking for 255.
    ; Case A: node_from >= count
    mov rdi, [numa_node_count]
    xor rsi, rsi
    call numa_get_distance
    cmp rax, 255
    jne .numa_fail_distance_pop

    ; Case B: node_to >= count
    xor rdi, rdi
    mov rsi, [numa_node_count]
    call numa_get_distance
    cmp rax, 255
    jne .numa_fail_distance_pop

    ; Case C: very large node ID (99)
    mov rdi, 99
    xor rsi, rsi
    call numa_get_distance
    cmp rax, 255
    jne .numa_fail_distance_pop

    ; 6. Verify Node-Local Bitmaps Active
    mov rax, [numa_local_bitmaps_active]
    test rax, rax
    jz .numa_fail_bitmaps_init_pop

    ; 7. Print Node-Local Bitmap Info
    mov rsi, msg_numa_local_info_header
    call uart_print_str

    xor r12, r12                    ; r12 = index J = 0
.loop_node_info:
    mov rcx, [numa_node_count]
    cmp r12, rcx
    jae .test_numa_allocation

    ; Print "  Node "
    mov rsi, msg_numa_node_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_dec

    ; Print " Bitmap: Base=0x"
    mov rsi, msg_numa_node_bmp_base
    call uart_print_str

    mov rax, r12
    imul rax, numa_node_t_size
    lea r13, [numa_nodes + rax]     ; R13 = node descriptor pointer

    mov rax, [r13 + numa_node_t.bitmap_addr]
    call uart_print_hex64

    ; Print " Size=0x"
    mov rsi, msg_numa_node_bmp_size
    call uart_print_str
    mov rax, [r13 + numa_node_t.bitmap_size]
    call uart_print_hex64

    ; Print " FreePages="
    mov rsi, msg_numa_node_bmp_free
    call uart_print_str
    mov rax, [r13 + numa_node_t.free_pages]
    call uart_print_dec

    mov rsi, msg_crlf
    call uart_print_str

    inc r12
    jmp .loop_node_info

.test_numa_allocation:
    ; 8. Test allocate page from Node 0
    xor rdi, rdi                    ; target node 0
    call phys_alloc_page_node
    test rax, rax
    jz .numa_fail_alloc_node_pop
    mov r14, rax                    ; save allocated address in R14

    ; Verify node affinity of returned address
    mov rdi, r14
    call numa_get_node_by_phys      ; RAX = Node ID
    test rax, rax
    jnz .numa_fail_node_affinity_pop

    ; Free the page
    mov rdi, r14
    call phys_free_page

    ; 9. Test fallback lookup for invalid node (99)
    mov rdi, 99
    call phys_alloc_page_node
    test rax, rax
    jz .numa_fail_fallback_alloc_pop
    mov r14, rax

    ; Free fallback page
    mov rdi, r14
    call phys_free_page

    ; 10. Test fallback under simulated Node 0 memory exhaustion
    mov rax, [numa_node_count]
    cmp rax, 1
    jbe .numa_sim_oom_done

    mov rsi, msg_numa_sim_oom_start
    call uart_print_str

    ; Save Node 0's end_page
    mov rax, [numa_nodes + numa_node_t.end_page]
    push rax

    ; Simulate Node 0 exhaustion: set Node 0's end_page equal to its start_page
    mov rcx, [numa_nodes + numa_node_t.start_page]
    mov [numa_nodes + numa_node_t.end_page], rcx

    ; Allocate from Node 0 (should fail on Node 0 and fallback to Node 1)
    xor rdi, rdi                    ; requested node 0
    call phys_alloc_page_node
    test rax, rax
    jz .numa_fail_sim_oom_alloc_pop

    mov r14, rax                    ; save allocated address in R14

    ; Verify node affinity of returned address: should be Node 1
    mov rdi, r14
    call numa_get_node_by_phys      ; RAX = Node ID
    cmp rax, 1
    jne .numa_fail_sim_oom_affinity_pop

    ; Free the page
    mov rdi, r14
    call phys_free_page

    ; Restore Node 0's end_page
    pop rax
    mov [numa_nodes + numa_node_t.end_page], rax

    mov rsi, msg_numa_sim_oom_ok
    call uart_print_str

.numa_sim_oom_done:
    pop r14
    pop r13
    pop r12

    ; NUMA Test PASSED!
    mov rsi, msg_numa_test_passed
    call uart_print_str
    jmp .smep_smap_test

.smep_smap_test:
    ; -------------------------------------------------------------
    ; SMEP/SMAP Protection Test
    ; -------------------------------------------------------------
    mov rsi, msg_smep_smap_test_start
    call uart_print_str

    ; 1. Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .smep_smap_fail_alloc
    mov r12, rax                    ; R12 = user page physical address

    ; 2. Create a VMA for user space test address
    ; start=0x40000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER (0x0B)
    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .smep_smap_fail_vma
    mov r13, rax                    ; R13 = VMA pointer

    ; 3. Map user space address
    mov rdi, 0x40000000
    mov rsi, r12
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .smep_smap_fail_map

    ; 4. Test copy_to_user
    mov rdi, 0x40000000             ; user destination
    mov rsi, msg_smep_smap_test_data ; kernel source
    mov rdx, 20                     ; length of msg_smep_smap_test_data ("SMAP_TEST_SIGNATURE" + null = 20)
    call copy_to_user
    test rax, rax
    jz .smep_smap_fail_copy_to

    ; 5. Test copy_from_user
    mov rdi, smep_smap_test_buf     ; kernel destination buffer
    mov rsi, 0x40000000             ; user source
    mov rdx, 20
    call copy_from_user
    test rax, rax
    jz .smep_smap_fail_copy_from

    ; 6. Verify data integrity
    mov rsi, smep_smap_test_buf
    mov rdi, msg_smep_smap_test_data
    mov rdx, 20
    call memcmp
    test rax, rax
    jnz .smep_smap_fail_data

    ; Clean up
    mov rdi, 0x40000000
    call virt_unmap

    mov rdi, r12
    call phys_free_page

    mov rdi, r13
    call vma_destroy

    ; SMEP/SMAP Test PASSED!
    mov rsi, msg_smep_smap_test_passed
    call uart_print_str

    jmp .zero_on_free_test

.zero_on_free_test:
    ; -------------------------------------------------------------
    ; Zero on Free Test
    ; -------------------------------------------------------------
    mov rsi, msg_zof_test_start
    call uart_print_str

    ; --- 1. Test Heap Allocator Zeroing ---
    mov rdi, 64
    call heap_alloc                 ; RAX = allocated pointer
    test rax, rax
    jz .zof_fail_heap_alloc
    mov r12, rax                    ; R12 = heap block pointer

    ; Write signature to the block
    mov qword [r12], 0x123456789ABCDEF0
    mov qword [r12 + 8], 0x123456789ABCDEF0
    mov qword [r12 + 16], 0x123456789ABCDEF0
    mov qword [r12 + 24], 0x123456789ABCDEF0

    ; Free the block
    mov rdi, r12
    call heap_free

    ; Verify that the payload is zeroed out
    cmp qword [r12], 0
    jne .zof_fail_heap_zero
    cmp qword [r12 + 8], 0
    jne .zof_fail_heap_zero
    cmp qword [r12 + 16], 0
    jne .zof_fail_heap_zero
    cmp qword [r12 + 24], 0
    jne .zof_fail_heap_zero

    ; --- 2. Test Physical Page Allocator Zeroing ---
    call phys_alloc_page            ; RAX = physical page address
    test rax, rax
    jz .zof_fail_phys_alloc
    mov r13, rax                    ; R13 = physical page address

    ; Write signature
    mov qword [r13], 0xDEADBEEFCAFEBAB1
    mov qword [r13 + 4088], 0xDEADBEEFCAFEBAB2

    ; Free page
    mov rdi, r13
    call phys_free_page

    ; Verify zeroed
    cmp qword [r13], 0
    jne .zof_fail_phys_zero
    cmp qword [r13 + 4088], 0
    jne .zof_fail_phys_zero

    ; VMM Zeroing on Free Tests PASSED!
    mov rsi, msg_zof_test_passed
    call uart_print_str

    jmp .mmap_test_start

    ; =========================================================================
    ; Memory-Mapped Files (mmap) Tests (Section 17)
    ; =========================================================================
.mmap_test_start:
    mov rsi, msg_mmap_test_start
    call uart_print_str

    ; 1. Create a mock file with size 8192 (2 pages)
    mov rdi, 8192
    call mock_file_create
    test rax, rax
    jz .mmap_fail_create
    mov r12, rax                    ; R12 = file_ptr (mock_file_t)

    ; 2. Map the file to virtual address 0x80000000 with VMA_READ | VMA_WRITE
    mov rdi, 0x80000000
    mov rsi, 8192                   ; 2 pages
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    mov r8, r12                     ; file_ptr
    mov r9, 0                       ; file offset 0
    call vma_map_file
    test rax, rax
    jz .mmap_fail_map

    ; 3. Access virtual address to trigger demand paging load (Read test)
    ; Virtual address: 0x80000000.
    ; This triggers a #PF, loads from mock storage, maps, and resumes execution.
    mov rsi, 0x80000000
    mov rax, [rsi]
    cmp rax, 0x4154544154544154     ; Compare first 8 bytes: "TATTVA_M"
    jne .mmap_fail_read_val

    ; Check offset value at 0x80000020 (decimal 32)
    mov rax, [rsi + 32]
    cmp rax, 0                      ; offset should be 0
    jne .mmap_fail_read_offset

    ; 4. Write data to the memory-mapped file (Write test)
    ; This sets the PAGE_DIRTY bit in the PTE.
    mov qword [rsi], 0xDEADBEEFCAFEBABE
    mov qword [rsi + 32], 0x1234567890ABCDEF

    ; 5. Verify the dirty bit is set in the PTE
    mov rdi, 0x80000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .mmap_fail_pte
    mov rcx, [rax]
    test rcx, 0x40                  ; PAGE_DIRTY (bit 6)
    jz .mmap_fail_dirty             ; If not set, error

    ; 6. Synchronize dirty pages back to mock storage via mmap_msync
    mov rdi, 0x80000000
    mov rsi, 8192
    call mmap_msync
    test rax, rax
    jz .mmap_fail_sync

    ; 7. Verify that the dirty bit is now cleared in the PTE
    mov rdi, 0x80000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .mmap_fail_pte
    mov rcx, [rax]
    test rcx, 0x40                  ; PAGE_DIRTY should be cleared
    jnz .mmap_fail_not_cleared

    ; 8. Verify the backing mock file blocks actually contain the synchronized data
    mov rbx, [r12 + mock_file_t.blocks + 0] ; First block physical page address
    test rbx, rbx
    jz .mmap_fail_backing

    mov rax, [rbx]
    cmp rax, 0xDEADBEEFCAFEBABE
    jne .mmap_fail_backing_data
    mov rax, [rbx + 32]
    cmp rax, 0x1234567890ABCDEF
    jne .mmap_fail_backing_data

    ; 9. Unmap the range via mmap_munmap
    mov rdi, 0x80000000
    mov rsi, 8192
    call mmap_munmap
    test rax, rax
    jz .mmap_fail_unmap

    ; 10. Destroy the mock file structure
    mov rdi, r12
    call mock_file_destroy

    jmp .ipc_test_start

    ; =========================================================================
    ; Shared Memory & IPC Primitives Tests (Section 18)
    ; =========================================================================
.ipc_test_start:
    mov rsi, msg_ipc_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 1. Test Shared Physical Frames (Subfeature 18.1)
    ; -------------------------------------------------------------------------
    ; Create a secondary User PML4
    xor rdi, rdi                    ; 0 = read current CR3
    call virt_create_user_pml4
    test rax, rax
    jz .ipc_fail_pml4
    mov r12, rax                    ; R12 = secondary PML4 physical address

    ; Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .ipc_fail_alloc
    mov r13, rax                    ; R13 = physical page

    ; Map it to 0x90000000 in current address space (CR3) with present & writable flags
    mov rdi, 0x90000000
    mov rsi, r13
    mov rdx, 0x03                   ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .ipc_fail_map

    ; Write test signature to 0x90000000
    mov rdi, 0x90000000
    mov rax, 0x5348415245445f4d     ; "SHARED_M"
    mov [rdi], rax
    mov rax, 0x454d4f52595f4f4b     ; "EMORY_OK"
    mov [rdi + 8], rax

    ; Share this page with the secondary PML4 at destination address 0x90000000
    mov rdi, 0x90000000             ; vaddr_src
    mov rsi, r12                    ; pml4_dest
    mov rdx, 0x90000000             ; vaddr_dest
    mov rcx, 0x03                   ; flags (PAGE_PRESENT | PAGE_WRITABLE)
    call ipc_share_frame
    test rax, rax
    jz .ipc_fail_share

    ; Temporarily switch CR3 to secondary PML4 to verify mapping
    mov r14, cr3                    ; R14 = original CR3
    mov cr3, r12                    ; switch to secondary PML4

    ; Verify that 0x90000000 is readable and contains our signature
    mov rdi, 0x90000000
    mov rax, [rdi]
    cmp rax, 0x5348415245445f4d     ; "SHARED_M"
    jne .ipc_fail_shared_val
    mov rax, [rdi + 8]
    cmp rax, 0x454d4f52595f4f4b     ; "EMORY_OK"
    jne .ipc_fail_shared_val

    ; Switch back to original CR3
    mov cr3, r14

    ; Clean up the shared page from both address spaces
    mov rdi, 0x90000000
    call virt_unmap
    
    ; Switch to secondary PML4 to unmap it there as well
    mov cr3, r12
    mov rdi, 0x90000000
    call virt_unmap
    mov cr3, r14                    ; restore original CR3

    ; Free the physical page frame
    mov rdi, r13
    call phys_free_page

    ; Free the secondary PML4 physical page itself
    mov rdi, r12
    call phys_free_page

    ; -------------------------------------------------------------------------
    ; 2. Test Zero-Copy Ring Buffers (Subfeature 18.2)
    ; -------------------------------------------------------------------------
    ; Create a double-mapped ring buffer at 0xA0000000 of size 4096 (total 8192 bytes mapped)
    mov rdi, 0xA0000000
    mov rsi, 4096                   ; size N = 4096 (1 page)
    mov rdx, 0x03                   ; VMA flags (VMA_READ | VMA_WRITE)
    call ipc_create_ring_buffer
    test rax, rax
    jz .ipc_fail_ring_create

    ; Write test data at the beginning of the first half (0xA0000000)
    mov rdi, 0xA0000000
    mov rax, 0x52494e475f425546     ; "RING_BUF"
    mov [rdi], rax
    mov rax, 0x4645525f444f5542     ; "FER_DOUB"
    mov [rdi + 8], rax
    mov rax, 0x4c455f4d41505f21     ; "LE_MAP_!"
    mov [rdi + 16], rax

    ; Read back from the second half at 0xA0001000 (offset 4096) and verify it's identical
    mov rsi, 0xA0001000
    mov rax, [rsi]
    cmp rax, 0x52494e475f425546
    jne .ipc_fail_ring_val
    mov rax, [rsi + 8]
    cmp rax, 0x4645525f444f5542
    jne .ipc_fail_ring_val
    mov rax, [rsi + 16]
    cmp rax, 0x4c455f4d41505f21
    jne .ipc_fail_ring_val

    ; Write a value at offset 32 in the second half (0xA0001020)
    mov qword [rsi + 32], 0x90ABCDEFAABBCCDD

    ; Read it back from the first half at 0xA0000020 and verify it matches
    mov rax, [rdi + 32]
    cmp rax, 0x90ABCDEFAABBCCDD
    jne .ipc_fail_ring_cross_val

    ; Clean up the ring buffer
    mov rdi, 0xA0000000
    mov rsi, 4096
    call ipc_destroy_ring_buffer

    ; VMM Shared Memory & IPC Tests PASSED!
    mov rsi, msg_ipc_test_passed
    call uart_print_str

    jmp .leak_test_start

    ; =========================================================================
    ; Memory Leak Tracker Tests (Subfeature 19.1)
    ; =========================================================================
.leak_test_start:
    mov rsi, msg_leak_test_start
    call uart_print_str

    ; 1. Reset/Initialize leak tracker
    call leak_tracker_init

    ; 2. Run report, verify RAX = 0 leaks initially
    call heap_leak_report
    cmp rax, 0
    jne .leak_fail_initial

    ; 3. Allocate two memory blocks
    mov rdi, 128
    call heap_alloc                 ; RAX = block 1
    test rax, rax
    jz .leak_fail_alloc
    mov r12, rax                    ; R12 = block 1 pointer

    mov rdi, 256
    call heap_alloc                 ; RAX = block 2
    test rax, rax
    jz .leak_fail_alloc
    mov r13, rax                    ; R13 = block 2 pointer

    ; 4. Free block 1
    mov rdi, r12
    call heap_free

    ; 5. Run leak report, verify RAX = 1 leak is detected
    call heap_leak_report
    cmp rax, 1
    jne .leak_fail_count

    ; Verify that block 2 address in our leak table matches r13
    ; Each leak_entry_t is 24 bytes (0=.ptr, 8=.size, 16=.caller)
    lea rbx, [leak_table]
    xor rcx, rcx
    xor rdx, rdx                    ; RDX = count of active leak pointers matched
.verify_loop_leak:
    cmp rcx, 512                    ; LEAK_MAX_ENTRIES
    jge .verify_done_leak
    imul rsi, rcx, 24
    mov rax, [rbx + rsi + 0]   ; offset 0 is .ptr
    test rax, rax
    jz .next_verify_leak
    cmp rax, r13
    jne .next_verify_leak
    inc rdx                         ; found block 2!
.next_verify_leak:
    inc rcx
    jmp .verify_loop_leak

.verify_done_leak:
    cmp rdx, 1
    jne .leak_fail_verify

    ; 6. Free block 2
    mov rdi, r13
    call heap_free

    ; 7. Run leak report, verify RAX = 0 leaks
    call heap_leak_report
    cmp rax, 0
    jne .leak_fail_final

    ; =========================================================================
    ; Hardware Transactional Memory (TSX) Fault Handling Test (Subfeature 25.1)
    ; =========================================================================
    jmp .tsx_test_start

.tsx_test_start:
    mov rsi, msg_tsx_test_start
    call uart_print_str

    ; Step A: Create a VMA for TSX demand paging test
    ; start=0x80000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x80000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .tsx_test_fail_vma

    ; Step B: Set current thread to index 0 (Thread 100)
    mov qword [current_thread_idx], 0

    ; Step C: Enter TSX transaction (Success Case)
    ; Fallback path is .tsx_success_fallback
    lea rdi, [.tsx_success_transaction]
    lea rsi, [.tsx_success_fallback]
    call tsx_begin

.tsx_success_transaction:
    ; Access the demand-paging address. This should trigger a page fault!
    ; Since it's inside TSX, the fault handler will resolve it and redirect RIP to .tsx_success_transaction.
    ; On the retry, the access will succeed without a fault!
    mov rdi, 0x80000000
    mov byte [rdi], 0xAA

    ; Commit transaction
    call tsx_end

    ; Verify data was written correctly
    mov al, [0x80000000]
    cmp al, 0xAA
    jne .tsx_test_fail_data

    mov rsi, msg_tsx_success_ok
    call uart_print_str
    jmp .tsx_run_abort_case

.tsx_success_fallback:
    ; We should not reach here in the success case
    mov rsi, msg_tsx_fail_success_fallback
    call uart_print_str
    jmp .panic

.tsx_run_abort_case:
    ; Step D: Enter TSX transaction (Abort Fallback Case)
    ; We access an unmapped address 0x90000000 (no VMA).
    ; This should abort the transaction and redirect RIP to the fallback handler .tsx_abort_fallback.
    lea rdi, [.tsx_abort_transaction]
    lea rsi, [.tsx_abort_fallback]
    call tsx_begin

.tsx_abort_transaction:
    mov rdi, 0x90000000
    mov al, [rdi]                   ; Unresolvable page fault!

    ; We should never reach here because the handler redirects RIP to fallback
    mov rsi, msg_tsx_fail_no_abort
    call uart_print_str
    jmp .panic

.tsx_abort_fallback:
    ; This is the expected path for the abort case!
    mov rsi, msg_tsx_abort_ok
    call uart_print_str

    ; Clean up the TSX VMA
    mov rdi, 0x80000000
    call virt_translate
    mov r14, rax                    ; physical address

    mov rdi, 0x80000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    ; TSX Test PASSED!
    mov rsi, msg_tsx_test_passed
    call uart_print_str

    ; =========================================================================
    ; TSX Speculative Directory Walk Engine Test (Subfeature 25.2)
    ; =========================================================================
.tsx_spec_walk_test_start:
    mov rsi, msg_tsx_spec_walk_test_start
    call uart_print_str

    ; 1. Initialise the transaction log
    call tsx_log_init

    ; 2. Create a VMA for our test address (0x85000000)
    ; start=0x85000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x85000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .tsx_spec_walk_fail_vma
    mov r12, rax                    ; R12 = VMA pointer

    ; 3. Cache flush
    call trans_cache_flush

    ; 4. Log the test address (not yet present/mapped in page tables)
    mov rdi, 0x85000000
    call tsx_log_address

    ; 5. Verify that it is NOT in the cache before walk
    mov rdi, 0x85000000
    call trans_cache_lookup
    test rax, rax
    jnz .tsx_spec_walk_fail_initial_cache

    ; 6. Run the speculative walk engine. It should read the log, see 0x85000000 is not present,
    ; speculatively map it (via virt_page_fault_handler), and load it into the translation cache.
    call tsx_spec_walk_engine

    ; 7. Verify that 0x85000000 IS now present in the cache and lookup returns its physical address
    mov rdi, 0x85000000
    call trans_cache_lookup         ; RAX = physical address
    test rax, rax
    jz .tsx_spec_walk_fail_lookup

    ; Let's translate it normally to verify the physical address matches
    mov r14, rax                    ; R14 = cached physical address
    mov rdi, 0x85000000
    call virt_translate             ; RAX = translated physical address
    cmp rax, r14
    jne .tsx_spec_walk_fail_mismatch

    ; 8. Clean up
    mov rdi, 0x85000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r12
    call vma_destroy

    ; 9. Invalidate entry and verify it is gone from cache
    mov rdi, 0x85000000
    call trans_cache_invalidate
    mov rdi, 0x85000000
    call trans_cache_lookup
    test rax, rax
    jnz .tsx_spec_walk_fail_invalidate

    mov rsi, msg_tsx_spec_walk_test_passed
    call uart_print_str

    ; =========================================================================
    ; TSX Lock-Free Directory Updates (Lock Elision) Test (Subfeature 25.3)
    ; =========================================================================
.tsx_lock_test_start:
    mov rsi, msg_tsx_lock_test_start
    call uart_print_str

    ; Step A: Verify Speculative lock-free directory update (Bypass mutex)
    ; 1. Set current thread to index 0 (TSX enabled)
    mov qword [current_thread_idx], 0

    ; 2. Calculate lock address to check
    ; Virtual address = 0xA0000000. PML4 index = (0xA0000000 >> 39) & 0x1FF = 0.
    ; So it uses pgtable_locks + 0.
    lea r12, [pgtable_locks]        ; R12 = &pgtable_locks[0]
    mov byte [r12], 0               ; Make sure it is unlocked

    ; 3. Call pgtable_lock_acquire
    mov rdi, 0xA0000000
    call pgtable_lock_acquire

    ; 4. Check results: tsx_active should be 1, but the lock byte MUST remain 0! (lock elision)
    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 1
    jne .tsx_lock_fail_active
    
    mov cl, [r12]
    cmp cl, 0
    jne .tsx_lock_fail_bypass

    mov rsi, msg_tsx_lock_bypass_ok
    call uart_print_str

    ; 5. Call pgtable_lock_release
    mov rdi, 0xA0000000
    call pgtable_lock_release

    ; 6. Check results: tsx_active should return to 0, and the lock byte should remain 0
    call sched_get_current_thread
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 0
    jne .tsx_lock_fail_release_active
    
    mov cl, [r12]
    cmp cl, 0
    jne .tsx_lock_fail_release_lock

    ; Step B: Verify Traditional lock fallback (when TSX disabled)
    ; 1. Set current thread to 99 (invalid/inactive) to disable TSX
    mov qword [current_thread_idx], 99

    ; 2. Call pgtable_lock_acquire
    mov rdi, 0xA0000000
    call pgtable_lock_acquire

    ; 3. Check results: lock byte MUST be 1 (traditional lock acquired!)
    mov cl, [r12]
    cmp cl, 1
    jne .tsx_lock_fail_traditional

    mov rsi, msg_tsx_lock_traditional_ok
    call uart_print_str

    ; 4. Call pgtable_lock_release
    mov rdi, 0xA0000000
    call pgtable_lock_release

    ; 5. Check results: lock byte should be cleared back to 0
    mov cl, [r12]
    cmp cl, 0
    jne .tsx_lock_fail_traditional_release

    ; Lock-Free Directory Updates Test PASSED!
    mov rsi, msg_tsx_lock_test_passed
    call uart_print_str

    jmp .hle_test_start

    ; =========================================================================
    ; Hardware Lock Elision (HLE) Protection Test (Subfeature 25.4)
    ; =========================================================================
.hle_test_start:
    mov rsi, msg_hle_test_start
    call uart_print_str

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .hle_fail_alloc
    mov r12, rax                    ; R12 = physical page

    ; 2. Map page to virtual address 0xC0000000 with cache disabled & write-through flags
    ; Flags: PAGE_PRESENT (1) | PAGE_WRITABLE (2) | PAGE_PWT (8) | PAGE_PCD (16) = 27 = 0x1B
    mov rdi, 0xC0000000
    mov rsi, r12
    mov rdx, 0x1B
    call virt_map
    test rax, rax
    jz .hle_fail_map

    ; 3. Verify page is mapped and has PWT and PCD set
    mov rdi, 0xC0000000
    mov rsi, 0                      ; current CR3
    call virt_walk_table            ; RAX = physical address of PTE
    test rax, rax
    jz .hle_fail_walk1

    mov rcx, [rax]
    test rcx, 0x18                  ; 0x18 = PAGE_PWT | PAGE_PCD
    jz .hle_fail_flags1             ; failure if either flag is missing

    ; 4. Call hle_protect_range to clear caching flags (enforcing WB caching)
    mov rdi, 0xC0000000
    mov rsi, 4096                   ; 1 page
    call hle_protect_range

    ; 5. Verify page table entry has PWT and PCD cleared to 0 (Write-Back)
    mov rdi, 0xC0000000
    mov rsi, 0                      ; current CR3
    call virt_walk_table            ; RAX = physical address of PTE
    test rax, rax
    jz .hle_fail_walk2

    mov rcx, [rax]
    test rcx, 0x18                  ; 0x18 = PAGE_PWT | PAGE_PCD
    jnz .hle_fail_flags2            ; failure if flags are still set

    ; 6. Clean up mapping
    mov rdi, 0xC0000000
    call virt_unmap

    mov rdi, r12
    call phys_free_page

    ; 7. Test cache line alignment checker (hle_is_cache_aligned)
    ; Aligned address (multiple of 64): 0x1000
    mov rdi, 0x1000
    call hle_is_cache_aligned
    cmp rax, 1
    jne .hle_fail_align1

    ; Unaligned address: 0x1005
    mov rdi, 0x1005
    call hle_is_cache_aligned
    cmp rax, 0
    jne .hle_fail_align2

    ; HLE Protection & Caching Test PASSED!
    mov rsi, msg_hle_test_passed
    call uart_print_str

    jmp .tsx_fallback_lock_test_start

    ; =========================================================================
    ; TSX Fallback Page-Directory Lock Manager Test (Subfeature 25.5)
    ; =========================================================================
.tsx_fallback_lock_test_start:
    mov rsi, msg_tsx_fallback_lock_test_start
    call uart_print_str

    ; 1. Set current thread to index 0 (TSX enabled)
    mov qword [current_thread_idx], 0

    ; 2. Initialize lock PML4 index 10 (address = 10 << 39)
    mov r14, 10
    shl r14, 39                     ; R14 = test virtual address

    ; Reset lock and abort count
    lea rbx, [pgtable_locks]
    mov byte [rbx + 10], 0
    lea rbx, [pgtable_lock_abort_counts]
    mov byte [rbx + 10], 0

    ; 3. Verify initial acquire uses TSX (speculative block)
    mov rdi, r14
    call pgtable_lock_acquire

    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 1
    jne .tsx_fallback_lock_fail_init_active

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_init_lock

    ; Release it
    mov rdi, r14
    call pgtable_lock_release

    ; 4. Manually set abort count to 3 (simulating exceeding limits)
    lea rbx, [pgtable_lock_abort_counts]
    mov byte [rbx + 10], 3

    ; 5. Call pgtable_lock_acquire. It should bypass TSX and use traditional lock!
    mov rdi, r14
    call pgtable_lock_acquire

    ; Verify: tsx_active should be 0, and the lock byte MUST be 1
    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 0
    jne .tsx_fallback_lock_fail_bypass_active

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 1
    jne .tsx_fallback_lock_fail_bypass_lock

    mov rsi, msg_tsx_fallback_lock_limit_ok
    call uart_print_str

    ; 6. Call pgtable_lock_release.
    ; It should traditionally release the lock, decay the abort count to 2, and clear the lock byte to 0.
    mov rdi, r14
    call pgtable_lock_release

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_decay_lock

    lea rbx, [pgtable_lock_abort_counts]
    mov cl, [rbx + 10]
    cmp cl, 2
    jne .tsx_fallback_lock_fail_decay_count

    mov rsi, msg_tsx_fallback_lock_decay_ok
    call uart_print_str

    ; 7. Call pgtable_lock_acquire again. Since count is 2 (which is < 3), it should try TSX again!
    mov rdi, r14
    call pgtable_lock_acquire

    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 1
    jne .tsx_fallback_lock_fail_retry_active

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_retry_lock

    ; 8. Call pgtable_lock_release. It should reset the abort count to 0.
    mov rdi, r14
    call pgtable_lock_release

    lea rbx, [pgtable_lock_abort_counts]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_final_count

    ; TSX Fallback Lock Manager Tests PASSED!
    mov rsi, msg_tsx_fallback_lock_test_passed
    call uart_print_str

    jmp .aslr_test_start

    ; =========================================================================
    ; ASLR Symbol Offset Randomization Test (Subfeature 26.1)
    ; =========================================================================
.aslr_test_start:
    mov rsi, msg_aslr_test_start
    call uart_print_str

    ; 1. Allocate block A (64 bytes)
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .aslr_fail_alloc
    mov r12, rax                    ; R12 = pointer A (offsetted)

    ; 2. Allocate block B (64 bytes)
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .aslr_fail_alloc
    mov r13, rax                    ; R13 = pointer B (offsetted)

    ; 3. Verify alignment of pointers
    test r12, 15
    jnz .aslr_fail_align
    test r13, 15
    jnz .aslr_fail_align

    ; 4. Retrieve gap sizes
    mov r14, [r12 - 8]              ; R14 = gap size A
    mov r15, [r13 - 8]              ; R15 = gap size B

    ; 5. Verify gap A is in range [16, 256] and is a multiple of 16
    cmp r14, 16
    jl .aslr_fail_bounds
    cmp r14, 256
    jg .aslr_fail_bounds
    test r14, 15
    jnz .aslr_fail_bounds

    ; 6. Verify gap B is in range [16, 256] and is a multiple of 16
    cmp r15, 16
    jl .aslr_fail_bounds
    cmp r15, 256
    jg .aslr_fail_bounds
    test r15, 15
    jnz .aslr_fail_bounds

    ; 7. Free allocations
    mov rdi, r12
    call heap_free
    mov rdi, r13
    call heap_free

    ; ASLR Symbol Offset Randomization Test PASSED!
    mov rsi, msg_aslr_test_passed
    call uart_print_str

    jmp .shuffling_test_start

    ; =========================================================================
    ; Virtual Page Table Shuffling Test (Subfeature 26.4)
    ; =========================================================================
.shuffling_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_shuffling_test_start
    call uart_print_str

    ; 1. Verify that logical index 1 is mapped to a different physical index
    lea rbx, [pml4_shuffle_map]
    movzx r12, word [rbx + 1 * 2]   ; R12 = physical PML4 index for logical index 1
    
    ; Verify that the mapping is randomized (R12 != 1)
    cmp r12, 1
    je .shuffling_fail_identity

    mov rsi, msg_shuffling_index_ok
    call uart_print_str

    ; 2. Allocate a physical page for mapping
    call phys_alloc_page
    test rax, rax
    jz .shuffling_fail_alloc
    mov r13, rax                    ; R13 = physical page

    ; 3. Map page at logical virtual address 0x8000000000 (logical index 1)
    mov rdi, 0x8000000000
    mov rsi, r13
    mov rdx, PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .shuffling_fail_map

    ; 4. Get physical virtual address
    mov rdi, 0x8000000000
    call virt_logical_to_physical_vaddr
    mov r14, rax                    ; R14 = physical virtual address

    ; Verify that physical virtual address PML4 index matches R12
    mov rax, r14
    shr rax, 39
    and rax, 0x1FF                  ; RAX = physical PML4 index
    cmp rax, r12
    jne .shuffling_fail_phys_vaddr

    ; 5. Access (write) using physical virtual address
    mov r15, 0x1122334455667788
    mov [r14], r15

    ; 6. Read back and verify the value
    mov rax, [r14]
    cmp rax, r15
    jne .shuffling_fail_data

    mov rsi, msg_shuffling_access_ok
    call uart_print_str

    ; 7. Walk table using logical address 0x8000000000 and verify it translates successfully
    mov rdi, 0x8000000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .shuffling_fail_walk

    ; Verify physical address matches R13
    mov rax, [rax]
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = mapped physical frame
    cmp rax, r13
    jne .shuffling_fail_walk_phys

    ; 8. Clean up
    mov rdi, 0x8000000000
    call virt_unmap
    
    mov rdi, r13
    call phys_free_page

    ; Virtual Page Table Shuffling Test PASSED!
    mov rsi, msg_shuffling_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .decoy_test_start

.shuffling_fail_identity:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_identity_str
    call uart_print_str
    jmp .panic

.shuffling_fail_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_alloc_str
    call uart_print_str
    jmp .panic

.shuffling_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_map_str
    call uart_print_str
    jmp .panic

.shuffling_fail_phys_vaddr:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_phys_vaddr_str
    call uart_print_str
    jmp .panic

.shuffling_fail_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_data_str
    call uart_print_str
    jmp .panic

.shuffling_fail_walk:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_walk_str
    call uart_print_str
    jmp .panic

.shuffling_fail_walk_phys:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_shuffling_fail_walk_phys_str
    call uart_print_str
    jmp .panic

    ; =========================================================================
    ; Decoy Memory Pages Test (Subfeature 26.3)
    ; =========================================================================
.decoy_test_start:
    push r12
    push r13
    push r14

    mov rsi, msg_decoy_test_start
    call uart_print_str

    ; 1. Map decoy page at 0x90000000 with PAGE_PRESENT | PAGE_USER
    mov rdi, 0x90000000
    mov rdx, PAGE_PRESENT | PAGE_USER
    call virt_map_decoy
    test rax, rax
    jz .decoy_fail_map

    ; 2. Walk the page table to verify the mapping
    mov rdi, 0x90000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .decoy_fail_walk

    mov rbx, [rax]                  ; rbx = PTE value
    
    ; Verify PAGE_PRESENT is 1
    test rbx, PAGE_PRESENT
    jz .decoy_fail_pte_present
    
    ; Verify PAGE_NX is 0 (executable)
    mov rcx, PAGE_NX
    test rbx, rcx
    jnz .decoy_fail_pte_nx
    
    ; Verify it points to decoy_page_phys
    mov rcx, [decoy_page_phys]
    and rbx, 0xFFFFFFFFFFFFF000     ; mask off flags
    cmp rbx, rcx
    jne .decoy_fail_pte_phys

    mov rsi, msg_decoy_pte_verify_ok
    call uart_print_str

    ; 3. Execute function call to decoy page (should slide and return RET 0xC3)
    mov rax, 0x90000000
    call rax                        ; executes the slide and returns safely!

    mov rsi, msg_decoy_call_ok
    call uart_print_str

    ; 4. Clean up the mapping
    mov rdi, 0x90000000
    call virt_unmap

    ; Decoy Memory Pages Test PASSED!
    mov rsi, msg_decoy_test_passed
    call uart_print_str

    pop r14
    pop r13
    pop r12
    jmp .temporal_test_start

.temporal_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_temporal_test_start
    call uart_print_str

    ; 1. Initialize temporal obfuscation (maps code page at 0x500000000)
    call virt_temporal_obfuscation_init
    test rax, rax
    jz .temporal_fail_init

    ; 2. Read initial address V_init
    mov r12, [temporal_code_vaddr]  ; R12 = V_init

    ; Verify V_init can be called successfully
    call r12

    ; 3. Run tick 5 times to trigger migration
    mov rcx, 5
.tick_loop:
    push rcx
    call virt_temporal_obfuscation_tick
    pop rcx
    dec rcx
    jnz .tick_loop

    ; 4. Read new address V_new
    mov r13, [temporal_code_vaddr]  ; R13 = V_new

    ; Verify that V_new is different from V_init
    cmp r13, r12
    je .temporal_fail_not_moved

    ; 5. Verify V_new can be executed successfully
    call r13

    ; 6. Verify that V_init is no longer present in page table
    mov rdi, r12
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jnz .temporal_fail_still_present

    ; 7. Clean up V_new mapping (unmap and free backing page)
    mov rdi, r13
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .temporal_fail_walk_new
    mov r14, [rax]
    and r14, 0xFFFFFFFFFFFFF000     ; R14 = backing physical frame

    mov rdi, r13
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    ; Temporal Layout Obfuscation Test PASSED!
    mov rsi, msg_temporal_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .stack_offset_test_start

.stack_offset_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_stack_offset_test_start
    call uart_print_str

    ; 1. Allocate stack A
    mov rdi, 16384                  ; 16KB size
    call thread_stack_alloc
    test rax, rax
    jz .stack_offset_fail_alloc
    mov r12, rax                    ; R12 = stack top A (offsetted)

    ; 2. Allocate stack B
    mov rdi, 16384                  ; 16KB size
    call thread_stack_alloc
    test rax, rax
    jz .stack_offset_fail_alloc
    mov r13, rax                    ; R13 = stack top B (offsetted)

    ; 3. Verify alignment (must be 16-byte aligned)
    test r12, 15
    jnz .stack_offset_fail_align
    test r13, 15
    jnz .stack_offset_fail_align

    ; 4. Find VMAs to get actual ends
    mov rdi, r12
    call vma_find
    test rax, rax
    jz .stack_offset_fail_vma
    mov r14, [rax + vma_t.end]      ; R14 = original stack top A

    mov rdi, r13
    call vma_find
    test rax, rax
    jz .stack_offset_fail_vma
    mov r15, [rax + vma_t.end]      ; R15 = original stack top B

    ; Calculate offsets: offset = original_top - top_offsetted
    sub r14, r12                    ; R14 = offset A
    sub r15, r13                    ; R15 = offset B

    ; Verify offsets are in range 0..240 and multiples of 16
    cmp r14, 0
    jl .stack_offset_fail_bounds
    cmp r14, 240
    jg .stack_offset_fail_bounds
    test r14, 15
    jnz .stack_offset_fail_bounds

    cmp r15, 0
    jl .stack_offset_fail_bounds
    cmp r15, 240
    jg .stack_offset_fail_bounds
    test r15, 15
    jnz .stack_offset_fail_bounds

    ; 5. Free both stacks
    mov rdi, r12
    mov rsi, 16384
    call thread_stack_free

    mov rdi, r13
    mov rsi, 16384
    call thread_stack_free

    ; Test PASSED!
    mov rsi, msg_stack_offset_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .dax_test_start

.dax_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_dax_test_start
    call uart_print_str

    ; 1. Create an 8KB mock file
    mov rdi, 8192
    call mock_file_create
    test rax, rax
    jz .dax_fail_create
    mov r12, rax                    ; R12 = mock_file pointer

    ; 2. Map the file range using vma_map_dax at virtual address 0xE0000000 (size 8192, flags VMA_READ | VMA_WRITE)
    mov rdi, 0xE0000000
    mov rsi, 8192
    mov rdx, 3                      ; VMA_READ | VMA_WRITE
    mov r8, r12                     ; mock_file
    mov r9, 0                       ; offset 0
    call vma_map_dax
    test rax, rax
    jz .dax_fail_map
    mov r13, rax                    ; R13 = VMA pointer

    ; 3. Access (write) magic value to 0xE0000000 (triggers page fault)
    mov rdi, 0xE0000000
    mov rbx, 0xAA55AA55BB66BB66
    mov [rdi], rbx

    ; 4. Verify that backing block 0 contains the magic value immediately
    mov r14, [r12 + 8]              ; R14 = mock_file->blocks[0]
    test r14, r14
    jz .dax_fail_backing
    mov rax, [r14]
    mov rbx, 0xAA55AA55BB66BB66
    cmp rax, rbx
    jne .dax_fail_data

    ; 5. Access (write) second magic value to 0xE0001000 (triggers page fault on page 1)
    mov rdi, 0xE0001000
    mov rbx, 0xCC77CC77DD88DD88
    mov [rdi], rbx

    ; Verify backing block 1 contains the second magic value immediately
    mov r15, [r12 + 16]             ; R15 = mock_file->blocks[1]
    test r15, r15
    jz .dax_fail_backing
    mov rax, [r15]
    mov rbx, 0xCC77CC77DD88DD88
    cmp rax, rbx
    jne .dax_fail_data

    ; 6. Unmap the range using mmap_munmap
    mov rdi, 0xE0000000
    mov rsi, 8192
    call mmap_munmap
    test rax, rax
    jz .dax_fail_unmap

    ; 7. Verify that backing blocks are not freed and still contain correct magic values
    mov rax, [r12 + 8]
    cmp rax, r14
    jne .dax_fail_unmap_freed
    mov rax, [r12 + 16]
    cmp rax, r15
    jne .dax_fail_unmap_freed

    mov rax, [r14]
    mov rbx, 0xAA55AA55BB66BB66
    cmp rax, rbx
    jne .dax_fail_unmap_data

    mov rax, [r15]
    mov rbx, 0xCC77CC77DD88DD88
    cmp rax, rbx
    jne .dax_fail_unmap_data

    ; 8. Destroy mock file to release blocks
    mov rdi, r12
    call mock_file_destroy

    ; DAX Block Mapping Tests PASSED!
    mov rsi, msg_dax_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .pmem_test_start

.pmem_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_pmem_test_start
    call uart_print_str

    ; 1. Allocate a physical page to act as the NVDIMM physical storage block
    call phys_alloc_page
    test rax, rax
    jz .pmem_fail_alloc
    mov r12, rax                    ; R12 = physical page address of mock NVDIMM

    ; 2. Setup the global nvdimm_dev descriptor
    mov rdi, nvdimm_dev
    mov [rdi], r12                  ; nvdimm_dev.phys_base = R12
    mov qword [rdi + 8], 4096       ; nvdimm_dev.size = 4096 (1 page)

    ; 3. Map the persistent memory range using vma_map_pmem at virtual address 0xF0000000 (flags VMA_READ | VMA_WRITE)
    mov rdi, 0xF0000000
    mov rsi, 4096
    mov rdx, 3                      ; VMA_READ | VMA_WRITE
    mov r8, nvdimm_dev              ; pointer to nvdimm_dev descriptor
    mov r9, 0                       ; offset 0
    call vma_map_pmem
    test rax, rax
    jz .pmem_fail_map
    mov r13, rax                    ; R13 = VMA pointer

    ; 4. Access (write) magic value to 0xF0000000 (triggers page fault)
    mov rdi, 0xF0000000
    mov rbx, 0x55AA55AA66BB66BB
    mov [rdi], rbx

    ; 5. Verify that the NVDIMM backing physical block contains the magic value immediately
    mov rax, [r12]                  ; R12 is the identity-mapped physical page of NVDIMM
    mov rbx, 0x55AA55AA66BB66BB
    cmp rax, rbx
    jne .pmem_fail_data

    ; 6. Unmap the range using mmap_munmap
    mov rdi, 0xF0000000
    mov rsi, 4096
    call mmap_munmap
    test rax, rax
    jz .pmem_fail_unmap

    ; 7. Verify that the backing block is not cleared or released after unmap (still holds the magic value)
    mov rax, [r12]
    mov rbx, 0x55AA55AA66BB66BB
    cmp rax, rbx
    jne .pmem_fail_unmap_data

    ; 8. Clean up the physical page (reclaim it manually as we bypassed munmap release)
    mov rdi, r12
    call phys_free_page

    ; PMEM Byte-Addressability Tests PASSED!
    mov rsi, msg_pmem_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .window_test_start

.window_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_window_test_start
    call uart_print_str

    ; 1. Allocate heap memory for pmem_window_t descriptor
    mov rdi, pmem_window_t_size
    extern heap_alloc
    call heap_alloc
    test rax, rax
    jz .window_fail_alloc_desc
    mov r12, rax                    ; R12 = pointer to pmem_window_t

    ; 2. Initialize the pmem hardware window
    mov rdi, r12
    call pmem_window_init
    test qword [r12 + pmem_window_t.data_page], 0
    jz .window_fail_init

    ; 3. Map the static hardware data page using vma_map_pmem_window at 0xFA000000
    mov rdi, 0xFA000000
    mov rsi, 4096                   ; 1 page size
    mov rdx, 3                      ; VMA_READ | VMA_WRITE
    mov r8, r12                     ; pointer to pmem_window_t
    call vma_map_pmem_window
    test rax, rax
    jz .window_fail_map
    mov r13, rax                    ; R13 = VMA pointer

    ; 4. Select block index 5
    mov rdi, r12
    mov rsi, 5
    call pmem_window_select_block

    ; 5. Access (read) the window at 0xFA000000 to verify default block 5 signature load (triggers page fault)
    mov rdi, 0xFA000000
    mov rax, [rdi]                  ; TATTVA_P
    mov rbx, 0x505f415654544154
    cmp rax, rbx
    jne .window_fail_sig

    ; Verify block index written at offset 32
    mov rax, [rdi + 32]
    cmp rax, 5
    jne .window_fail_sig

    ; 6. Modify the memory in the window: write magic value 0x1122334455667788 to 0xFA000000
    mov rbx, 0x1122334455667788
    mov [rdi], rbx

    ; 7. Select block index 8 (this should flush block 5 changes to backing block 5, and load block 8)
    mov rdi, r12
    mov rsi, 8
    call pmem_window_select_block

    ; Verify static window data page now contains block 8 signature
    mov rdi, 0xFA000000
    mov rax, [rdi]
    mov rbx, 0x505f415654544154
    cmp rax, rbx
    jne .window_fail_sig
    mov rax, [rdi + 32]
    cmp rax, 8
    jne .window_fail_sig

    ; 8. Verify that backing block 5 physical page contains the modified magic value
    mov r14, [r12 + pmem_window_t.pmem_array + 5 * 8] ; R14 = backing block 5 address
    test r14, r14
    jz .window_fail_backing
    mov rax, [r14]
    mov rbx, 0x1122334455667788
    cmp rax, rbx
    jne .window_fail_backing_data

    ; 9. Unmap the window range
    mov rdi, 0xFA000000
    mov rsi, 4096
    call mmap_munmap
    test rax, rax
    jz .window_fail_unmap

    ; 10. Clean up: free physical backing page 5, the static data page, and the heap descriptor
    mov rdi, r14
    call phys_free_page

    mov rdi, [r12 + pmem_window_t.data_page]
    call phys_free_page

    mov rdi, r12
    extern heap_free
    call heap_free

    ; NVDIMM Block Window Mapping Tests PASSED!
    mov rsi, msg_window_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .bypass_test_start

.bypass_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_bypass_test_start
    call uart_print_str

    ; 1. Allocate source physical page
    call phys_alloc_page
    test rax, rax
    jz .bypass_fail_alloc
    mov r12, rax                    ; R12 = source physical page

    ; 2. Allocate destination physical page
    call phys_alloc_page
    test rax, rax
    jz .bypass_fail_alloc_dest
    mov r13, rax                    ; R13 = dest physical page

    ; 3. Map pages into virtual address space
    mov rdi, 0x80000000
    mov rsi, r12
    mov rdx, 3                      ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .bypass_fail_map

    mov rdi, 0x80001000
    mov rsi, r13
    mov rdx, 3                      ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .bypass_fail_map

    ; 4. Fill source page with pattern "TATTVA_BYPASS_CACHE_TEST_PATTERN_"
    mov rdi, 0x80000000
    mov rcx, 128                    ; 128 * 32 bytes = 4096 bytes
.fill_loop:
    mov rax, 0x425f415654544154     ; "TATTVA_B"
    mov [rdi], rax
    mov rax, 0x41435f5353415059     ; "YPASS_CA"
    mov [rdi + 8], rax
    mov rax, 0x545345545f454843     ; "CHE_TEST"
    mov [rdi + 16], rax
    mov rax, 0x4e5245545441505f     ; "_PATTERN"
    mov [rdi + 24], rax
    add rdi, 32
    dec rcx
    jnz .fill_loop

    ; 5. Copy using cache-bypassing copy (aligned to 4096)
    mov rdi, 0x80001000
    mov rsi, 0x80000000
    mov rdx, 4096
    call pmem_memcpy_nt

    ; 6. Verify destination contains identical pattern immediately
    mov rdi, 0x80001000
    mov rcx, 128
.verify_loop_bypass:
    mov rax, [rdi]
    mov rbx, 0x425f415654544154
    cmp rax, rbx
    jne .bypass_fail_data
    mov rax, [rdi + 8]
    mov rbx, 0x41435f5353415059
    cmp rax, rbx
    jne .bypass_fail_data
    mov rax, [rdi + 16]
    mov rbx, 0x545345545f454843
    cmp rax, rbx
    jne .bypass_fail_data
    mov rax, [rdi + 24]
    mov rbx, 0x4e5245545441505f
    cmp rax, rbx
    jne .bypass_fail_data
    add rdi, 32
    dec rcx
    jnz .verify_loop_bypass

    ; --- Unaligned pointer test subcase ---
    ; Re-initialize source page with sentinel bytes (0..255)
    mov rdi, 0x80000000
    xor rcx, rcx
.fill_unaligned_src:
    mov [rdi + rcx], cl
    inc rcx
    cmp rcx, 512
    jb .fill_unaligned_src

    ; Re-initialize destination page with 0xFF
    mov rdi, 0x80001000
    mov rcx, 512
    mov al, 0xFF
    rep stosb

    ; Copy 200 bytes from Src + 3 to Dest + 7
    mov rdi, 0x80001000 + 7
    mov rsi, 0x80000000 + 3
    mov rdx, 200
    call pmem_memcpy_nt

    ; Verify destination bytes [7 .. 206] match source bytes [3 .. 202]
    mov rdi, 0x80001000
    xor rcx, rcx
.verify_unaligned:
    cmp rcx, 7
    jb .check_ff
    cmp rcx, 207
    jae .check_ff

    ; In-range check: Dest[rcx] should be Src[rcx - 7 + 3] = rcx - 4
    mov al, [rdi + rcx]
    mov r8, rcx
    sub r8, 4
    cmp al, r8b
    jne .bypass_fail_data
    jmp .next_verify_bypass

.check_ff:
    ; Out-of-range check: Dest[rcx] should be 0xFF
    mov al, [rdi + rcx]
    cmp al, 0xFF
    jne .bypass_fail_data

.next_verify_bypass:
    inc rcx
    cmp rcx, 512
    jb .verify_unaligned

    ; 7. Clean up mappings
    mov rdi, 0x80000000
    mov rsi, 4096
    call virt_unmap

    mov rdi, 0x80001000
    mov rsi, 4096
    call virt_unmap

    ; 8. Free backing pages
    mov rdi, r12
    call phys_free_page

    mov rdi, r13
    call phys_free_page

    ; VMM PMEM Direct Write Cache Bypass Tests PASSED!
    mov rsi, msg_bypass_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .barrier_test_start

.barrier_test_start:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_barrier_test_start
    call uart_print_str

    ; 1. Allocate a physical page for testing
    call phys_alloc_page
    test rax, rax
    jz .barrier_fail_alloc
    mov r12, rax                    ; R12 = physical page address

    ; 2. Map page to 0x80002000
    mov rdi, 0x80002000
    mov rsi, r12
    mov rdx, 3                      ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .barrier_fail_map

    ; 3. Fill page with signature data
    mov rdi, 0x80002000
    mov rcx, 512
    mov rax, 0x1122334455667788
.fill_loop_barrier:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .fill_loop_barrier

    ; 4. Flush cache lines using pmem_flush_range
    mov rdi, 0x80002000             ; RDI = start address
    mov rsi, 4096                   ; RSI = size (1 page)
    call pmem_flush_range

    ; 5. Verify that data remains intact immediately
    mov rdi, 0x80002000
    mov rcx, 512
.verify_loop_barrier:
    mov rax, [rdi]
    mov rbx, 0x1122334455667788
    cmp rax, rbx
    jne .barrier_fail_data
    add rdi, 8
    dec rcx
    jnz .verify_loop_barrier

    ; --- Part 2: Unaligned offset flush test ---
    ; Set a single cache line to a different value and flush it with unaligned offset
    mov rdi, 0x80002000 + 100
    mov rax, 0x9988776655443322
    mov [rdi], rax

    mov rdi, 0x80002000 + 100
    mov rsi, 8                      ; 8 bytes flush
    call pmem_flush_range

    ; Verify data remains intact
    mov rax, [rdi]
    mov rbx, 0x9988776655443322
    cmp rax, rbx
    jne .barrier_fail_data

    ; 6. Unmap virtual address space
    mov rdi, 0x80002000
    mov rsi, 4096
    call virt_unmap

    ; 7. Free physical page
    mov rdi, r12
    call phys_free_page

    ; VMM PMEM Hardware Metadata Barrier Flushing Tests PASSED!
    mov rsi, msg_barrier_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .xo_test_start

.barrier_fail_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_barrier_fail_alloc_str
    call uart_print_str
    jmp .panic

.barrier_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_barrier_fail_map_str
    call uart_print_str
    jmp .panic

.barrier_fail_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_barrier_fail_data_str
    call uart_print_str
    jmp .panic


.window_fail_alloc_desc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_alloc_desc_str
    call uart_print_str
    jmp .panic

.window_fail_init:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_init_str
    call uart_print_str
    jmp .panic

.window_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_map_str
    call uart_print_str
    jmp .panic

.window_fail_sig:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_sig_str
    call uart_print_str
    jmp .panic

.window_fail_backing:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_backing_str
    call uart_print_str
    jmp .panic

.window_fail_backing_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_backing_data_str
    call uart_print_str
    jmp .panic

.window_fail_unmap:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_window_fail_unmap_str
    call uart_print_str
    jmp .panic

.bypass_fail_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_bypass_fail_alloc_str
    call uart_print_str
    jmp .panic

.bypass_fail_alloc_dest:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_bypass_fail_alloc_dest_str
    call uart_print_str
    jmp .panic

.bypass_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_bypass_fail_map_str
    call uart_print_str
    jmp .panic

.bypass_fail_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_bypass_fail_data_str
    call uart_print_str
    jmp .panic

.pmem_fail_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_pmem_fail_alloc_str
    call uart_print_str
    jmp .panic

.pmem_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_pmem_fail_map_str
    call uart_print_str
    jmp .panic

.pmem_fail_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_pmem_fail_data_str
    call uart_print_str
    jmp .panic

.pmem_fail_unmap:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_pmem_fail_unmap_str
    call uart_print_str
    jmp .panic

.pmem_fail_unmap_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_pmem_fail_unmap_data_str
    call uart_print_str
    jmp .panic

.dax_fail_create:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_create_str
    call uart_print_str
    jmp .panic

.dax_fail_map:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_map_str
    call uart_print_str
    jmp .panic

.dax_fail_backing:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_backing_str
    call uart_print_str
    jmp .panic

.dax_fail_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_data_str
    call uart_print_str
    jmp .panic

.dax_fail_unmap:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_unmap_str
    call uart_print_str
    jmp .panic

.dax_fail_unmap_freed:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_unmap_freed_str
    call uart_print_str
    jmp .panic

.dax_fail_unmap_data:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_dax_fail_unmap_data_str
    call uart_print_str
    jmp .panic

.stack_offset_fail_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_stack_offset_fail_alloc_str
    call uart_print_str
    jmp .panic

.stack_offset_fail_align:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_stack_offset_fail_align_str
    call uart_print_str
    jmp .panic

.stack_offset_fail_vma:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_stack_offset_fail_vma_str
    call uart_print_str
    jmp .panic

.stack_offset_fail_bounds:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_stack_offset_fail_bounds_str
    call uart_print_str
    jmp .panic

.temporal_fail_init:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_temporal_fail_init_str
    call uart_print_str
    jmp .panic

.temporal_fail_not_moved:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_temporal_fail_not_moved_str
    call uart_print_str
    jmp .panic

.temporal_fail_still_present:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_temporal_fail_still_present_str
    call uart_print_str
    jmp .panic

.temporal_fail_walk_new:
    pop r15
    pop r14
    pop r13
    pop r12
    mov rsi, msg_temporal_fail_walk_new_str
    call uart_print_str
    jmp .panic

.decoy_fail_map:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_decoy_fail_map_str
    call uart_print_str
    jmp .panic

.decoy_fail_walk:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_decoy_fail_walk_str
    call uart_print_str
    jmp .panic

.decoy_fail_pte_present:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_decoy_fail_pte_present_str
    call uart_print_str
    jmp .panic

.decoy_fail_pte_nx:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_decoy_fail_pte_nx_str
    call uart_print_str
    jmp .panic

.decoy_fail_pte_phys:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_decoy_fail_pte_phys_str
    call uart_print_str
    jmp .panic

    ; =========================================================================
    ; Execute-Only (XO) Pages Security Test (Subfeature 26.2)
    ; =========================================================================
.xo_test_start:
    push r12
    mov rsi, msg_xo_test_start
    call uart_print_str

    ; Check CPUID for PKU support (CPUID.07H.0H:EBX.PKU [bit 3])
    push rbx
    push rcx
    push rdx
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, (1 << 3)
    pop rdx
    pop rcx
    pop rbx
    jz .xo_test_fallback_path

    ; --- Hardware PKU Path ---
    mov rsi, msg_xo_pku_supported
    call uart_print_str

    ; Enable CR4.PKE and program PKRU
    mov rax, cr4
    or rax, (1 << 22)
    mov cr4, rax

    xor ecx, ecx
    rdpkru
    or eax, 0x0C                    ; AD1=1, WD1=1
    and eax, ~0x03                  ; Key 0 fully accessible
    xor edx, edx
    wrpkru

    ; Allocate a physical page for mapping
    call phys_alloc_page
    test rax, rax
    jz .xo_fail_alloc
    mov r12, rax                    ; R12 = physical page

    ; Map page at 0xA0000000 with PAGE_XO
    mov rdi, 0xA0000000
    mov rsi, r12
    mov rdx, PAGE_XO
    call virt_map
    test rax, rax
    jz .xo_fail_map

    ; Walk page table to verify PTE
    mov rdi, 0xA0000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .xo_fail_walk

    mov rbx, [rax]
    ; Verify PAGE_PRESENT = 1
    test rbx, PAGE_PRESENT
    jz .xo_fail_pte_present
    ; Verify PAGE_KEY_1 is set
    mov rcx, PAGE_KEY_1
    test rbx, rcx
    jz .xo_fail_pte_key
    ; Verify PAGE_NX is 0
    mov rcx, PAGE_NX
    test rbx, rcx
    jnz .xo_fail_pte_nx

    mov rsi, msg_xo_pte_verify_ok
    call uart_print_str

    ; Attempt read from 0xA0000000 -> should panic and halt
    mov rdi, 0xA0000000
    mov rax, [rdi]

    ; If we reach here, the protection check failed!
    jmp .xo_fail_trap

.xo_test_fallback_path:
    ; --- Software Fallback Path ---
    mov rsi, msg_xo_pku_unsupported
    call uart_print_str

    ; Allocate a physical page for mapping
    call phys_alloc_page
    test rax, rax
    jz .xo_fail_alloc
    mov r12, rax

    ; Map page at 0xA0000000 with PAGE_XO
    mov rdi, 0xA0000000
    mov rsi, r12
    mov rdx, PAGE_XO
    call virt_map
    test rax, rax
    jz .xo_fail_map

    ; Walk page table to verify PTE
    mov rdi, 0xA0000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .xo_fail_walk

    mov rbx, [rax]
    ; Verify PAGE_PRESENT = 0
    test rbx, PAGE_PRESENT
    jnz .xo_fail_pte_absent
    ; Verify PAGE_XO is set
    test rbx, PAGE_XO
    jz .xo_fail_pte_xo

    mov rsi, msg_xo_pte_verify_ok
    call uart_print_str

    ; Attempt read from 0xA0000000 -> should panic and halt
    mov rdi, 0xA0000000
    mov rax, [rdi]

    ; If we reach here, the protection check failed!
    jmp .xo_fail_trap

.xo_fail_alloc:
    pop r12
    mov rsi, msg_xo_fail_alloc_str
    call uart_print_str
    jmp .panic

.xo_fail_map:
    pop r12
    mov rsi, msg_xo_fail_map_str
    call uart_print_str
    jmp .panic

.xo_fail_walk:
    pop r12
    mov rsi, msg_xo_fail_walk_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_present:
    pop r12
    mov rsi, msg_xo_fail_pte_present_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_key:
    pop r12
    mov rsi, msg_xo_fail_pte_key_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_nx:
    pop r12
    mov rsi, msg_xo_fail_pte_nx_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_absent:
    pop r12
    mov rsi, msg_xo_fail_pte_absent_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_xo:
    pop r12
    mov rsi, msg_xo_fail_pte_xo_str
    call uart_print_str
    jmp .panic

.xo_fail_trap:
    pop r12
    mov rsi, msg_xo_fail_trap_str
    call uart_print_str
    jmp .panic

.aslr_fail_alloc:
    mov rsi, msg_aslr_fail_alloc_str
    call uart_print_str
    jmp .panic

.aslr_fail_align:
    mov rsi, msg_aslr_fail_align_str
    call uart_print_str
    jmp .panic

.aslr_fail_bounds:
    mov rsi, msg_aslr_fail_bounds_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_init_active:
    mov rsi, msg_tsx_fallback_lock_fail_init_active_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_init_lock:
    mov rsi, msg_tsx_fallback_lock_fail_init_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_bypass_active:
    mov rsi, msg_tsx_fallback_lock_fail_bypass_active_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_bypass_lock:
    mov rsi, msg_tsx_fallback_lock_fail_bypass_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_decay_lock:
    mov rsi, msg_tsx_fallback_lock_fail_decay_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_decay_count:
    mov rsi, msg_tsx_fallback_lock_fail_decay_count_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_retry_active:
    mov rsi, msg_tsx_fallback_lock_fail_retry_active_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_retry_lock:
    mov rsi, msg_tsx_fallback_lock_fail_retry_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_final_count:
    mov rsi, msg_tsx_fallback_lock_fail_final_count_str
    call uart_print_str
    jmp .panic

.hle_fail_alloc:
    mov rsi, msg_hle_fail_alloc_str
    call uart_print_str
    jmp .panic

.hle_fail_map:
    mov rsi, msg_hle_fail_map_str
    call uart_print_str
    jmp .panic

.hle_fail_walk1:
    mov rsi, msg_hle_fail_walk1_str
    call uart_print_str
    jmp .panic

.hle_fail_flags1:
    mov rsi, msg_hle_fail_flags1_str
    call uart_print_str
    jmp .panic

.hle_fail_walk2:
    mov rsi, msg_hle_fail_walk2_str
    call uart_print_str
    jmp .panic

.hle_fail_flags2:
    mov rsi, msg_hle_fail_flags2_str
    call uart_print_str
    jmp .panic

.hle_fail_align1:
    mov rsi, msg_hle_fail_align1_str
    call uart_print_str
    jmp .panic

.hle_fail_align2:
    mov rsi, msg_hle_fail_align2_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_active:
    mov rsi, msg_tsx_lock_fail_active_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_bypass:
    mov rsi, msg_tsx_lock_fail_bypass_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_release_active:
    mov rsi, msg_tsx_lock_fail_rel_active_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_release_lock:
    mov rsi, msg_tsx_lock_fail_rel_lock_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_traditional:
    mov rsi, msg_tsx_lock_fail_trad_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_traditional_release:
    mov rsi, msg_tsx_lock_fail_trad_rel_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_vma:
    mov rsi, msg_tsx_spec_walk_fail_vma_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_initial_cache:
    mov rsi, msg_tsx_spec_walk_fail_init_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_lookup:
    mov rsi, msg_tsx_spec_walk_fail_lookup_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_mismatch:
    mov rsi, msg_tsx_spec_walk_fail_mismatch_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_invalidate:
    mov rsi, msg_tsx_spec_walk_fail_inval_str
    call uart_print_str
    jmp .panic

.tsx_test_fail_vma:
    mov rsi, msg_tsx_test_fail_vma
    call uart_print_str
    jmp .panic

.tsx_test_fail_data:
    mov rsi, msg_tsx_test_fail_data
    call uart_print_str
    jmp .panic

    ; =========================================================================
    ; Use-After-Free (UAF) Trap Tests (Subfeature 19.2)
    ; =========================================================================
.uaf_test_start:
    mov rsi, msg_uaf_test_start
    call uart_print_str

    ; Initialize UAF quarantine table
    call uaf_init

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .uaf_fail_alloc
    mov r12, rax                    ; R12 = physical page

    ; 2. Map page to virtual address 0xB0000000 with present & writable permissions
    mov rdi, 0xB0000000
    mov rsi, r12
    mov rdx, 0x03                   ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .uaf_fail_map

    ; 3. Write data to make sure it is mapped and present
    mov rdi, 0xB0000000
    mov qword [rdi], 0xDEADBEEF12345678

    ; 4. Unmap/Free the virtual page (calls uaf_quarantine_add internally)
    mov rdi, 0xB0000000
    call virt_unmap

    mov rdi, r12
    call phys_free_page             ; Free physical frame

    ; 5. Read access from unmapped address 0xB0000000
    ; This triggers a page fault, which queries the quarantine table,
    ; prints "Use-After-Free detected at address 0x00000000B0000000! (UAF_TEST_SUCCESS)"
    ; and panics.
    mov rdi, 0xB0000000
    mov rax, [rdi]                  ; should trigger UAF Trap and halt!

    ; If we reach here, the trap failed!
    mov rsi, msg_uaf_fail_trap
    call uart_print_str
    jmp .panic

.uaf_fail_alloc:
    mov rsi, msg_uaf_fail_alloc_str
    call uart_print_str
    jmp .panic

.uaf_fail_map:
    mov rsi, msg_uaf_fail_map_str
    call uart_print_str
    jmp .panic


.leak_fail_initial:
    mov rsi, msg_leak_fail_initial
    call uart_print_str
    jmp .panic

.leak_fail_alloc:
    mov rsi, msg_leak_fail_alloc
    call uart_print_str
    jmp .panic

.leak_fail_count:
    mov rsi, msg_leak_fail_count
    call uart_print_str
    jmp .panic

.leak_fail_verify:
    mov rsi, msg_leak_fail_verify
    call uart_print_str
    jmp .panic

.leak_fail_final:
    mov rsi, msg_leak_fail_final
    call uart_print_str
    jmp .panic


.ipc_fail_pml4:
    mov rsi, msg_ipc_fail_pml4
    call uart_print_str
    jmp .panic

.ipc_fail_alloc:
    mov rsi, msg_ipc_fail_alloc
    call uart_print_str
    jmp .panic

.ipc_fail_map:
    mov rsi, msg_ipc_fail_map
    call uart_print_str
    jmp .panic

.ipc_fail_share:
    mov rsi, msg_ipc_fail_share
    call uart_print_str
    jmp .panic

.ipc_fail_shared_val:
    mov cr3, r14                    ; restore original CR3
    mov rsi, msg_ipc_fail_shared_val
    call uart_print_str
    jmp .panic

.ipc_fail_ring_create:
    mov rsi, msg_ipc_fail_ring_create
    call uart_print_str
    jmp .panic

.ipc_fail_ring_val:
    mov rsi, msg_ipc_fail_ring_val
    call uart_print_str
    jmp .panic

.ipc_fail_ring_cross_val:
    mov rsi, msg_ipc_fail_ring_cross_val
    call uart_print_str
    jmp .panic


.mmap_fail_create:
    mov rsi, msg_mmap_fail_create
    call uart_print_str
    jmp .panic

.mmap_fail_map:
    mov rsi, msg_mmap_fail_map
    call uart_print_str
    jmp .panic

.mmap_fail_read_val:
    mov rsi, msg_mmap_fail_read_val
    call uart_print_str
    jmp .panic

.mmap_fail_read_offset:
    mov rsi, msg_mmap_fail_read_offset
    call uart_print_str
    jmp .panic

.mmap_fail_pte:
    mov rsi, msg_mmap_fail_pte
    call uart_print_str
    jmp .panic

.mmap_fail_dirty:
    mov rsi, msg_mmap_fail_dirty
    call uart_print_str
    jmp .panic

.mmap_fail_sync:
    mov rsi, msg_mmap_fail_sync
    call uart_print_str
    jmp .panic

.mmap_fail_not_cleared:
    mov rsi, msg_mmap_fail_not_cleared
    call uart_print_str
    jmp .panic

.mmap_fail_backing:
    mov rsi, msg_mmap_fail_backing
    call uart_print_str
    jmp .panic

.mmap_fail_backing_data:
    mov rsi, msg_mmap_fail_backing_data
    call uart_print_str
    jmp .panic

.mmap_fail_unmap:
    mov rsi, msg_mmap_fail_unmap
    call uart_print_str
    jmp .panic


.smep_smap_fail_alloc:
    mov rsi, msg_smep_smap_fail_alloc_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_vma:
    mov rdi, r12
    call phys_free_page
    mov rsi, msg_smep_smap_fail_vma_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_map:
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_map_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_copy_to:
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_copy_to_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_copy_from:
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_copy_from_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_data:
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_data_str
    call uart_print_str
    jmp .panic

.numa_fail_count:
    mov rsi, msg_numa_fail_count_str
    call uart_print_str
    jmp .panic

.numa_fail_lookup_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_lookup:
    mov rsi, msg_numa_fail_lookup_str
    call uart_print_str
    jmp .panic

.numa_fail_distance_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_distance_bounds:
    mov rsi, msg_numa_fail_dist_bounds_str
    call uart_print_str
    jmp .panic

.numa_fail_bitmaps_init_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_bitmaps_init:
    mov rsi, msg_numa_fail_bmp_init_str
    call uart_print_str
    jmp .panic

.numa_fail_alloc_node_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_alloc_node:
    mov rsi, msg_numa_fail_alloc_node_str
    call uart_print_str
    jmp .panic

.numa_fail_node_affinity_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_node_affinity:
    mov rsi, msg_numa_fail_affinity_str
    call uart_print_str
    jmp .panic

.numa_fail_fallback_alloc_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_fallback_alloc:
    mov rsi, msg_numa_fail_fallback_str
    call uart_print_str
    jmp .panic

.numa_fail_sim_oom_alloc_pop:
    pop rax
    mov [numa_nodes + numa_node_t.end_page], rax
    pop r14
    pop r13
    pop r12
.numa_fail_sim_oom_alloc:
    mov rsi, msg_numa_fail_sim_oom_alloc_str
    call uart_print_str
    jmp .panic

.numa_fail_sim_oom_affinity_pop:
    mov rdi, r14
    call phys_free_page
    pop rax
    mov [numa_nodes + numa_node_t.end_page], rax
    pop r14
    pop r13
    pop r12
.numa_fail_sim_oom_affinity:
    mov rsi, msg_numa_fail_sim_oom_affinity_str
    call uart_print_str
    jmp .panic



.memmove_fail_alloc:
    pop r12
    mov rsi, msg_memmove_fail_alloc_str
    call uart_print_str
    jmp .panic

.memmove_fail_ret:
    pop r12
    mov rsi, msg_memmove_fail_ret_str
    call uart_print_str
    jmp .panic

.memmove_fail_data:
    pop r12
    mov rsi, msg_memmove_fail_data_str
    call uart_print_str
    jmp .panic

.run_match_case:
    mov rdi, r12
    mov rsi, r13
    mov rdx, rcx
    call memcmp
    test rax, rax
    jnz .memcmp_fail_match_pop
    ret

.memcmp_fail_match_pop:
    pop rax                         ; clean up call return address
    pop r14
    pop r13
    pop r12
    jmp .memcmp_fail_match

.memcmp_fail_mismatch_val:
    pop r14
    pop r13
    pop r12
    jmp .memcmp_fail_mismatch

.memcmp_fail_alloc:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_memcmp_fail_alloc_str
    call uart_print_str
    jmp .panic

.memcmp_fail_match:
    mov rsi, msg_memcmp_fail_match_str
    call uart_print_str
    jmp .panic

.memcmp_fail_mismatch:
    mov rsi, msg_memcmp_fail_mismatch_str
    call uart_print_str
    jmp .panic

.run_one_memzero_case:
    push rcx

    ; 1. Reset destination buffer with sentinel values (1..128)
    mov rdi, r12
    xor rdx, rdx
.sentinel_loop_memzero:
    mov r8b, dl
    inc r8b
    mov [rdi + rdx], r8b
    inc rdx
    cmp rdx, 128
    jb .sentinel_loop_memzero

    ; 2. Call memzero(r12, rcx)
    mov rdi, r12
    mov rsi, rcx                    ; RSI = size N
    call memzero                    ; RAX = dest pointer

    ; 3. Verify return value
    cmp rax, r12
    jne .memzero_fail_ret_pop

    ; Restore parameters for verification
    mov rcx, [rsp]                  ; RCX = size N

    ; 4. Verify first N bytes match 0
    test rcx, rcx
    jz .check_tail_memzero          ; if N == 0, skip checking payload
    xor rdx, rdx                    ; RDX = index i
.payload_loop_memzero:
    mov al, [r12 + rdx]
    test al, al
    jnz .memzero_fail_data_pop
    inc rdx
    cmp rdx, rcx
    jb .payload_loop_memzero

.check_tail_memzero:
    mov rcx, [rsp]                  ; RCX = size N
    ; 5. Verify remaining 128-N bytes are original sentinels (i + 1)
    mov rdx, rcx                    ; RDX = index i = N
.tail_loop_memzero:
    cmp rdx, 128
    jae .done_case_memzero
    mov al, [r12 + rdx]
    mov r8b, dl
    inc r8b                         ; R8B = index + 1
    cmp al, r8b                     ; Dst[i] must be i + 1
    jne .memzero_fail_extra_pop
    inc rdx
    jmp .tail_loop_memzero

.done_case_memzero:
    pop rcx
    ret

.memzero_fail_ret_pop:
    pop rcx
    pop r13
    pop r12
    jmp .memzero_fail_ret

.memzero_fail_data_pop:
    pop rcx
    pop r13
    pop r12
    jmp .memzero_fail_data

.memzero_fail_extra_pop:
    pop rcx
    pop r13
    pop r12
    jmp .memzero_fail_extra

.memzero_fail_alloc:
    pop r13
    pop r12
    mov rsi, msg_memzero_fail_alloc_str
    call uart_print_str
    jmp .panic

.memzero_fail_ret:
    mov rsi, msg_memzero_fail_ret_str
    call uart_print_str
    jmp .panic

.memzero_fail_data:
    mov rsi, msg_memzero_fail_data_str
    call uart_print_str
    jmp .panic

.memzero_fail_extra:
    mov rsi, msg_memzero_fail_extra_str
    call uart_print_str
    jmp .panic

.run_one_memset_case:
    push rcx
    push rsi

    ; 1. Reset destination buffer with sentinel values (0..127)
    mov rdi, r12
    xor rdx, rdx
.sentinel_loop:
    mov [rdi + rdx], dl
    inc rdx
    cmp rdx, 128
    jb .sentinel_loop

    ; 2. Call memset(r12, rsi, rcx)
    mov rdi, r12
    ; RSI is already the fill byte
    mov rdx, rcx                    ; RDX = size N
    call memset                     ; RAX = dest pointer

    ; 3. Verify return value
    cmp rax, r12
    jne .memset_fail_ret_pop

    ; Restore parameters for verification
    mov rcx, [rsp + 8]              ; RCX = size N
    mov rsi, [rsp]                  ; RSI = fill byte

    ; 4. Verify first N bytes match the fill value
    test rcx, rcx
    jz .check_tail_memset           ; if N == 0, skip checking payload
    xor rdx, rdx                    ; RDX = index i
.payload_loop_memset:
    mov al, [r12 + rdx]
    cmp al, sil
    jne .memset_fail_data_pop
    inc rdx
    cmp rdx, rcx
    jb .payload_loop_memset

.check_tail_memset:
    mov rcx, [rsp + 8]              ; RCX = size N
    ; 5. Verify remaining 128-N bytes are original sentinels (i)
    mov rdx, rcx                    ; RDX = index i = N
.tail_loop_memset:
    cmp rdx, 128
    jae .done_case_memset
    mov al, [r12 + rdx]
    cmp al, dl                      ; Dst[i] must be i
    jne .memset_fail_extra_pop
    inc rdx
    jmp .tail_loop_memset

.done_case_memset:
    pop rsi
    pop rcx
    ret

.memset_fail_ret_pop:
    pop rsi
    pop rcx
    pop r13
    pop r12
    jmp .memset_fail_ret

.memset_fail_data_pop:
    pop rsi
    pop rcx
    pop r13
    pop r12
    jmp .memset_fail_data

.memset_fail_extra_pop:
    pop rsi
    pop rcx
    pop r13
    pop r12
    jmp .memset_fail_extra

.memset_fail_alloc:
    pop r13
    pop r12
    mov rsi, msg_memset_fail_alloc_str
    call uart_print_str
    jmp .panic

.memset_fail_ret:
    mov rsi, msg_memset_fail_ret_str
    call uart_print_str
    jmp .panic

.memset_fail_data:
    mov rsi, msg_memset_fail_data_str
    call uart_print_str
    jmp .panic

.memset_fail_extra:
    mov rsi, msg_memset_fail_extra_str
    call uart_print_str
    jmp .panic

.run_one_memcpy_case:
    push rcx

    ; Zero out destination buffer (128 bytes)
    mov rdi, r13
    mov rdx, 128
.zero_loop:
    mov byte [rdi], 0
    inc rdi
    dec rdx
    jnz .zero_loop

    ; Call memcpy(r13, r12, rcx)
    mov rdi, r13
    mov rsi, r12
    pop rdx                         ; RDX = size N
    push rdx                        ; save for verification
    call memcpy                     ; RAX = dest pointer

    ; Verify return value
    cmp rax, r13
    jne .memcpy_fail_ret_pop

    pop rdx                         ; RDX = size N
    push rdx

    ; Verify first N bytes match
    test rdx, rdx
    jz .check_tail                  ; if N == 0, skip checking payload
    xor rcx, rcx                    ; RCX = index i
.payload_loop:
    mov al, [r13 + rcx]
    cmp al, cl                      ; since Src[i] == i, [r13 + i] must be i
    jne .memcpy_fail_data_pop
    inc rcx
    cmp rcx, rdx
    jb .payload_loop

.check_tail:
    pop rdx                         ; RDX = size N
    push rdx
    ; Verify remaining 128-N bytes are 0
    mov rcx, rdx                    ; RCX = index i = N
.tail_loop:
    cmp rcx, 128
    jae .done_case
    mov al, [r13 + rcx]
    test al, al
    jnz .memcpy_fail_extra_pop
    inc rcx
    jmp .tail_loop

.done_case:
    pop rdx
    ret

.memcpy_fail_ret_pop:
    pop rdx
    pop r13
    pop r12
    jmp .memcpy_fail_ret

.memcpy_fail_data_pop:
    pop rdx
    pop r13
    pop r12
    jmp .memcpy_fail_data

.memcpy_fail_extra_pop:
    pop rdx
    pop r13
    pop r12
    jmp .memcpy_fail_extra

.memcpy_fail_alloc:
    pop r13
    pop r12
    mov rsi, msg_memcpy_fail_alloc_str
    call uart_print_str
    jmp .panic

.memcpy_fail_ret:
    mov rsi, msg_memcpy_fail_ret_str
    call uart_print_str
    jmp .panic

.memcpy_fail_data:
    mov rsi, msg_memcpy_fail_data_str
    call uart_print_str
    jmp .panic

.memcpy_fail_extra:
    mov rsi, msg_memcpy_fail_extra_str
    call uart_print_str
    jmp .panic

.pool_fail_grow_alloc:
    pop rbp
    mov rsi, msg_pool_fail_grow_alloc_str
    call uart_print_str
    jmp .panic

.pool_fail_capacity_grow:
    pop rbp
    mov rsi, msg_pool_fail_capacity_grow_str
    call uart_print_str
    jmp .panic

.pool_fail_count_grow:
    pop rbp
    mov rsi, msg_pool_fail_count_grow_str
    call uart_print_str
    jmp .panic

.pool_fail_alloc_pop:
    pop rbp
.pool_fail_alloc:
    mov rsi, msg_pool_fail_alloc_str
    call uart_print_str
    jmp .panic

.pool_fail_oom_pop:
    pop rbp
.pool_fail_oom:
    mov rsi, msg_pool_fail_oom_str
    call uart_print_str
    jmp .panic

.pool_fail_count_pop:
    pop rbp
.pool_fail_count:
    mov rsi, msg_pool_fail_count_str
    call uart_print_str
    jmp .panic

.pool_fail_free_list_pop:
    pop rbp
.pool_fail_free_list:
    mov rsi, msg_pool_fail_free_list_str
    call uart_print_str
    jmp .panic

.pool_fail_reuse_pop:
    pop rbp
.pool_fail_reuse:
    mov rsi, msg_pool_fail_reuse_str
    call uart_print_str
    jmp .panic

.pool_fail_safety_pop:
    pop rbp
.pool_fail_safety:
    mov rsi, msg_pool_fail_safety_str
    call uart_print_str
    jmp .panic

.pool_fail_tag_pop:
    pop rbp
.pool_fail_tag:
    mov rsi, msg_pool_fail_tag_str
    call uart_print_str
    jmp .panic

.pool_fail_create:
    mov rsi, msg_pool_fail_create_str
    call uart_print_str
    jmp .panic

.pool_fail_config:
    mov rsi, msg_pool_fail_config_str
    call uart_print_str
    jmp .panic

.pool_fail_ptr:
    mov rsi, msg_pool_fail_ptr_str
    call uart_print_str
    jmp .panic

.heap_fail_active:
    mov rsi, msg_heap_fail_active_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc:
    mov rsi, msg_heap_fail_alloc_str
    call uart_print_str
    jmp .panic

.heap_fail_align:
    mov rsi, msg_heap_fail_align_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc2:
    mov rsi, msg_heap_fail_alloc2_str
    call uart_print_str
    jmp .panic

.heap_fail_align2:
    mov rsi, msg_heap_fail_align2_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc3:
    mov rsi, msg_heap_fail_alloc3_str
    call uart_print_str
    jmp .panic

.heap_fail_align3:
    mov rsi, msg_heap_fail_align3_str
    call uart_print_str
    jmp .panic

.heap_fail_spacing:
    mov rsi, msg_heap_fail_spacing_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc_split:
    mov rsi, msg_heap_fail_alloc_split_str
    call uart_print_str
    jmp .panic

.heap_fail_split_ptr:
    mov rsi, msg_heap_fail_split_ptr_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc_split2:
    mov rsi, msg_heap_fail_alloc_split2_str
    call uart_print_str
    jmp .panic

.heap_fail_split_rem:
    mov rsi, msg_heap_fail_split_rem_str
    call uart_print_str
    jmp .panic

.heap_fail_coalesce:
    mov rsi, msg_heap_fail_coalesce_str
    call uart_print_str
    jmp .panic

.heap_fail_coalesce_ptr:
    mov rsi, msg_heap_fail_coalesce_ptr_str
    call uart_print_str
    jmp .panic


.pat_skip_test:
    mov rsi, msg_pat_skipped_str
    call uart_print_str
    jmp .percpu_stat_test

.pat_fail_get:
    mov rsi, msg_pat_fail_get_str
    call uart_print_str
    jmp .panic

.pat_fail_wb_index:
    mov rsi, msg_pat_fail_wb_index_str
    call uart_print_str
    jmp .panic

.pat_fail_wt_index:
    mov rsi, msg_pat_fail_wt_index_str
    call uart_print_str
    jmp .panic

.pat_fail_wc_index:
    mov rsi, msg_pat_fail_wc_index_str
    call uart_print_str
    jmp .panic

.pat_fail_uc_index:
    mov rsi, msg_pat_fail_uc_index_str
    call uart_print_str
    jmp .panic

.pat_fail_set:
    mov rsi, msg_pat_fail_set_str
    call uart_print_str
    jmp .panic

.pat_fail_wc_swap:
    mov rsi, msg_pat_fail_wc_swap_str
    call uart_print_str
    jmp .panic

.pat_fail_wp_swap:
    mov rsi, msg_pat_fail_wp_swap_str
    call uart_print_str
    jmp .panic

.pat_fail_restore:
    mov rsi, msg_pat_fail_restore_str
    call uart_print_str
    jmp .panic

.pat_fail_restore_verify:
    mov rsi, msg_pat_fail_rest_ver_str
    call uart_print_str
    jmp .panic

.mtrr_fail_set:
    mov rsi, msg_mtrr_fail_set_str
    call uart_print_str
    jmp .panic

.mtrr_fail_get_active:
    mov rsi, msg_mtrr_fail_get_act_str
    call uart_print_str
    jmp .panic

.mtrr_fail_base:
    mov rsi, msg_mtrr_fail_base_str
    call uart_print_str
    jmp .panic

.mtrr_fail_size:
    mov rsi, msg_mtrr_fail_size_str
    call uart_print_str
    jmp .panic

.mtrr_fail_type:
    mov rsi, msg_mtrr_fail_type_str
    call uart_print_str
    jmp .panic

.mtrr_fail_disable:
    mov rsi, msg_mtrr_fail_disable_str
    call uart_print_str
    jmp .panic

.mtrr_fail_still_active:
    mov rsi, msg_mtrr_fail_still_act_str
    call uart_print_str
    jmp .panic

.zswap_fail_init_telemetry:
    mov rsi, msg_zswap_fail_init_tel_str
    call uart_print_str
    jmp .panic

.zswap_fail_alloc1:
    mov rsi, msg_zswap_fail_alloc1_str
    call uart_print_str
    jmp .panic

.zswap_fail_vma1:
    mov rsi, msg_zswap_fail_vma1_str
    call uart_print_str
    jmp .panic

.zswap_fail_map1:
    mov rsi, msg_zswap_fail_map1_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk1:
    mov rsi, msg_zswap_fail_walk1_str
    call uart_print_str
    jmp .panic

.zswap_fail_evict1:
    mov rsi, msg_zswap_fail_evict1_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk_ev1:
    mov rsi, msg_zswap_fail_walk_ev1_str
    call uart_print_str
    jmp .panic

.zswap_fail_still_present1:
    mov rsi, msg_zswap_fail_still_pres1_str
    call uart_print_str
    jmp .panic

.zswap_fail_not_swapped1:
    mov rsi, msg_zswap_fail_not_swap1_str
    call uart_print_str
    jmp .panic

.zswap_fail_not_zswapped1:
    mov rsi, msg_zswap_fail_not_zswap1_str
    call uart_print_str
    jmp .panic

.zswap_fail_telemetry1:
    mov rsi, msg_zswap_fail_telemetry1_str
    call uart_print_str
    jmp .panic

.zswap_fail_data_corrupt1:
    mov rsi, msg_zswap_fail_data1_str
    call uart_print_str
    jmp .panic

.zswap_fail_telemetry_res1:
    mov rsi, msg_zswap_fail_tel_res1_str
    call uart_print_str
    jmp .panic

.zswap_fail_alloc2:
    mov rsi, msg_zswap_fail_alloc2_str
    call uart_print_str
    jmp .panic

.zswap_fail_vma2:
    mov rsi, msg_zswap_fail_vma2_str
    call uart_print_str
    jmp .panic

.zswap_fail_map2:
    mov rsi, msg_zswap_fail_map2_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk2:
    mov rsi, msg_zswap_fail_walk2_str
    call uart_print_str
    jmp .panic

.zswap_fail_evict2:
    mov rsi, msg_zswap_fail_evict2_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk_ev2:
    mov rsi, msg_zswap_fail_walk_ev2_str
    call uart_print_str
    jmp .panic

.zswap_fail_still_present2:
    mov rsi, msg_zswap_fail_still_pres2_str
    call uart_print_str
    jmp .panic

.zswap_fail_not_swapped2:
    mov rsi, msg_zswap_fail_not_swap2_str
    call uart_print_str
    jmp .panic

.zswap_fail_is_zswapped2:
    mov rsi, msg_zswap_fail_is_zswap2_str
    call uart_print_str
    jmp .panic

.zswap_fail_telemetry2:
    mov rsi, msg_zswap_fail_telemetry2_str
    call uart_print_str
    jmp .panic

.zswap_fail_data_corrupt2:
    mov rsi, msg_zswap_fail_data2_str
    call uart_print_str
    jmp .panic

.rep_fail_init_count:
    mov rsi, msg_rep_fail_init_str
    call uart_print_str
    jmp .panic

.rep_fail_alloc:
    mov rsi, msg_rep_fail_alloc_str
    call uart_print_str
    jmp .panic

.rep_fail_vma:
    mov rsi, msg_rep_fail_vma_str
    call uart_print_str
    jmp .panic

.rep_fail_map:
    mov rsi, msg_rep_fail_map_str
    call uart_print_str
    jmp .panic

.rep_fail_active_count:
    mov rsi, msg_rep_fail_active_str
    call uart_print_str
    jmp .panic

.rep_fail_inactive_count:
    mov rsi, msg_rep_fail_inactive_str
    call uart_print_str
    jmp .panic

.rep_fail_active_count_inactive:
    mov rsi, msg_rep_fail_active_in_str
    call uart_print_str
    jmp .panic

.rep_fail_inactive_count_inactive:
    mov rsi, msg_rep_fail_inactive_in_str
    call uart_print_str
    jmp .panic

.rep_fail_active_count_back:
    mov rsi, msg_rep_fail_active_back_str
    call uart_print_str
    jmp .panic

.rep_fail_inactive_count_back:
    mov rsi, msg_rep_fail_inactive_back_str
    call uart_print_str
    jmp .panic

.rep_fail_final_count:
    mov rsi, msg_rep_fail_final_str
    call uart_print_str
    jmp .panic

.test_fail_vma:
    mov rsi, msg_fail_vma_str
    call uart_print_str
    jmp .panic

.test_fail_val:
    mov rsi, msg_fail_val_str
    call uart_print_str
    jmp .panic

.test_fail_addr:
    mov rsi, msg_fail_addr_str
    call uart_print_str
    jmp .panic

.cow_fail_alloc:
    mov rsi, msg_cow_fail_alloc_str
    call uart_print_str
    jmp .panic

.cow_fail_vma:
    mov rsi, msg_cow_fail_vma_str
    call uart_print_str
    jmp .panic

.cow_fail_map:
    mov rsi, msg_cow_fail_map_str
    call uart_print_str
    jmp .panic

.cow_fail_isolation:
    mov rsi, msg_cow_fail_iso_str
    call uart_print_str
    jmp .panic

.cow_fail_same_page:
    mov rsi, msg_cow_fail_same_str
    call uart_print_str
    jmp .panic

.zfod_fail_vma:
    mov rsi, msg_zfod_fail_vma_str
    call uart_print_str
    jmp .panic

.zfod_fail_read_val:
    mov rsi, msg_zfod_fail_read_str
    call uart_print_str
    jmp .panic

.zfod_fail_zero_ptr:
    mov rsi, msg_zfod_fail_ptr_str
    call uart_print_str
    jmp .panic

.zfod_fail_write_val:
    mov rsi, msg_zfod_fail_write_str
    call uart_print_str
    jmp .panic

.zfod_fail_isolation:
    mov rsi, msg_zfod_fail_iso_str
    call uart_print_str
    jmp .panic

.zfod_fail_same_page:
    mov rsi, msg_zfod_fail_same_str
    call uart_print_str
    jmp .panic

.zfod_fail_page2_val:
    mov rsi, msg_zfod_fail_p2val_str
    call uart_print_str
    jmp .panic

.zfod_fail_page2_same:
    mov rsi, msg_zfod_fail_p2same_str
    call uart_print_str
    jmp .panic

.stack_fail_vma:
    mov rsi, msg_stack_fail_vma_str
    call uart_print_str
    jmp .panic

.stack_fail_val:
    mov rsi, msg_stack_fail_val_str
    call uart_print_str
    jmp .panic

.stack_fail_map:
    mov rsi, msg_stack_fail_map_str
    call uart_print_str
    jmp .panic

.clock_fail_alloc:
    mov rsi, msg_clock_fail_alloc_str
    call uart_print_str
    jmp .panic

.clock_fail_vma:
    mov rsi, msg_clock_fail_vma_str
    call uart_print_str
    jmp .panic

.clock_fail_map:
    mov rsi, msg_clock_fail_map_str
    call uart_print_str
    jmp .panic

.clock_fail_inactive:
    mov rsi, msg_clock_fail_inactive_str
    call uart_print_str
    jmp .panic

.clock_fail_walk:
    mov rsi, msg_clock_fail_walk_str
    call uart_print_str
    jmp .panic

.clock_fail_evict:
    mov rsi, msg_clock_fail_evict_str
    call uart_print_str
    jmp .panic

.clock_fail_walk_evicted:
    mov rsi, msg_clock_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.clock_fail_still_present:
    mov rsi, msg_clock_fail_still_pres_str
    call uart_print_str
    jmp .panic

.clock_fail_not_swapped:
    mov rsi, msg_clock_fail_not_swap_str
    call uart_print_str
    jmp .panic

.clock_fail_stats:
    mov rsi, msg_clock_fail_stats_str
    call uart_print_str
    jmp .panic

.clock_fail_list_counts:
    mov rsi, msg_clock_fail_list_str
    call uart_print_str
    jmp .panic

.clock_fail_data_corrupt:
    mov rsi, msg_clock_fail_data_str
    call uart_print_str
    jmp .panic

.clock_fail_stats_restore:
    mov rsi, msg_clock_fail_stats_res_str
    call uart_print_str
    jmp .panic

.clock_fail_active_restore:
    mov rsi, msg_clock_fail_act_res_str
    call uart_print_str
    jmp .panic

.clock_fail_inactive_restore:
    mov rsi, msg_clock_fail_inact_res_str
    call uart_print_str
    jmp .panic

.ata_fail_alloc:
    mov rsi, msg_ata_fail_alloc_str
    call uart_print_str
    jmp .panic

.ata_fail_vma:
    mov rsi, msg_ata_fail_vma_str
    call uart_print_str
    jmp .panic

.ata_fail_map:
    mov rsi, msg_ata_fail_map_str
    call uart_print_str
    jmp .panic

.ata_fail_inactive:
    mov rsi, msg_ata_fail_inactive_str
    call uart_print_str
    jmp .panic

.ata_fail_walk:
    mov rsi, msg_ata_fail_walk_str
    call uart_print_str
    jmp .panic

.ata_fail_evict:
    mov rsi, msg_ata_fail_evict_str
    call uart_print_str
    jmp .panic

.ata_fail_walk_evicted:
    mov rsi, msg_ata_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.ata_fail_still_present:
    mov rsi, msg_ata_fail_still_pres_str
    call uart_print_str
    jmp .panic

.ata_fail_not_swapped:
    mov rsi, msg_ata_fail_not_swap_str
    call uart_print_str
    jmp .panic

.ata_fail_data_corrupt:
    mov rsi, msg_ata_fail_data_str
    call uart_print_str
    jmp .panic

.nvme_fail_alloc:
    mov rsi, msg_nvme_fail_alloc_str
    call uart_print_str
    jmp .panic

.nvme_fail_vma:
    mov rsi, msg_nvme_fail_vma_str
    call uart_print_str
    jmp .panic

.nvme_fail_map:
    mov rsi, msg_nvme_fail_map_str
    call uart_print_str
    jmp .panic

.nvme_fail_inactive:
    mov rsi, msg_nvme_fail_inactive_str
    call uart_print_str
    jmp .panic

.nvme_fail_walk:
    mov rsi, msg_nvme_fail_walk_str
    call uart_print_str
    jmp .panic

.nvme_fail_evict:
    mov rsi, msg_nvme_fail_evict_str
    call uart_print_str
    jmp .panic

.nvme_fail_walk_evicted:
    mov rsi, msg_nvme_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.nvme_fail_still_present:
    mov rsi, msg_nvme_fail_still_pres_str
    call uart_print_str
    jmp .panic

.nvme_fail_not_swapped:
    mov rsi, msg_nvme_fail_not_swap_str
    call uart_print_str
    jmp .panic

.nvme_fail_data_corrupt:
    mov rsi, msg_nvme_fail_data_str
    call uart_print_str
    jmp .panic

.kswapd_fail_alloc_setup:
    mov rsi, msg_kswapd_fail_alloc_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_vma_setup:
    mov rsi, msg_kswapd_fail_vma_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_map_setup:
    mov rsi, msg_kswapd_fail_map_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_walk_setup:
    mov rsi, msg_kswapd_fail_walk_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_alloc_trigger:
    mov rsi, msg_kswapd_fail_alloc_trigger_str
    call uart_print_str
    jmp .panic

.kswapd_fail_walk_evicted:
    mov rsi, msg_kswapd_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.kswapd_fail_still_present:
    mov rsi, msg_kswapd_fail_still_pres_str
    call uart_print_str
    jmp .panic

.kswapd_fail_not_swapped:
    mov rsi, msg_kswapd_fail_not_swap_str
    call uart_print_str
    jmp .panic

.kswapd_fail_data_corrupt:
    mov rsi, msg_kswapd_fail_data_str
    call uart_print_str
    jmp .panic

    ; =========================================================================
    ; 34.2 Per-CPU Memory Counters Test
    ; =========================================================================
.percpu_stat_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_percpu_stat_test_start
    call uart_print_str

    ; --- Step 1: Initialise the per-CPU counter subsystem ---
    call percpu_stat_init

    ; Verify: after init, the global vm_stat nr_free counter should be 0
    ; (index 0 = VM_STAT_NR_FREE)
    mov rdi, 0
    call percpu_stat_read
    test rax, rax
    jnz .percpu_fail_init_nonzero

    ; Verify: global vm_event pgalloc counter should also be 0
    ; (index 0 = VM_EVENT_PGALLOC)
    mov rdi, 0
    call percpu_event_read
    test rax, rax
    jnz .percpu_fail_init_nonzero

    ; Verify: sync count telemetry starts at 0
    mov rax, [sys_percpu_sync_count]
    test rax, rax
    jnz .percpu_fail_init_nonzero

    ; --- Step 2: Lock-free per-CPU stat increments (CPU 0) ---
    ; Increment nr_free (idx 0) three times from CPU 0
    mov rdi, 0          ; cpu_id = 0
    mov rsi, 0          ; stat_idx = VM_STAT_NR_FREE
    call percpu_stat_inc
    call percpu_stat_inc
    call percpu_stat_inc

    ; Increment nr_anon (idx 1) once from CPU 0
    mov rdi, 0
    mov rsi, 1          ; VM_STAT_NR_ANON
    call percpu_stat_inc

    ; Decrement nr_anon once (net = 0)
    mov rdi, 0
    mov rsi, 1
    call percpu_stat_dec

    ; --- Step 3: Lock-free per-CPU event increments (CPU 0) ---
    ; Increment pgalloc (idx 0) twice
    mov rdi, 0
    mov rsi, 0          ; VM_EVENT_PGALLOC
    call percpu_event_inc
    call percpu_event_inc

    ; Increment pgfault (idx 2) once
    mov rdi, 0
    mov rsi, 2          ; VM_EVENT_PGFAULT
    call percpu_event_inc

    ; --- Step 4: Verify pending per-CPU deltas BEFORE sync ---
    ; nr_free delta for CPU 0 must be 3
    mov rdi, 0          ; cpu_id
    mov rsi, 0          ; stat_idx = VM_STAT_NR_FREE
    call percpu_stat_delta_read
    cmp rax, 3
    jne .percpu_fail_delta_stat

    ; nr_anon delta for CPU 0 must be 0 (incremented once, decremented once)
    mov rdi, 0
    mov rsi, 1          ; VM_STAT_NR_ANON
    call percpu_stat_delta_read
    test rax, rax
    jnz .percpu_fail_delta_anon

    ; pgalloc delta for CPU 0 must be 2
    mov rdi, 0
    mov rsi, 0          ; VM_EVENT_PGALLOC
    call percpu_event_delta_read
    cmp rax, 2
    jne .percpu_fail_delta_event

    ; pgfault delta for CPU 0 must be 1
    mov rdi, 0
    mov rsi, 2          ; VM_EVENT_PGFAULT
    call percpu_event_delta_read
    cmp rax, 1
    jne .percpu_fail_delta_event

    ; Global counters must still be 0 (not yet synced)
    mov rdi, 0          ; VM_STAT_NR_FREE
    call percpu_stat_read
    test rax, rax
    jnz .percpu_fail_presync_nonzero

    mov rdi, 0          ; VM_EVENT_PGALLOC
    call percpu_event_read
    test rax, rax
    jnz .percpu_fail_presync_nonzero

    ; --- Step 5: Periodic sync â€” flush per-CPU deltas to globals ---
    call percpu_sync

    ; After sync, per-CPU deltas for CPU 0 must be reset to 0
    mov rdi, 0
    mov rsi, 0          ; VM_STAT_NR_FREE
    call percpu_stat_delta_read
    test rax, rax
    jnz .percpu_fail_postsync_delta

    ; --- Step 6: Verify global vm_stat counters after sync ---
    ; sys_vm_stat[VM_STAT_NR_FREE] must be 3
    mov rdi, 0
    call percpu_stat_read
    cmp rax, 3
    jne .percpu_fail_global_stat

    ; sys_vm_stat[VM_STAT_NR_ANON] must be 0
    mov rdi, 1
    call percpu_stat_read
    test rax, rax
    jnz .percpu_fail_global_stat

    ; --- Step 7: Verify global vm_event counters after sync ---
    ; sys_vm_event[VM_EVENT_PGALLOC] must be 2
    mov rdi, 0
    call percpu_event_read
    cmp rax, 2
    jne .percpu_fail_global_event

    ; sys_vm_event[VM_EVENT_PGFAULT] must be 1
    mov rdi, 2
    call percpu_event_read
    cmp rax, 1
    jne .percpu_fail_global_event

    ; sys_vm_event[VM_EVENT_PGSWAPOUT] must be 0 (never incremented)
    mov rdi, 3
    call percpu_event_read
    test rax, rax
    jnz .percpu_fail_global_event

    ; --- Step 8: Verify sync telemetry counter is now 1 ---
    mov rax, [sys_percpu_sync_count]
    cmp rax, 1
    jne .percpu_fail_sync_count

    ; --- Step 9: Second sync should be a no-op (no new deltas) ---
    call percpu_sync

    ; sys_vm_stat[VM_STAT_NR_FREE] must still be 3
    mov rdi, 0
    call percpu_stat_read
    cmp rax, 3
    jne .percpu_fail_idempotent

    ; sync count telemetry must now be 2
    mov rax, [sys_percpu_sync_count]
    cmp rax, 2
    jne .percpu_fail_sync_count

    ; --- Step 10: Multi-CPU simulation â€” add deltas for CPU 1 ---
    ; Increment nr_slab (idx 3) twice from CPU 1
    mov rdi, 1          ; cpu_id = 1
    mov rsi, 3          ; VM_STAT_NR_SLAB
    call percpu_stat_inc
    call percpu_stat_inc

    ; Increment pgswapout (idx 3) once from CPU 1
    mov rdi, 1
    mov rsi, 3          ; VM_EVENT_PGSWAPOUT
    call percpu_event_inc

    ; Sync to aggregate CPU 1 deltas
    call percpu_sync

    ; sys_vm_stat[VM_STAT_NR_SLAB] must be 2
    mov rdi, 3
    call percpu_stat_read
    cmp rax, 2
    jne .percpu_fail_multicpu_stat

    ; sys_vm_event[VM_EVENT_PGSWAPOUT] must be 1
    mov rdi, 3
    call percpu_event_read
    cmp rax, 1
    jne .percpu_fail_multicpu_event

    ; sys_vm_stat[VM_STAT_NR_FREE] must still be 3 (CPU 0 delta, not changed)
    mov rdi, 0
    call percpu_stat_read
    cmp rax, 3
    jne .percpu_fail_multicpu_stat

    ; PASSED!
    mov rsi, msg_percpu_stat_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .meminfo_test

.percpu_fail_init_nonzero:
    mov rsi, msg_percpu_fail_init_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_delta_stat:
    mov rsi, msg_percpu_fail_delta_stat_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_delta_anon:
    mov rsi, msg_percpu_fail_delta_anon_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_delta_event:
    mov rsi, msg_percpu_fail_delta_event_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_presync_nonzero:
    mov rsi, msg_percpu_fail_presync_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_postsync_delta:
    mov rsi, msg_percpu_fail_postsync_delta_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_global_stat:
    mov rsi, msg_percpu_fail_global_stat_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_global_event:
    mov rsi, msg_percpu_fail_global_event_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_sync_count:
    mov rsi, msg_percpu_fail_sync_count_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_idempotent:
    mov rsi, msg_percpu_fail_idempotent_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_multicpu_stat:
    mov rsi, msg_percpu_fail_multicpu_stat_str
    call uart_print_str
    jmp .percpu_panic

.percpu_fail_multicpu_event:
    mov rsi, msg_percpu_fail_multicpu_event_str
    call uart_print_str
    jmp .percpu_panic

    ; =========================================================================
    ; 34.3 Memory Map Statistics Test (meminfo / /proc/meminfo equivalent)
    ; =========================================================================
.meminfo_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_meminfo_test_start
    call uart_print_str

    ; --- Step 1: Take a snapshot ---
    call meminfo_snapshot

    ; Verify snap count is now 1
    mov rax, [sys_meminfo_snap_count]
    cmp rax, 1
    jne .meminfo_fail_snap_count

    ; --- Step 2: MemTotal must be non-zero ---
    mov rdi, 0          ; MEMINFO_TOTAL
    call meminfo_get_field
    test rax, rax
    jz   .meminfo_fail_total_zero
    mov r12, rax        ; R12 = MemTotal

    ; --- Step 3: MemFree must be non-zero and <= MemTotal ---
    mov rdi, 1          ; MEMINFO_FREE
    call meminfo_get_field
    test rax, rax
    jz   .meminfo_fail_free_zero
    cmp rax, r12
    ja   .meminfo_fail_free_exceeds ; free > total is impossible

    ; --- Step 4: Inject a buf page, re-snapshot, verify Buffers field ---
    ; Manually increment buf counter to simulate a buffer-cache allocation
    lock inc qword [sys_buf_pages]
    call meminfo_snapshot

    mov rdi, 2          ; MEMINFO_BUFFERS
    call meminfo_get_field
    ; Buffers must now be >= 4096 (at least 1 page)
    cmp rax, 4096
    jb   .meminfo_fail_buffers

    ; Undo: decrement buf counter
    lock dec qword [sys_buf_pages]

    ; --- Step 5: Inject a shmem page, re-snapshot, verify Shmem field ---
    lock inc qword [sys_shmem_pages]
    call meminfo_snapshot

    mov rdi, 5          ; MEMINFO_SHMEM
    call meminfo_get_field
    cmp rax, 4096
    jb   .meminfo_fail_shmem

    ; Undo
    lock dec qword [sys_shmem_pages]

    ; --- Step 6: Verify get_snapshot_ptr returns a non-null pointer ---
    call meminfo_get_snapshot_ptr
    test rax, rax
    jz   .meminfo_fail_ptr

    ; Verify MemTotal in struct matches what get_field returns
    mov rbx, rax        ; RBX = snapshot ptr
    mov rax, [rbx]      ; .mem_total = first field
    cmp rax, r12
    jne .meminfo_fail_struct

    ; PASSED!
    mov rsi, msg_meminfo_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .proc_memstat_test

.meminfo_fail_snap_count:
    mov rsi, msg_meminfo_fail_snap_count_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_total_zero:
    mov rsi, msg_meminfo_fail_total_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_free_zero:
    mov rsi, msg_meminfo_fail_free_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_free_exceeds:
    mov rsi, msg_meminfo_fail_free_exceeds_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_buffers:
    mov rsi, msg_meminfo_fail_buffers_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_shmem:
    mov rsi, msg_meminfo_fail_shmem_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_ptr:
    mov rsi, msg_meminfo_fail_ptr_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_fail_struct:
    mov rsi, msg_meminfo_fail_struct_str
    call uart_print_str
    jmp .meminfo_panic

.meminfo_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 34.4 Per-Process Memory Stats Test (VSZ / RSS / PSS / USS)
    ; =========================================================================
.proc_memstat_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_proc_memstat_test_start
    call uart_print_str

    ; Allocate a proc_memstat_t result struct on the heap (32 bytes)
    mov rdi, 32
    call heap_alloc
    test rax, rax
    jz   .proc_memstat_fail_alloc
    mov r12, rax        ; R12 = output struct ptr

    ; Allocate a physical page and map it at 0xB0000000 with a VMA
    call phys_alloc_page
    test rax, rax
    jz   .proc_memstat_fail_page
    mov r13, rax        ; R13 = physical page

    ; Create VMA for [0xB0000000, 0xB0001000)
    mov rdi, 0xB0000000
    mov rsi, 4096
    mov rdx, 3          ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz   .proc_memstat_fail_vma
    mov r14, rax        ; R14 = VMA pointer

    ; Map the physical page into the VMA
    mov rdi, 0xB0000000
    mov rsi, r13
    mov rdx, 3          ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz   .proc_memstat_fail_map

    ; Run proc_memstat_compute â€” use thread_table[0] as the thread
    lea  rdi, [thread_table]
    mov  rsi, r12       ; output struct
    call proc_memstat_compute

    ; --- VSZ must be >= 4096 (at minimum the VMA we just created) ---
    mov rdi, r12
    call proc_memstat_get_vsz
    cmp rax, 4096
    jb   .proc_memstat_fail_vsz
    mov r15, rax        ; R15 = VSZ

    ; --- RSS must be >= 4096 (the one mapped page) ---
    mov rdi, r12
    call proc_memstat_get_rss
    cmp rax, 4096
    jb   .proc_memstat_fail_rss

    ; --- For a single VMA with no sharing, PSS == RSS ---
    mov rbx, rax        ; RBX = RSS
    mov rdi, r12
    call proc_memstat_get_pss
    ; PSS should equal RSS when share_count = 1
    cmp rax, rbx
    jne  .proc_memstat_fail_pss

    ; --- USS must equal RSS (unique, no sharing) ---
    mov rdi, r12
    call proc_memstat_get_uss
    cmp rax, rbx
    jne  .proc_memstat_fail_uss

    ; --- VSZ >= RSS (virtual space always >= resident) ---
    cmp r15, rbx
    jb   .proc_memstat_fail_vsz

    ; Clean up
    mov rdi, 0xB0000000
    call virt_unmap

    mov rdi, r14
    call vma_destroy

    mov rdi, r13
    call phys_free_page

    mov rdi, r12
    call heap_free

    ; PASSED!
    mov rsi, msg_proc_memstat_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .mbm_test

.proc_memstat_fail_alloc:
    mov rsi, msg_proc_memstat_fail_alloc_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_page:
    mov rsi, msg_proc_memstat_fail_page_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_vma:
    mov rsi, msg_proc_memstat_fail_vma_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_map:
    mov rsi, msg_proc_memstat_fail_map_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_vsz:
    mov rsi, msg_proc_memstat_fail_vsz_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_rss:
    mov rsi, msg_proc_memstat_fail_rss_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_pss:
    mov rsi, msg_proc_memstat_fail_pss_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_fail_uss:
    mov rsi, msg_proc_memstat_fail_uss_str
    call uart_print_str
    jmp .proc_memstat_panic

.proc_memstat_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 34.5 Memory Bandwidth Monitoring (MBM / Intel RDT) Test
    ; =========================================================================
.mbm_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_mbm_test_start
    call uart_print_str

    ; --- Step 1: Detect RDT/MBM hardware ---
    call mbm_detect
    ; We accept both supported and unsupported hardware paths:
    ;   if supported: run full test
    ;   if not:       verify sys_mbm_supported == 0 and skip to PASSED
    test rax, rax
    jz   .mbm_no_hardware

    ; --- Hardware detected path ---
    mov rsi, msg_mbm_hw_detected
    call uart_print_str

    ; --- Step 2: Init MBM subsystem ---
    call mbm_init
    test rax, rax
    jz   .mbm_fail_init

    ; Verify scale factor is set (non-zero)
    mov rax, [sys_mbm_scale]
    test rax, rax
    jz   .mbm_fail_scale

    ; --- Step 3: Assign RMID 1 to CPU 0 ---
    mov rdi, 0
    call mbm_assign_rmid
    test rax, rax
    jz   .mbm_fail_assign
    mov r12, rax        ; R12 = RMID

    ; Verify active RMID count = 1
    mov rax, [sys_mbm_active_rmids]
    cmp rax, 1
    jne .mbm_fail_rmid_count

    ; --- Step 4: Inject synthetic bandwidth counters ---
    ; Inject 1000 raw units for total BW on RMID 1
    mov rdi, r12        ; RMID
    mov rsi, 0x2        ; MBM_EVT_TOTAL_BW
    mov rdx, 1000
    call mbm_set_sim_counter

    ; Inject 750 raw units for local BW on RMID 1
    mov rdi, r12
    mov rsi, 0x3        ; MBM_EVT_LOCAL_BW
    mov rdx, 750
    call mbm_set_sim_counter

    ; --- Step 5: Read bandwidth (raw Ã— scale) ---
    mov rdi, r12
    mov rsi, 0x2        ; total BW
    call mbm_read_bw
    ; RAX = 1000 Ã— scale_factor; must be >= 1000 (scale >= 1)
    cmp rax, 1000
    jb   .mbm_fail_total_bw
    mov r13, rax        ; R13 = total BW bytes

    mov rdi, r12
    mov rsi, 0x3        ; local BW
    call mbm_read_bw
    cmp rax, 750
    jb   .mbm_fail_local_bw
    mov r14, rax        ; R14 = local BW bytes

    ; Local BW must be <= total BW
    cmp r14, r13
    ja   .mbm_fail_local_exceeds_total

    ; --- Step 6: mbm_poll_all --- snapshot into mbm_bw_snapshot ---
    call mbm_poll_all
    ; Verify snapshot[0] (RMID 1 total) matches R13
    mov rax, [mbm_bw_snapshot]
    cmp rax, r13
    jne .mbm_fail_snapshot

    ; --- Step 7: mbm_is_saturated with low threshold (should be saturated) ---
    ; threshold = 0 MB â†’ any BW will trigger saturation
    mov rdi, 0
    call mbm_is_saturated
    cmp rax, 1
    jne .mbm_fail_saturated_low

    ; threshold = very high (1 TB) â†’ should NOT be saturated
    mov rdi, (1024 * 1024)  ; 1 TB in MB
    call mbm_is_saturated
    test rax, rax
    jnz .mbm_fail_saturated_high

    jmp .mbm_passed

.mbm_no_hardware:
    ; Verify flag was set to 0
    mov rax, [sys_mbm_supported]
    test rax, rax
    jnz .mbm_fail_flag

    mov rsi, msg_mbm_hw_unsupported
    call uart_print_str

    ; Verify that mbm_init returns 0 (graceful no-op)
    call mbm_init
    test rax, rax
    jnz .mbm_fail_init_notsup

    ; Verify read_bw returns 0 when not supported
    mov rdi, 1
    mov rsi, 0x2
    call mbm_read_bw
    test rax, rax
    jnz .mbm_fail_bw_notsup

    jmp .mbm_passed

.mbm_passed:
    mov rsi, msg_mbm_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .sev_test

.mbm_fail_init:
    mov rsi, msg_mbm_fail_init_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_scale:
    mov rsi, msg_mbm_fail_scale_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_assign:
    mov rsi, msg_mbm_fail_assign_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_rmid_count:
    mov rsi, msg_mbm_fail_rmid_count_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_total_bw:
    mov rsi, msg_mbm_fail_total_bw_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_local_bw:
    mov rsi, msg_mbm_fail_local_bw_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_local_exceeds_total:
    mov rsi, msg_mbm_fail_local_exceeds_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_snapshot:
    mov rsi, msg_mbm_fail_snapshot_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_saturated_low:
    mov rsi, msg_mbm_fail_saturated_low_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_saturated_high:
    mov rsi, msg_mbm_fail_saturated_high_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_flag:
    mov rsi, msg_mbm_fail_flag_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_init_notsup:
    mov rsi, msg_mbm_fail_init_notsup_str
    call uart_print_str
    jmp .mbm_panic

.mbm_fail_bw_notsup:
    mov rsi, msg_mbm_fail_bw_notsup_str
    call uart_print_str
    jmp .mbm_panic

.mbm_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 35.1 AMD SEV (Secure Encrypted Virtualization) Test
    ; =========================================================================
.sev_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_sev_test_start
    call uart_print_str

    ; --- Step 1: sev_detect() â€” probe CPUID.8000001Fh ---
    call sev_detect
    ; Accept both paths: SEV capable or not
    mov r12, rax                ; R12 = sys_sev_supported value

    ; Verify sys_sev_supported matches return value
    mov rax, [sys_sev_supported]
    cmp rax, r12
    jne .sev_fail_flag

    ; --- Step 2: sev_init() â€” combined init (always succeeds if CPU is capable) ---
    call sev_init
    test rax, rax
    jz   .sev_not_capable       ; CPU doesn't have SEV at all

    ; --- Hardware-capable path ---
    mov rsi, msg_sev_capable
    call uart_print_str

    ; sys_sev_init_count must be 1
    mov rax, [sys_sev_init_count]
    cmp rax, 1
    jne .sev_fail_init_count

    ; --- Step 3: sev_encrypt_gpa for page at GPA 0x1000 ---
    mov rdi, 0x1000
    call sev_encrypt_gpa
    cmp rax, 1
    jne .sev_fail_encrypt

    ; sys_sev_encrypted_pages must now be 1
    mov rax, [sys_sev_encrypted_pages]
    cmp rax, 1
    jne .sev_fail_count

    ; --- Step 4: sev_is_encrypted must return 1 for 0x1000 ---
    mov rdi, 0x1000
    call sev_is_encrypted
    cmp rax, 1
    jne .sev_fail_is_encrypted

    ; --- Step 5: sev_is_encrypted must return 0 for 0x2000 (not encrypted) ---
    mov rdi, 0x2000
    call sev_is_encrypted
    test rax, rax
    jnz .sev_fail_is_not_encrypted

    ; --- Step 6: sev_encrypt_gpa for two more pages (0x2000, 0x3000) ---
    mov rdi, 0x2000
    call sev_encrypt_gpa
    mov rdi, 0x3000
    call sev_encrypt_gpa

    ; sys_sev_encrypted_pages must now be 3
    mov rax, [sys_sev_encrypted_pages]
    cmp rax, 3
    jne .sev_fail_count

    ; --- Step 7: sev_decrypt_gpa for 0x2000 â€” unshare one page ---
    mov rdi, 0x2000
    call sev_decrypt_gpa
    cmp rax, 1
    jne .sev_fail_decrypt

    ; encrypted_pages must drop to 2
    mov rax, [sys_sev_encrypted_pages]
    cmp rax, 2
    jne .sev_fail_count

    ; sev_is_encrypted(0x2000) must now return 0
    mov rdi, 0x2000
    call sev_is_encrypted
    test rax, rax
    jnz .sev_fail_decrypt_verify

    ; --- Step 8: sev_decrypt_gpa idempotent â€” decrypt already-clear page ---
    mov rdi, 0x2000
    call sev_decrypt_gpa    ; already clear; should still return 1
    cmp rax, 1
    jne .sev_fail_decrypt

    ; count must not change (still 2)
    mov rax, [sys_sev_encrypted_pages]
    cmp rax, 2
    jne .sev_fail_count

    ; --- Step 9: sev_vmgexit â€” must not fault on bare metal ---
    mov rdi, 0x002          ; SEV_GHCB_PAGE_SHARE
    mov rsi, 0x1000         ; GPA
    call sev_vmgexit        ; returns 0 on bare metal (nop)
    ; No assertion on return value; just must not crash

    ; --- Step 10: sev_validate_page (SEV-SNP simulation) ---
    mov rdi, 0x4000
    mov rsi, 1              ; validate (encrypt)
    call sev_validate_page
    mov rdi, 0x4000
    call sev_is_encrypted
    cmp rax, 1
    jne .sev_fail_validate

    jmp .sev_passed

.sev_not_capable:
    ; CPU doesn't have SEV â€” verify flag is 0
    mov rax, [sys_sev_supported]
    test rax, rax
    jnz .sev_fail_flag

    mov rsi, msg_sev_not_capable
    call uart_print_str

    ; Verify encrypt/decrypt return 1 (bitmap ops work regardless of HW)
    mov rdi, 0x5000
    call sev_encrypt_gpa
    cmp rax, 1
    jne .sev_fail_encrypt

    mov rdi, 0x5000
    call sev_is_encrypted
    cmp rax, 1
    jne .sev_fail_is_encrypted

.sev_passed:
    mov rsi, msg_sev_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .tdx_test

.sev_fail_flag:
    mov rsi, msg_sev_fail_flag_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_init_count:
    mov rsi, msg_sev_fail_init_count_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_encrypt:
    mov rsi, msg_sev_fail_encrypt_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_count:
    mov rsi, msg_sev_fail_count_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_is_encrypted:
    mov rsi, msg_sev_fail_is_encrypted_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_is_not_encrypted:
    mov rsi, msg_sev_fail_is_not_encrypted_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_decrypt:
    mov rsi, msg_sev_fail_decrypt_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_decrypt_verify:
    mov rsi, msg_sev_fail_decrypt_verify_str
    call uart_print_str
    jmp .sev_panic

.sev_fail_validate:
    mov rsi, msg_sev_fail_validate_str
    call uart_print_str
    jmp .sev_panic

.sev_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 35.2 Intel TDX (Trust Domain Extensions) Test
    ; =========================================================================
.tdx_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_tdx_test_start
    call uart_print_str

    ; --- Step 1: tdx_detect() â€” CPUID signature + feature bit probe ---
    call tdx_detect
    mov r12, rax                ; R12 = 1 if TDX capable

    ; Verify sys_tdx_supported matches return value
    mov rax, [sys_tdx_supported]
    cmp rax, r12
    jne .tdx_fail_flag

    ; --- Step 2: tdx_init() ---
    call tdx_init
    test rax, rax
    jz   .tdx_not_capable

    ; --- Hardware-capable path ---
    mov rsi, msg_tdx_capable
    call uart_print_str

    ; sys_tdx_init_count must be 1
    mov rax, [sys_tdx_init_count]
    cmp rax, 1
    jne .tdx_fail_init_count

    ; --- Step 3: tdx_share_gpa for GPA 0x10000 ---
    mov rdi, 0x10000
    call tdx_share_gpa
    cmp rax, 1
    jne .tdx_fail_share

    ; sys_tdx_shared_pages must be 1
    mov rax, [sys_tdx_shared_pages]
    cmp rax, 1
    jne .tdx_fail_count

    ; --- Step 4: tdx_is_shared(0x10000) must return 1 ---
    mov rdi, 0x10000
    call tdx_is_shared
    cmp rax, 1
    jne .tdx_fail_is_shared

    ; --- Step 5: tdx_is_shared(0x20000) must return 0 (not shared) ---
    mov rdi, 0x20000
    call tdx_is_shared
    test rax, rax
    jnz .tdx_fail_is_not_shared

    ; --- Step 6: tdx_private_gpa â€” convert 0x10000 back to private ---
    mov rdi, 0x10000
    call tdx_private_gpa
    cmp rax, 1
    jne .tdx_fail_private

    ; shared_pages must drop to 0
    mov rax, [sys_tdx_shared_pages]
    test rax, rax
    jnz .tdx_fail_count

    ; tdx_is_shared(0x10000) must now return 0
    mov rdi, 0x10000
    call tdx_is_shared
    test rax, rax
    jnz .tdx_fail_private_verify

    ; --- Step 7: tdx_private_gpa idempotent ---
    mov rdi, 0x10000
    call tdx_private_gpa    ; already private; still returns 1
    cmp rax, 1
    jne .tdx_fail_private
    ; count must still be 0
    mov rax, [sys_tdx_shared_pages]
    test rax, rax
    jnz .tdx_fail_count

    ; --- Step 8: tdx_accept_page simulation ---
    mov rdi, 0x30000
    call tdx_accept_page    ; 0 = success
    test rax, rax
    jnz .tdx_fail_accept

    ; accepted page must be private (not shared)
    mov rdi, 0x30000
    call tdx_is_shared
    test rax, rax
    jnz .tdx_fail_accept_verify

    ; --- Step 9: tdx_vmcall â€” must not fault on bare metal ---
    mov rdi, 0x0001         ; TDX_VMCALL_HALT (just a safe function number)
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call tdx_vmcall         ; returns 0 in simulation

    ; --- Step 10: tdx_report â€” fill attestation report buffer ---
    sub  rsp, 1024          ; stack-allocate 1024-byte report buffer
    mov  rdi, rsp
    xor  rsi, rsi           ; no additional data
    call tdx_report
    test rax, rax
    jnz  .tdx_fail_report

    ; Verify the "TDXREP" marker at offset 0
    mov  rax, [rsp]
    mov  rbx, 0x524F504552584454     ; "TDXREPOR"
    cmp  rax, rbx
    jne  .tdx_fail_report_marker

    add  rsp, 1024          ; restore stack

    jmp .tdx_passed

.tdx_not_capable:
    ; CPU doesn't enumerate TDX â€” verify flag is 0
    mov rax, [sys_tdx_supported]
    test rax, rax
    jnz .tdx_fail_flag

    mov rsi, msg_tdx_not_capable
    call uart_print_str

    ; Bitmap ops still work on bare metal
    mov rdi, 0x40000
    call tdx_share_gpa
    cmp rax, 1
    jne .tdx_fail_share

    mov rdi, 0x40000
    call tdx_is_shared
    cmp rax, 1
    jne .tdx_fail_is_shared

    ; tdx_report with null buf must return error
    xor rdi, rdi
    call tdx_report
    test rax, rax
    jz   .tdx_fail_report_null

.tdx_passed:
    mov rsi, msg_tdx_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .cca_test

.tdx_fail_flag:
    mov rsi, msg_tdx_fail_flag_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_init_count:
    mov rsi, msg_tdx_fail_init_count_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_share:
    mov rsi, msg_tdx_fail_share_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_count:
    mov rsi, msg_tdx_fail_count_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_is_shared:
    mov rsi, msg_tdx_fail_is_shared_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_is_not_shared:
    mov rsi, msg_tdx_fail_is_not_shared_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_private:
    mov rsi, msg_tdx_fail_private_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_private_verify:
    mov rsi, msg_tdx_fail_private_verify_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_accept:
    mov rsi, msg_tdx_fail_accept_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_accept_verify:
    mov rsi, msg_tdx_fail_accept_verify_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_report:
    add  rsp, 1024
    mov rsi, msg_tdx_fail_report_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_report_marker:
    add  rsp, 1024
    mov rsi, msg_tdx_fail_report_marker_str
    call uart_print_str
    jmp .tdx_panic

.tdx_fail_report_null:
    mov rsi, msg_tdx_fail_report_null_str
    call uart_print_str
    jmp .tdx_panic

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 35.3 ARM CCA (Confidential Compute Architecture) Test
    ; =========================================================================
.cca_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_cca_test_start
    call uart_print_str

    ; 1. cca_detect (returns 0 because sys_cca_supported is initially 0)
    call cca_detect
    test rax, rax
    jz .cca_not_capable

    ; (If it somehow returned 1, just fail or handle it, but it should return 0)
    jmp .cca_panic

.cca_not_capable:
    ; Verify sys_cca_supported is 0
    mov rax, [sys_cca_supported]
    test rax, rax
    jnz .cca_fail_flag

    mov rsi, msg_cca_not_capable
    call uart_print_str

    ; 2. Initialize simulation explicitly
    call cca_init
    cmp rax, 1
    jne .cca_fail_init

    ; Verify sys_cca_supported is now 1
    mov rax, [sys_cca_supported]
    cmp rax, 1
    jne .cca_fail_flag

    ; Verify sys_cca_init_count is 1
    mov rax, [sys_cca_init_count]
    cmp rax, 1
    jne .cca_fail_init_count

    ; Verify sys_cca_realm_count is 0
    mov rax, [sys_cca_realm_count]
    test rax, rax
    jnz .cca_fail_count

    ; 3. Create Realm 1
    mov rdi, 1
    call cca_realm_create
    cmp rax, 1
    jne .cca_fail_create

    ; Verify realm_count is 1
    mov rax, [sys_cca_realm_count]
    cmp rax, 1
    jne .cca_fail_count

    ; 4. Map GPA 0x10000 -> IPA 0x10000 in Realm 1
    mov rdi, 1
    mov rsi, 0x10000
    mov rdx, 0x10000
    call cca_map_gpa
    cmp rax, 1
    jne .cca_fail_map

    ; Verify is_realm_page
    mov rdi, 0x10000
    call cca_is_realm_page
    cmp rax, 1              ; should return Realm ID (1)
    jne .cca_fail_is_realm_page

    ; Check adjacent/unmapped GPA 0x20000
    mov rdi, 0x20000
    call cca_is_realm_page
    test rax, rax
    jnz .cca_fail_is_not_realm_page

    ; 5. Test SMC calls
    ; version check
    mov rdi, SMC_RMI_VERSION
    call cca_smc_call
    cmp rax, 0x00010000
    jne .cca_fail_smc_version

    ; map unprotected via SMC
    mov rdi, SMC_RMI_RTT_MAP_UNPROTECTED
    mov rsi, 1
    mov rdx, 0x30000
    mov rcx, 0x30000
    call cca_smc_call
    test rax, rax
    jnz .cca_fail_smc_map

    ; verify GPA 0x30000 is now owned by Realm 1
    mov rdi, 0x30000
    call cca_is_realm_page
    cmp rax, 1
    jne .cca_fail_is_realm_page

    ; 6. Unmap GPA 0x10000
    mov rdi, 1
    mov rsi, 0x10000
    call cca_unmap_gpa
    cmp rax, 1
    jne .cca_fail_unmap

    mov rdi, 0x10000
    call cca_is_realm_page
    test rax, rax
    jnz .cca_fail_is_not_realm_page

    ; 7. Destroy Realm 1 (should unmap 0x30000 too)
    mov rdi, 1
    call cca_realm_destroy
    cmp rax, 1
    jne .cca_fail_destroy

    ; Verify counts are 0
    mov rax, [sys_cca_realm_count]
    test rax, rax
    jnz .cca_fail_count
    mov rax, [sys_cca_mapped_pages]
    test rax, rax
    jnz .cca_fail_count

    ; Verify 0x30000 is now free
    mov rdi, 0x30000
    call cca_is_realm_page
    test rax, rax
    jnz .cca_fail_is_not_realm_page

    mov rsi, msg_cca_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .enc_swap_test

.cca_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.cca_fail_flag:
    mov rsi, msg_cca_fail_flag
    call uart_print_str
    jmp .cca_panic

.cca_fail_init:
    mov rsi, msg_cca_fail_init
    call uart_print_str
    jmp .cca_panic

.cca_fail_init_count:
    mov rsi, msg_cca_fail_init_count
    call uart_print_str
    jmp .cca_panic

.cca_fail_count:
    mov rsi, msg_cca_fail_count
    call uart_print_str
    jmp .cca_panic

.cca_fail_create:
    mov rsi, msg_cca_fail_create
    call uart_print_str
    jmp .cca_panic

.cca_fail_map:
    mov rsi, msg_cca_fail_map
    call uart_print_str
    jmp .cca_panic

.cca_fail_unmap:
    mov rsi, msg_cca_fail_unmap
    call uart_print_str
    jmp .cca_panic

.cca_fail_destroy:
    mov rsi, msg_cca_fail_destroy
    call uart_print_str
    jmp .cca_panic

.cca_fail_is_realm_page:
    mov rsi, msg_cca_fail_is_realm_page
    call uart_print_str
    jmp .cca_panic

.cca_fail_is_not_realm_page:
    mov rsi, msg_cca_fail_is_not_realm_page
    call uart_print_str
    jmp .cca_panic

.cca_fail_smc_version:
    mov rsi, msg_cca_fail_smc_version
    call uart_print_str
    jmp .cca_panic

.cca_fail_smc_map:
    mov rsi, msg_cca_fail_smc_map
    call uart_print_str
    jmp .cca_panic


    ; =========================================================================
    ; 35.4 Encrypted Memory Swapping Test
    ; =========================================================================
.enc_swap_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_enc_swap_test_start
    call uart_print_str

    call enc_swap_init
    cmp rax, 1
    jne .enc_swap_fail_init

    mov rax, [sys_enc_swap_enabled]
    cmp rax, 1
    jne .enc_swap_fail_enabled

    mov rax, [sys_enc_swap_pages_encrypted]
    test rax, rax
    jnz .enc_swap_fail_counters
    mov rax, [sys_enc_swap_pages_decrypted]
    test rax, rax
    jnz .enc_swap_fail_counters

    ; stack buffer allocation for testing page encryption/decryption
    sub rsp, 8192

    ; fill Page A with pattern
    mov rdi, rsp
    mov rax, 0x0102030405060708
    mov rcx, 512
    rep stosq

    ; zero Page B
    lea rdi, [rsp + 4096]
    xor rax, rax
    mov rcx, 512
    rep stosq

    ; Encrypt Page A to Page B
    mov rdi, rsp
    lea rsi, [rsp + 4096]
    mov rdx, 4096
    call enc_swap_encrypt_page
    cmp rax, 1
    jne .enc_swap_fail_encrypt_stack

    ; Verify Page B != Page A
    mov rax, [rsp]
    mov rbx, [rsp + 4096]
    cmp rax, rbx
    je .enc_swap_fail_verify_enc_stack

    ; Verify stats count
    mov rax, [sys_enc_swap_pages_encrypted]
    cmp rax, 1
    jne .enc_swap_fail_counters_stack

    ; Clear Page A
    mov rdi, rsp
    xor rax, rax
    mov rcx, 512
    rep stosq

    ; Decrypt Page B to Page A
    lea rdi, [rsp + 4096]
    mov rsi, rsp
    mov rdx, 4096
    call enc_swap_decrypt_page
    cmp rax, 1
    jne .enc_swap_fail_decrypt_stack

    ; Verify Page A has original pattern
    mov rdi, rsp
    mov rax, 0x0102030405060708
    mov rcx, 512
.verify_dec_loop:
    cmp [rdi], rax
    jne .enc_swap_fail_verify_dec_stack
    add rdi, 8
    loop .verify_dec_loop

    ; Verify stats count
    mov rax, [sys_enc_swap_pages_decrypted]
    cmp rax, 1
    jne .enc_swap_fail_counters_stack

    add rsp, 8192

    mov rsi, msg_enc_swap_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .mte_test

.enc_swap_fail_encrypt_stack:
    add rsp, 8192
    jmp .enc_swap_fail_encrypt

.enc_swap_fail_verify_enc_stack:
    add rsp, 8192
    jmp .enc_swap_fail_verify_encryption

.enc_swap_fail_counters_stack:
    add rsp, 8192
    jmp .enc_swap_fail_counters

.enc_swap_fail_decrypt_stack:
    add rsp, 8192
    jmp .enc_swap_fail_decrypt

.enc_swap_fail_verify_dec_stack:
    add rsp, 8192
    jmp .enc_swap_fail_verify_decryption

.enc_swap_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.enc_swap_fail_init:
    mov rsi, msg_enc_swap_fail_init
    call uart_print_str
    jmp .enc_swap_panic

.enc_swap_fail_enabled:
    mov rsi, msg_enc_swap_fail_enabled
    call uart_print_str
    jmp .enc_swap_panic

.enc_swap_fail_counters:
    mov rsi, msg_enc_swap_fail_counters
    call uart_print_str
    jmp .enc_swap_panic

.enc_swap_fail_encrypt:
    mov rsi, msg_enc_swap_fail_encrypt
    call uart_print_str
    jmp .enc_swap_panic

.enc_swap_fail_decrypt:
    mov rsi, msg_enc_swap_fail_decrypt
    call uart_print_str
    jmp .enc_swap_panic

.enc_swap_fail_verify_encryption:
    mov rsi, msg_enc_swap_fail_verify_encryption
    call uart_print_str
    jmp .enc_swap_panic

.enc_swap_fail_verify_decryption:
    mov rsi, msg_enc_swap_fail_verify_decryption
    call uart_print_str
    jmp .enc_swap_panic


    ; =========================================================================
    ; 35.5 Memory Tagging (MTE) Test
    ; =========================================================================
.mte_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_mte_test_start
    call uart_print_str

    call mte_detect
    test rax, rax
    jnz .mte_fail_detect

    call mte_init
    cmp rax, 1
    jne .mte_fail_init

    call mte_detect
    cmp rax, 1
    jne .mte_fail_detect

    mov rax, [sys_mte_active]
    cmp rax, 1
    jne .mte_fail_active

    mov rax, [sys_mte_tag_faults]
    test rax, rax
    jnz .mte_fail_fault_count

    ; Granule test
    mov rdi, 0x1000
    mov rsi, 0x9
    call mte_set_granule_tag
    cmp rax, 1
    jne .mte_fail_set_tag

    mov rdi, 0x1000
    call mte_get_granule_tag
    cmp rax, 0x9
    jne .mte_fail_get_tag

    mov rdi, 0x1010
    call mte_get_granule_tag
    test rax, rax
    jnz .mte_fail_adjacent_tag

    ; Pointer validation (bits 59:56 = tag 9)
    mov rdi, 0x0900000000001000
    call mte_validate_ptr
    cmp rax, 1
    jne .mte_fail_validation

    ; Mismatch validation (bits 59:56 = tag A)
    mov rdi, 0x0A00000000001000
    call mte_validate_ptr
    test rax, rax
    jnz .mte_fail_validation_mismatch

    mov rax, [sys_mte_tag_faults]
    cmp rax, 1
    jne .mte_fail_fault_count

    ; Page-level test
    mov rdi, 0x5000
    mov rsi, 0xC
    call mte_tag_page
    cmp rax, 1
    jne .mte_fail_tag_page

    mov rdi, 0x5000
    call mte_get_granule_tag
    cmp rax, 0xC
    jne .mte_fail_page_tag_verify

    mov rdi, 0x5FF0
    call mte_get_granule_tag
    cmp rax, 0xC
    jne .mte_fail_page_tag_verify

    mov rax, [sys_mte_tagged_pages]
    cmp rax, 1
    jne .mte_fail_tagged_pages_count

    ; Free page tagging (UAF detection)
    mov rdi, 0x5000
    call mte_tag_free_page
    cmp rax, 1
    jne .mte_fail_tag_free_page

    mov rdi, 0x5000
    call mte_get_granule_tag
    cmp rax, 0xF
    jne .mte_fail_free_tag_verify

    mov rdi, 0x5FF0
    call mte_get_granule_tag
    cmp rax, 0xF
    jne .mte_fail_free_tag_verify

    mov rsi, msg_mte_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .ai_mem_test

.mte_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.mte_fail_detect:
    mov rsi, msg_mte_fail_detect
    call uart_print_str
    jmp .mte_panic

.mte_fail_init:
    mov rsi, msg_mte_fail_init
    call uart_print_str
    jmp .mte_panic

.mte_fail_active:
    mov rsi, msg_mte_fail_active
    call uart_print_str
    jmp .mte_panic

.mte_fail_fault_count:
    mov rsi, msg_mte_fail_fault_count
    call uart_print_str
    jmp .mte_panic

.mte_fail_set_tag:
    mov rsi, msg_mte_fail_set_tag
    call uart_print_str
    jmp .mte_panic

.mte_fail_get_tag:
    mov rsi, msg_mte_fail_get_tag
    call uart_print_str
    jmp .mte_panic

.mte_fail_adjacent_tag:
    mov rsi, msg_mte_fail_adjacent_tag
    call uart_print_str
    jmp .mte_panic

.mte_fail_validation:
    mov rsi, msg_mte_fail_validation
    call uart_print_str
    jmp .mte_panic

.mte_fail_validation_mismatch:
    mov rsi, msg_mte_fail_validation_mismatch
    call uart_print_str
    jmp .mte_panic

.mte_fail_tag_page:
    mov rsi, msg_mte_fail_tag_page
    call uart_print_str
    jmp .mte_panic

.mte_fail_page_tag_verify:
    mov rsi, msg_mte_fail_page_tag_verify
    call uart_print_str
    jmp .mte_panic

.mte_fail_tagged_pages_count:
    mov rsi, msg_mte_fail_tagged_pages_count
    call uart_print_str
    jmp .mte_panic

.mte_fail_tag_free_page:
    mov rsi, msg_mte_fail_tag_free_page
    call uart_print_str
    jmp .mte_panic

.mte_fail_free_tag_verify:
    mov rsi, msg_mte_fail_free_tag_verify
    call uart_print_str
    jmp .mte_panic

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 36. AI/Inference Specific Memory Features Test
    ; =========================================================================
.ai_mem_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_ai_mem_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 36.1 Tensor Memory Pool Test
    ; -------------------------------------------------------------------------
    lea rdi, [sys_tensor_pool_test_buf]
    mov rsi, 16384
    mov rdx, 2048
    call tensor_pool_init
    test rax, rax
    jz .ai_fail_tensor_init

    mov r12, rax                ; R12 = pool context pointer

    ; Verify sys_tensor_pool_total_blocks
    mov rax, [sys_tensor_pool_total_blocks]
    test rax, rax
    jz .ai_fail_tensor_count

    ; Allocate block 1
    mov rdi, r12
    call tensor_pool_alloc
    test rax, rax
    jz .ai_fail_tensor_alloc
    mov r13, rax                ; R13 = block 1 ptr

    ; Verify sys_tensor_pool_allocated_blocks is 1
    mov rax, [sys_tensor_pool_allocated_blocks]
    cmp rax, 1
    jne .ai_fail_tensor_allocated_count

    ; Allocate block 2
    mov rdi, r12
    call tensor_pool_alloc
    test rax, rax
    jz .ai_fail_tensor_alloc
    mov r14, rax                ; R14 = block 2 ptr

    ; Verify block 1 != block 2
    cmp r13, r14
    je .ai_fail_tensor_distinct

    ; Verify sys_tensor_pool_allocated_blocks is 2
    mov rax, [sys_tensor_pool_allocated_blocks]
    cmp rax, 2
    jne .ai_fail_tensor_allocated_count

    ; Free block 1
    mov rdi, r12
    mov rsi, r13
    call tensor_pool_free
    cmp rax, 1
    jne .ai_fail_tensor_free

    ; Verify allocated count is 1
    mov rax, [sys_tensor_pool_allocated_blocks]
    cmp rax, 1
    jne .ai_fail_tensor_allocated_count

    ; Free block 2
    mov rdi, r12
    mov rsi, r14
    call tensor_pool_free
    cmp rax, 1
    jne .ai_fail_tensor_free

    ; Verify allocated count is 0
    mov rax, [sys_tensor_pool_allocated_blocks]
    test rax, rax
    jnz .ai_fail_tensor_allocated_count

    mov rsi, msg_ai_tensor_pool_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 36.2 Weight Cache Manager Test
    ; -------------------------------------------------------------------------
    mov rdi, 1000000
    call weight_cache_init
    cmp rax, 1
    jne .ai_fail_weight_init

    ; Verify sys_weight_cache_max_bytes is 1000000
    mov rax, [sys_weight_cache_max_bytes]
    cmp rax, 1000000
    jne .ai_fail_weight_config

    ; Pin Model 1: size = 400,000, ptr = 0x50000000
    mov rdi, 0x50000000
    mov rsi, 400000
    mov rdx, 1
    call weight_cache_pin
    cmp rax, 1
    jne .ai_fail_weight_pin

    ; Verify stats
    mov rax, [sys_weight_cache_pinned_bytes]
    cmp rax, 400000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_total_bytes]
    cmp rax, 400000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_resident_models]
    cmp rax, 1
    jne .ai_fail_weight_stats

    ; Pin Model 2: size = 400,000, ptr = 0x50000000 + 400000
    mov rdi, 0x50000000 + 400000
    mov rsi, 400000
    mov rdx, 2
    call weight_cache_pin
    cmp rax, 1
    jne .ai_fail_weight_pin

    ; Verify stats
    mov rax, [sys_weight_cache_pinned_bytes]
    cmp rax, 800000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_total_bytes]
    cmp rax, 800000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_resident_models]
    cmp rax, 2
    jne .ai_fail_weight_stats

    ; Unpin Model 1
    mov rdi, 1
    call weight_cache_unpin
    cmp rax, 1
    jne .ai_fail_weight_unpin

    ; Verify stats
    mov rax, [sys_weight_cache_pinned_bytes]
    cmp rax, 400000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_total_bytes]
    cmp rax, 800000
    jne .ai_fail_weight_stats

    ; Pin Model 3
    mov rdi, 0x50000000 + 800000
    mov rsi, 300000
    mov rdx, 3
    call weight_cache_pin
    cmp rax, 1
    jne .ai_fail_weight_pin

    ; Verify Model 1 is evicted (touch/access fails)
    mov rdi, 1
    call weight_cache_access
    test rax, rax
    jnz .ai_fail_weight_evicted

    ; Verify Model 2 and 3 are resident
    mov rdi, 2
    call weight_cache_access
    cmp rax, 1
    jne .ai_fail_weight_access
    mov rdi, 3
    call weight_cache_access
    cmp rax, 1
    jne .ai_fail_weight_access

    ; Verify stats
    mov rax, [sys_weight_cache_pinned_bytes]
    cmp rax, 700000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_total_bytes]
    cmp rax, 700000
    jne .ai_fail_weight_stats
    mov rax, [sys_weight_cache_resident_models]
    cmp rax, 2
    jne .ai_fail_weight_stats

    mov rsi, msg_ai_weight_cache_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 36.3 KV Cache Physical Allocator Test
    ; -------------------------------------------------------------------------
    call kv_cache_init
    cmp rax, 1
    jne .ai_fail_kv_init

    ; Allocate contiguous 4 pages
    mov rdi, 4
    call kv_cache_alloc_block
    test rax, rax
    jz .ai_fail_kv_alloc
    mov r12, rax                ; R12 = physical block 1 (0x20000000)

    ; Verify stats
    mov rax, [sys_kv_cache_allocated_blocks]
    cmp rax, 1
    jne .ai_fail_kv_stats
    mov rax, [sys_kv_cache_contiguous_pages]
    cmp rax, 4
    jne .ai_fail_kv_stats

    ; Allocate contiguous 2 pages
    mov rdi, 2
    call kv_cache_alloc_block
    test rax, rax
    jz .ai_fail_kv_alloc
    mov r13, rax                ; R13 = physical block 2 (0x20004000)

    ; Verify stats
    mov rax, [sys_kv_cache_allocated_blocks]
    cmp rax, 2
    jne .ai_fail_kv_stats
    mov rax, [sys_kv_cache_contiguous_pages]
    cmp rax, 6
    jne .ai_fail_kv_stats

    ; Free block 1
    mov rdi, r12
    mov rsi, 4
    call kv_cache_free_block
    cmp rax, 1
    jne .ai_fail_kv_free

    ; Verify stats
    mov rax, [sys_kv_cache_allocated_blocks]
    cmp rax, 1
    jne .ai_fail_kv_stats
    mov rax, [sys_kv_cache_contiguous_pages]
    cmp rax, 2
    jne .ai_fail_kv_stats

    ; Free block 2
    mov rdi, r13
    mov rsi, 2
    call kv_cache_free_block
    cmp rax, 1
    jne .ai_fail_kv_free

    ; Verify stats
    mov rax, [sys_kv_cache_allocated_blocks]
    test rax, rax
    jnz .ai_fail_kv_stats
    mov rax, [sys_kv_cache_contiguous_pages]
    test rax, rax
    jnz .ai_fail_kv_stats

    ; Test TurboQuant Packing
    lea rdi, [sys_kv_src_bytes]
    mov byte [rdi], 5
    mov byte [rdi + 1], 11
    mov byte [rdi + 2], 2
    mov byte [rdi + 3], 8
    mov byte [rdi + 4], 0
    mov byte [rdi + 5], 7
    mov byte [rdi + 6], 10
    mov byte [rdi + 7], 4

    ; Pack 8 elements into packed dword
    lea rdi, [sys_kv_src_bytes]
    lea rsi, [sys_kv_packed_dword]
    mov rdx, 8
    call kv_cache_pack_turboquant
    cmp rax, 1
    jne .ai_fail_turboquant_pack

    ; Unpack packed dword back to bytes
    lea rdi, [sys_kv_packed_dword]
    lea rsi, [sys_kv_unpacked_bytes]
    mov rdx, 8
    call kv_cache_unpack_turboquant
    cmp rax, 8
    jne .ai_fail_turboquant_unpack

    ; Verify unpacked matches source
    lea rdi, [sys_kv_src_bytes]
    lea rsi, [sys_kv_unpacked_bytes]
    mov rcx, 8
.verify_kv_bytes:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .ai_fail_turboquant_mismatch
    inc rdi
    inc rsi
    loop .verify_kv_bytes

    mov rsi, msg_ai_kv_alloc_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 36.4 Activation Memory Recycler Test
    ; -------------------------------------------------------------------------
    call activation_recycler_init
    cmp rax, 1
    jne .ai_fail_act_init

    ; Register 4 pages
    mov rdi, 4
    call activation_recycler_register
    cmp rax, 4
    jne .ai_fail_act_register

    ; Verify page count
    mov rax, [sys_activation_page_count]
    cmp rax, 4
    jne .ai_fail_act_stats

    ; Map to virtual address 0x70000000 for Layer 1
    mov rdi, 1
    mov rsi, 0x70000000
    call activation_recycler_map
    cmp rax, 1
    jne .ai_fail_act_map

    ; Get physical translation
    mov rdi, 0x70000000
    call virt_translate
    test rax, rax
    jz .ai_fail_act_translate
    mov r12, rax                ; R12 = physical frame base

    ; Map to virtual address 0x70100000 for Layer 2
    mov rdi, 2
    mov rsi, 0x70100000
    call activation_recycler_map
    cmp rax, 1
    jne .ai_fail_act_map

    ; Get physical translation
    mov rdi, 0x70100000
    call virt_translate
    test rax, rax
    jz .ai_fail_act_translate
    mov r13, rax                ; R13 = physical frame base (Layer 2)

    ; Assert both layers map to the exact same physical frame
    cmp r12, r13
    jne .ai_fail_act_distinct

    ; Verify mapped buffers count
    mov rax, [sys_activation_mapped_buffers]
    cmp rax, 2
    jne .ai_fail_act_stats

    ; Unmap virtual ranges
    mov rdi, 0x70000000
    call activation_recycler_unmap
    cmp rax, 1
    jne .ai_fail_act_unmap

    mov rdi, 0x70100000
    call activation_recycler_unmap
    cmp rax, 1
    jne .ai_fail_act_unmap

    ; Verify mapped count is 0
    mov rax, [sys_activation_mapped_buffers]
    test rax, rax
    jnz .ai_fail_act_stats

    mov rsi, msg_ai_act_recycler_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 36.5 Prefetch-Aware Allocator Test
    ; -------------------------------------------------------------------------
    ; Allocate 8192 bytes aligned on NUMA Node 0
    mov rdi, 8192
    mov rsi, 0
    call prefetch_alloc_aligned
    test rax, rax
    jz .ai_fail_prefetch_alloc
    mov r12, rax                ; R12 = allocated virtual base

    ; Verify aligned allocations stat
    mov rax, [sys_prefetch_aligned_allocations]
    cmp rax, 1
    jne .ai_fail_prefetch_stats

    ; Verify virtual address is 64-byte aligned
    mov rax, r12
    test rax, 63
    jnz .ai_fail_prefetch_align

    ; Test hint function
    mov rdi, r12
    mov rsi, 8192
    call prefetch_alloc_hint
    cmp rax, 1
    jne .ai_fail_prefetch_hint

    mov rsi, msg_ai_prefetch_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 36.6 Quantized Memory Layout Manager Test
    ; -------------------------------------------------------------------------
    ; Populate source byte buffer
    lea rdi, [sys_quant_src_bytes]
    mov byte [rdi], 3
    mov byte [rdi + 1], 14
    mov byte [rdi + 2], 0
    mov byte [rdi + 3], 9
    mov byte [rdi + 4], 12
    mov byte [rdi + 5], 1
    mov byte [rdi + 6], 15
    mov byte [rdi + 7], 6

    ; Pack 8 bytes into 4 bytes (AVX2-aligned BSS destination)
    lea rdi, [sys_quant_src_bytes]
    lea rsi, [sys_quant_packed_bytes]
    mov rdx, 8
    call quant_layout_pack_int4
    cmp rax, 4
    jne .ai_fail_quant_pack

    ; Verify telemetry counters
    mov rax, [sys_quant_packed_weights]
    cmp rax, 1
    jne .ai_fail_quant_stats
    mov rax, [sys_quant_avx2_alignments]
    cmp rax, 1
    jne .ai_fail_quant_stats

    ; Unpack 4 bytes back to 8 bytes
    lea rdi, [sys_quant_packed_bytes]
    lea rsi, [sys_quant_unpacked_bytes]
    mov rdx, 8
    call quant_layout_unpack_int4
    cmp rax, 8
    jne .ai_fail_quant_unpack

    ; Verify unpacked weights match original source
    lea rdi, [sys_quant_src_bytes]
    lea rsi, [sys_quant_unpacked_bytes]
    mov rcx, 8
.verify_quant_bytes:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .ai_fail_quant_mismatch
    inc rdi
    inc rsi
    loop .verify_quant_bytes

    mov rsi, msg_ai_quant_ok
    call uart_print_str

    ; All AI/Inference memory tests passed!
    mov rsi, msg_ai_mem_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .rt_mem_test

.ai_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.ai_fail_tensor_init:
    mov rsi, msg_ai_fail_tensor_init
    call uart_print_str
    jmp .ai_panic

.ai_fail_tensor_count:
    mov rsi, msg_ai_fail_tensor_count
    call uart_print_str
    jmp .ai_panic

.ai_fail_tensor_alloc:
    mov rsi, msg_ai_fail_tensor_alloc
    call uart_print_str
    jmp .ai_panic

.ai_fail_tensor_allocated_count:
    mov rsi, msg_ai_fail_tensor_allocated_count
    call uart_print_str
    jmp .ai_panic

.ai_fail_tensor_distinct:
    mov rsi, msg_ai_fail_tensor_distinct
    call uart_print_str
    jmp .ai_panic

.ai_fail_tensor_free:
    mov rsi, msg_ai_fail_tensor_free
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_init:
    mov rsi, msg_ai_fail_weight_init
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_config:
    mov rsi, msg_ai_fail_weight_config
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_pin:
    mov rsi, msg_ai_fail_weight_pin
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_stats:
    mov rsi, msg_ai_fail_weight_stats
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_unpin:
    mov rsi, msg_ai_fail_weight_unpin
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_evicted:
    mov rsi, msg_ai_fail_weight_evicted
    call uart_print_str
    jmp .ai_panic

.ai_fail_weight_access:
    mov rsi, msg_ai_fail_weight_access
    call uart_print_str
    jmp .ai_panic

.ai_fail_kv_init:
    mov rsi, msg_ai_fail_kv_init
    call uart_print_str
    jmp .ai_panic

.ai_fail_kv_alloc:
    mov rsi, msg_ai_fail_kv_alloc
    call uart_print_str
    jmp .ai_panic

.ai_fail_kv_stats:
    mov rsi, msg_ai_fail_kv_stats
    call uart_print_str
    jmp .ai_panic

.ai_fail_kv_free:
    mov rsi, msg_ai_fail_kv_free
    call uart_print_str
    jmp .ai_panic

.ai_fail_turboquant_pack:
    mov rsi, msg_ai_fail_turboquant_pack
    call uart_print_str
    jmp .ai_panic

.ai_fail_turboquant_unpack:
    mov rsi, msg_ai_fail_turboquant_unpack
    call uart_print_str
    jmp .ai_panic

.ai_fail_turboquant_mismatch:
    mov rsi, msg_ai_fail_turboquant_mismatch
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_init:
    mov rsi, msg_ai_fail_act_init
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_register:
    mov rsi, msg_ai_fail_act_register
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_stats:
    mov rsi, msg_ai_fail_act_stats
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_map:
    mov rsi, msg_ai_fail_act_map
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_translate:
    mov rsi, msg_ai_fail_act_translate
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_distinct:
    mov rsi, msg_ai_fail_act_distinct
    call uart_print_str
    jmp .ai_panic

.ai_fail_act_unmap:
    mov rsi, msg_ai_fail_act_unmap
    call uart_print_str
    jmp .ai_panic

.ai_fail_prefetch_alloc:
    mov rsi, msg_ai_fail_prefetch_alloc
    call uart_print_str
    jmp .ai_panic

.ai_fail_prefetch_stats:
    mov rsi, msg_ai_fail_prefetch_stats
    call uart_print_str
    jmp .ai_panic

.ai_fail_prefetch_align:
    mov rsi, msg_ai_fail_prefetch_align
    call uart_print_str
    jmp .ai_panic

.ai_fail_prefetch_hint:
    mov rsi, msg_ai_fail_prefetch_hint
    call uart_print_str
    jmp .ai_panic

.ai_fail_quant_pack:
    mov rsi, msg_ai_fail_quant_pack
    call uart_print_str
    jmp .ai_panic

.ai_fail_quant_stats:
    mov rsi, msg_ai_fail_quant_stats
    call uart_print_str
    jmp .ai_panic

.ai_fail_quant_unpack:
    mov rsi, msg_ai_fail_quant_unpack
    call uart_print_str
    jmp .ai_panic

.ai_fail_quant_mismatch:
    mov rsi, msg_ai_fail_quant_mismatch
    call uart_print_str
    jmp .ai_panic

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 37. Real-Time Memory Management Test
    ; =========================================================================
.rt_mem_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_rt_mem_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 37.1 & 37.2 mlockall & Pre-fault Memory Test
    ; -------------------------------------------------------------------------
    ; Create a test VMA: start=0x70200000, size=8192, flags=VMA_READ|VMA_WRITE
    mov rdi, 0x70200000
    mov rsi, 8192
    mov rdx, 0x03                   ; normal mapped flags
    call vma_create
    test rax, rax
    jz .rt_fail_vma
    mov r12, rax                    ; R12 = VMA ptr

    ; Pre-fault the VMA (write mode)
    mov rdi, r12
    mov rsi, 1
    call rt_prefault_vma
    cmp rax, 1
    jne .rt_fail_prefault

    ; Verify pre-faulted count is at least 2 (the VMA range is 2 pages)
    mov rax, [sys_rt_prefaulted_pages]
    cmp rax, 2
    jb .rt_fail_prefault_count

    ; Verify virtual address is mapped (present in tables)
    mov rdi, 0x70200000
    call virt_translate
    test rax, rax
    jz .rt_fail_prefault_map

    ; Lock all mappings
    mov rdi, 1                      ; MCL_CURRENT
    call rt_mlockall
    cmp rax, 1
    jne .rt_fail_mlockall

    ; Verify active flag & locked pages count
    mov rax, [sys_rt_mlockall_active]
    cmp rax, 1
    jne .rt_fail_mlock_active
    mov rax, [sys_rt_locked_pages]
    cmp rax, 2
    jb .rt_fail_locked_count

    ; Verify specific page locked query
    mov rdi, 0x70200000
    call rt_is_locked
    cmp rax, 1
    jne .rt_fail_locked_verify
    mov rdi, 0x70500000
    call rt_is_locked
    test rax, rax
    jnz .rt_fail_locked_verify

    ; Unlock mappings
    call rt_munlockall
    cmp rax, 1
    jne .rt_fail_munlockall

    ; Verify cleared state
    mov rax, [sys_rt_mlockall_active]
    test rax, rax
    jnz .rt_fail_mlock_active
    mov rax, [sys_rt_locked_pages]
    test rax, rax
    jnz .rt_fail_locked_count

    ; Clean up VMA
    mov rdi, r12
    call vma_destroy

    mov rsi, msg_rt_mlock_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 37.3 Deterministic Allocator Test (TLSF-like)
    ; -------------------------------------------------------------------------
    lea rdi, [sys_rt_det_test_pool]
    mov rsi, 65536                  ; 64KB pool
    call rt_det_alloc_init
    cmp rax, 1
    jne .rt_fail_det_init

    ; Allocate Block A: 40 bytes (maps to class 2, 64-byte size)
    mov rdi, 40
    call rt_det_alloc
    test rax, rax
    jz .rt_fail_det_alloc
    mov r12, rax                    ; R12 = Block A ptr

    ; Verify stats
    mov rax, [sys_rt_det_allocated_bytes]
    cmp rax, 64
    jne .rt_fail_det_stats

    ; Allocate Block B: 120 bytes (maps to class 3, 128-byte size)
    mov rdi, 120
    call rt_det_alloc
    test rax, rax
    jz .rt_fail_det_alloc
    mov r13, rax                    ; R13 = Block B ptr

    ; Verify stats
    mov rax, [sys_rt_det_allocated_bytes]
    cmp rax, 192                    ; 64 + 128
    jne .rt_fail_det_stats

    ; Free Block A
    mov rdi, r12
    call rt_det_free
    cmp rax, 1
    jne .rt_fail_det_free

    ; Verify stats
    mov rax, [sys_rt_det_allocated_bytes]
    cmp rax, 128
    jne .rt_fail_det_stats
    mov rax, [sys_rt_det_free_blocks]
    cmp rax, 1
    jne .rt_fail_det_stats

    ; Allocate Block C: 30 bytes (maps to class 1, 32-byte size)
    mov rdi, 30
    call rt_det_alloc
    test rax, rax
    jz .rt_fail_det_alloc
    mov r14, rax                    ; R14 = Block C ptr

    ; Verify stats
    mov rax, [sys_rt_det_allocated_bytes]
    cmp rax, 160                    ; 128 + 32
    jne .rt_fail_det_stats

    ; Free Block B and C
    mov rdi, r13
    call rt_det_free
    cmp rax, 1
    jne .rt_fail_det_free

    mov rdi, r14
    call rt_det_free
    cmp rax, 1
    jne .rt_fail_det_free

    ; Verify final stats are 0
    mov rax, [sys_rt_det_allocated_bytes]
    test rax, rax
    jnz .rt_fail_det_stats

    mov rsi, msg_rt_det_alloc_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 37.4 Interrupt-Safe Allocator Test (Lock-Free Ring)
    ; -------------------------------------------------------------------------
    call rt_isr_alloc_init
    cmp rax, 1
    jne .rt_fail_isr_init

    ; Verify head/tail are 0/16
    mov rax, [sys_rt_isr_head]
    test rax, rax
    jnz .rt_fail_isr_stats
    mov rax, [sys_rt_isr_tail]
    cmp rax, 16
    jne .rt_fail_isr_stats

    ; Lock-free pop a page from interrupt context
    call rt_isr_alloc
    test rax, rax
    jz .rt_fail_isr_alloc
    mov r12, rax                    ; R12 = physical page frame address

    ; Verify updated head & stats
    mov rax, [sys_rt_isr_head]
    cmp rax, 1
    jne .rt_fail_isr_stats
    mov rax, [sys_rt_isr_allocations]
    cmp rax, 1
    jne .rt_fail_isr_stats

    ; Lock-free push page back to pool
    mov rdi, r12
    call rt_isr_free
    cmp rax, 1
    jne .rt_fail_isr_free

    ; Verify updated tail & stats
    mov rax, [sys_rt_isr_tail]
    cmp rax, 17
    jne .rt_fail_isr_stats
    mov rax, [sys_rt_isr_freed]
    cmp rax, 1
    jne .rt_fail_isr_stats

    mov rsi, msg_rt_isr_alloc_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 37.5 Memory Reservation Test
    ; -------------------------------------------------------------------------
    ; Reserve 4 Megabytes at boot
    mov rdi, 4
    call rt_reserve_boot_memory
    test rax, rax
    jz .rt_fail_reserve_boot

    ; Backup array for indexing free operations
    call rt_reserve_backup

    ; Verify stats
    mov rax, [sys_rt_reserved_total_bytes]
    cmp rax, 4194304
    jne .rt_fail_reserve_stats
    mov rax, [sys_rt_reserved_used_bytes]
    test rax, rax
    jnz .rt_fail_reserve_stats

    ; Slice 2 pages (8KB) from reserve
    mov rdi, 2
    call rt_reserve_alloc
    test rax, rax
    jz .rt_fail_reserve_alloc
    mov r12, rax                    ; R12 = physical address base

    ; Verify stats
    mov rax, [sys_rt_reserved_used_bytes]
    cmp rax, 8192
    jne .rt_fail_reserve_stats

    ; Release back to reserve
    mov rdi, r12
    mov rsi, 2
    call rt_reserve_free
    cmp rax, 1
    jne .rt_fail_reserve_free

    ; Verify final stats
    mov rax, [sys_rt_reserved_used_bytes]
    test rax, rax
    jnz .rt_fail_reserve_stats

    mov rsi, msg_rt_reserve_ok
    call uart_print_str

    ; All Real-Time Memory tests passed!
    mov rsi, msg_rt_mem_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .ras_mem_test

.rt_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.rt_fail_vma:
    mov rsi, msg_rt_fail_vma
    call uart_print_str
    jmp .rt_panic

.rt_fail_prefault:
    mov rsi, msg_rt_fail_prefault
    call uart_print_str
    jmp .rt_panic

.rt_fail_prefault_count:
    mov rsi, msg_rt_fail_prefault_count
    call uart_print_str
    jmp .rt_panic

.rt_fail_prefault_map:
    mov rsi, msg_rt_fail_prefault_map
    call uart_print_str
    jmp .rt_panic

.rt_fail_mlockall:
    mov rsi, msg_rt_fail_mlockall
    call uart_print_str
    jmp .rt_panic

.rt_fail_mlock_active:
    mov rsi, msg_rt_fail_mlock_active
    call uart_print_str
    jmp .rt_panic

.rt_fail_locked_count:
    mov rsi, msg_rt_fail_locked_count
    call uart_print_str
    jmp .rt_panic

.rt_fail_locked_verify:
    mov rsi, msg_rt_fail_locked_verify
    call uart_print_str
    jmp .rt_panic

.rt_fail_munlockall:
    mov rsi, msg_rt_fail_munlockall
    call uart_print_str
    jmp .rt_panic

.rt_fail_det_init:
    mov rsi, msg_rt_fail_det_init
    call uart_print_str
    jmp .rt_panic

.rt_fail_det_alloc:
    mov rsi, msg_rt_fail_det_alloc
    call uart_print_str
    jmp .rt_panic

.rt_fail_det_stats:
    mov rsi, msg_rt_fail_det_stats
    call uart_print_str
    jmp .rt_panic

.rt_fail_det_free:
    mov rsi, msg_rt_fail_det_free
    call uart_print_str
    jmp .rt_panic

.rt_fail_isr_init:
    mov rsi, msg_rt_fail_isr_init
    call uart_print_str
    jmp .rt_panic

.rt_fail_isr_stats:
    mov rsi, msg_rt_fail_isr_stats
    call uart_print_str
    jmp .rt_panic

.rt_fail_isr_alloc:
    mov rsi, msg_rt_fail_isr_alloc
    call uart_print_str
    jmp .rt_panic

.rt_fail_isr_free:
    mov rsi, msg_rt_fail_isr_free
    call uart_print_str
    jmp .rt_panic

.rt_fail_reserve_boot:
    mov rsi, msg_rt_fail_reserve_boot
    call uart_print_str
    jmp .rt_panic

.rt_fail_reserve_stats:
    mov rsi, msg_rt_fail_reserve_stats
    call uart_print_str
    jmp .rt_panic

.rt_fail_reserve_alloc:
    mov rsi, msg_rt_fail_reserve_alloc
    call uart_print_str
    jmp .rt_panic

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

    ; =========================================================================
    ; 38. Memory Error Handling (RAS) Test
    ; =========================================================================
.ras_mem_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_ras_mem_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 38.1 ECC Memory Error Detection Test
    ; -------------------------------------------------------------------------
    call ras_ecc_init
    cmp rax, 1
    jne .ras_fail_ecc_init

    ; Report correctable single-bit error at DIMM 1 range
    mov rdi, 0x15004000
    mov rsi, 1                      ; single-bit error
    call ras_ecc_report
    cmp rax, 1
    jne .ras_fail_ecc_report

    ; Verify counters
    mov rax, [sys_ras_ecc_single_bit_errors]
    cmp rax, 1
    jne .ras_fail_ecc_counters

    mov rsi, msg_ras_ecc_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 38.2 & 38.3 MCE Handler & Poison Page Handling Test
    ; -------------------------------------------------------------------------
    call ras_mce_init
    cmp rax, 1
    jne .ras_fail_mce_init

    ; Report uncorrectable double-bit MCE in user address space (0x15004000)
    mov rdi, 0x15004000
    mov rsi, 1                      ; uncorrectable
    call ras_mce_handler
    cmp rax, 1
    jne .ras_fail_mce_recover

    ; Verify MCE stats
    mov rax, [sys_ras_mce_occurred]
    cmp rax, 1
    jne .ras_fail_mce_stats
    mov rax, [sys_ras_mce_recovered]
    cmp rax, 1
    jne .ras_fail_mce_stats

    ; Verify page is poisoned
    mov rdi, 0x15004000
    call ras_is_poisoned
    cmp rax, 1
    jne .ras_fail_poison_verify

    mov rax, [sys_ras_poisoned_pages]
    cmp rax, 1
    jne .ras_fail_poison_verify

    ; Verify healthy page is not poisoned
    mov rdi, 0x18000000
    call ras_is_poisoned
    test rax, rax
    jnz .ras_fail_poison_verify

    ; Verify uncorrectable error in kernel space (0x00500000) is fatal (returns 0)
    mov rdi, 0x00500000
    mov rsi, 1                      ; uncorrectable
    call ras_mce_handler
    test rax, rax
    jnz .ras_fail_mce_fatal

    mov rsi, msg_ras_mce_poison_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 38.4 DIMM Failure Prediction Test
    ; -------------------------------------------------------------------------
    ; DIMM 1 currently has 1 single-bit error + 1 poisoned event = 2 total.
    ; Report 3 more correctable errors to trigger threshold (5) failure prediction.
    mov r12, 3
.log_dimm_loop:
    mov rdi, 0x15004000
    mov rsi, 1                      ; correctable
    call ras_ecc_report
    cmp rax, 1
    jne .ras_fail_dimm_log
    dec r12
    jnz .log_dimm_loop

    ; Verify migration occurred
    mov rax, [sys_ras_dimm_migrated_pages]
    cmp rax, 1
    jne .ras_fail_dimm_migrate

    ; Verify DIMM 1 errors were reset after migration
    mov rax, [sys_ras_dimm_errors_dimm1]
    test rax, rax
    jnz .ras_fail_dimm_stats

    mov rsi, msg_ras_dimm_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 38.5 Memory Scrubbing Test
    ; -------------------------------------------------------------------------
    call ras_scrub_init
    cmp rax, 1
    jne .ras_fail_scrub_init

    ; Scrub first 10 pages
    mov rdi, 10
    call ras_scrub_tick
    cmp rax, 10
    jne .ras_fail_scrub_tick

    mov rax, [sys_ras_scrubbed_pages]
    cmp rax, 10
    jne .ras_fail_scrub_stats

    ; Scrub deep to reach the mock faulty address 0x15004000.
    ; Next addr starts at 0x1000A000 (after 10 pages).
    ; Address 0x15004000 is 0x4FFA000 bytes away = 20474 pages.
    mov rdi, 20474
    call ras_scrub_tick
    cmp rax, 20474
    jne .ras_fail_scrub_tick

    ; Verify scrubber intercepted the bit flip and reported it
    mov rax, [sys_ras_scrub_errors_detected]
    cmp rax, 1
    jne .ras_fail_scrub_flip

    mov rsi, msg_ras_scrub_ok
    call uart_print_str

    ; All RAS Memory tests passed!
    mov rsi, msg_ras_mem_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .cxl_mem_test

.ras_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.ras_fail_ecc_init:
    mov rsi, msg_ras_fail_ecc_init
    call uart_print_str
    jmp .ras_panic

.ras_fail_ecc_report:
    mov rsi, msg_ras_fail_ecc_report
    call uart_print_str
    jmp .ras_panic

.ras_fail_ecc_counters:
    mov rsi, msg_ras_fail_ecc_counters
    call uart_print_str
    jmp .ras_panic

.ras_fail_mce_init:
    mov rsi, msg_ras_fail_mce_init
    call uart_print_str
    jmp .ras_panic

.ras_fail_mce_recover:
    mov rsi, msg_ras_fail_mce_recover
    call uart_print_str
    jmp .ras_panic

.ras_fail_mce_stats:
    mov rsi, msg_ras_fail_mce_stats
    call uart_print_str
    jmp .ras_panic

.ras_fail_poison_verify:
    mov rsi, msg_ras_fail_poison_verify
    call uart_print_str
    jmp .ras_panic

.ras_fail_mce_fatal:
    mov rsi, msg_ras_fail_mce_fatal
    call uart_print_str
    jmp .ras_panic

.ras_fail_dimm_log:
    mov rsi, msg_ras_fail_dimm_log
    call uart_print_str
    jmp .ras_panic

.ras_fail_dimm_migrate:
    mov rsi, msg_ras_fail_dimm_migrate
    call uart_print_str
    jmp .ras_panic

.ras_fail_dimm_stats:
    mov rsi, msg_ras_fail_dimm_stats
    call uart_print_str
    jmp .ras_panic

.ras_fail_scrub_init:
    mov rsi, msg_ras_fail_scrub_init
    call uart_print_str
    jmp .ras_panic

.ras_fail_scrub_tick:
    mov rsi, msg_ras_fail_scrub_tick
    call uart_print_str
    jmp .ras_panic

.ras_fail_scrub_stats:
    mov rsi, msg_ras_fail_scrub_stats
    call uart_print_str
    jmp .ras_panic

.ras_fail_scrub_flip:
    mov rsi, msg_ras_fail_scrub_flip
    call uart_print_str
    jmp .ras_panic

    ; =========================================================================
    ; 39. CXL Memory Test
    ; =========================================================================
.cxl_mem_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_cxl_mem_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 39.1 CXL Type 1 Device Support Test
    ; -------------------------------------------------------------------------
    call cxl_t1_init
    cmp rax, 1
    jne .cxl_fail_t1_init

    mov rax, [sys_cxl_t1_active_devices]
    cmp rax, 1
    jne .cxl_fail_t1_active

    call cxl_t1_get_bandwidth
    cmp rax, 64000
    jne .cxl_fail_t1_bandwidth

    mov rsi, msg_cxl_t1_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 39.2 CXL Type 3 Memory Expansion Test
    ; -------------------------------------------------------------------------
    call cxl_t3_init
    cmp rax, 1
    jne .cxl_fail_t3_init

    ; Hot-plug a 2TB memory region at base address 0x400000000
    mov rdi, 0x400000000
    mov rsi, 2048                    ; 2048 GB (2TB)
    call cxl_t3_hotplug
    cmp rax, 1
    jne .cxl_fail_t3_hotplug

    mov rax, [sys_cxl_t3_device_count]
    cmp rax, 1
    jne .cxl_fail_t3_stats

    mov rax, [sys_cxl_t3_total_capacity_gb]
    cmp rax, 2048
    jne .cxl_fail_t3_stats

    mov rsi, msg_cxl_t3_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 39.3 CXL Memory Tiering Test
    ; -------------------------------------------------------------------------
    call cxl_tier_init
    cmp rax, 1
    jne .cxl_fail_tier_init

    ; Demote page from DRAM to CXL
    mov rdi, 0x75000000
    call cxl_tier_demote
    cmp rax, 1
    jne .cxl_fail_tier_demote

    mov rax, [sys_cxl_demoted_pages]
    cmp rax, 1
    jne .cxl_fail_tier_stats

    ; Promote page from CXL back to DRAM
    mov rdi, 0x75000000
    call cxl_tier_promote
    cmp rax, 1
    jne .cxl_fail_tier_promote

    mov rax, [sys_cxl_promoted_pages]
    cmp rax, 1
    jne .cxl_fail_tier_stats

    mov rsi, msg_cxl_tier_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 39.4 CXL Persistent Memory Test
    ; -------------------------------------------------------------------------
    call cxl_pmem_init
    cmp rax, 1
    jne .cxl_fail_pmem_init

    ; Flush 128 bytes to KV cache persistent memory
    mov rdi, 0x76000000
    mov rsi, 128
    call cxl_pmem_flush
    cmp rax, 1
    jne .cxl_fail_pmem_flush

    mov rax, [sys_cxl_pmem_flushed_bytes]
    cmp rax, 128
    jne .cxl_fail_pmem_stats

    mov rsi, msg_cxl_pmem_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 39.5 CXL Fabric Manager Integration Test
    ; -------------------------------------------------------------------------
    call cxl_fabric_init
    cmp rax, 1
    jne .cxl_fail_fabric_init

    ; Allocate dynamic fabric slice of 512GB
    mov rdi, 512
    call cxl_fabric_allocate
    test rax, rax
    jz .cxl_fail_fabric_alloc
    mov r12, rax                     ; save slice ID

    mov r13, [sys_cxl_fabric_slices_allocated]
    cmp r13, 1
    jne .cxl_fail_fabric_stats

    mov r13, [sys_cxl_fabric_allocated_gb]
    cmp r13, 512
    jne .cxl_fail_fabric_stats

    ; Release dynamic slice
    mov rdi, r12
    mov rsi, 512
    call cxl_fabric_release
    cmp rax, 1
    jne .cxl_fail_fabric_release

    mov rax, [sys_cxl_fabric_slices_allocated]
    test rax, rax
    jnz .cxl_fail_fabric_stats

    mov rax, [sys_cxl_fabric_allocated_gb]
    test rax, rax
    jnz .cxl_fail_fabric_stats

    mov rsi, msg_cxl_fabric_ok
    call uart_print_str

    ; All CXL Memory tests passed!
    mov rsi, msg_cxl_mem_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    jmp .prof_mem_test

.cxl_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.cxl_fail_t1_init:
    mov rsi, msg_cxl_fail_t1_init
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_t1_active:
    mov rsi, msg_cxl_fail_t1_active
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_t1_bandwidth:
    mov rsi, msg_cxl_fail_t1_bandwidth
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_t3_init:
    mov rsi, msg_cxl_fail_t3_init
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_t3_hotplug:
    mov rsi, msg_cxl_fail_t3_hotplug
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_t3_stats:
    mov rsi, msg_cxl_fail_t3_stats
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_tier_init:
    mov rsi, msg_cxl_fail_tier_init
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_tier_demote:
    mov rsi, msg_cxl_fail_tier_demote
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_tier_promote:
    mov rsi, msg_cxl_fail_tier_promote
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_tier_stats:
    mov rsi, msg_cxl_fail_tier_stats
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_pmem_init:
    mov rsi, msg_cxl_fail_pmem_init
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_pmem_flush:
    mov rsi, msg_cxl_fail_pmem_flush
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_pmem_stats:
    mov rsi, msg_cxl_fail_pmem_stats
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_fabric_init:
    mov rsi, msg_cxl_fail_fabric_init
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_fabric_alloc:
    mov rsi, msg_cxl_fail_fabric_alloc
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_fabric_stats:
    mov rsi, msg_cxl_fail_fabric_stats
    call uart_print_str
    jmp .cxl_panic

.cxl_fail_fabric_release:
    mov rsi, msg_cxl_fail_fabric_release
    call uart_print_str
    jmp .cxl_panic

    ; =========================================================================
    ; 40. Memory Profiling & Telemetry Test
    ; =========================================================================
.prof_mem_test:
    push r12
    push r13
    push r14
    push r15

    mov rsi, msg_prof_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 40.1 Hardware Performance Counters Test
    ; -------------------------------------------------------------------------
    call hw_perf_init
    cmp rax, 1
    jne .prof_fail_hw_init

    call hw_perf_sample
    cmp rax, 1
    jne .prof_fail_hw_sample

    mov rax, [sys_hw_perf_llc_miss_rate]
    cmp rax, 12
    jne .prof_fail_hw_stats

    mov rax, [sys_hw_perf_dram_bw_mbps]
    cmp rax, 45000
    jne .prof_fail_hw_stats

    mov rax, [sys_hw_perf_latency_ns]
    cmp rax, 85
    jne .prof_fail_hw_stats

    mov rsi, msg_prof_hw_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 40.2 Allocation Site Tracking Test
    ; -------------------------------------------------------------------------
    call alloc_site_init
    cmp rax, 1
    jne .prof_fail_site_init

    mov rdi, 0x100080                ; Call site instruction pointer
    mov rsi, 4096                    ; 4KB allocation
    call alloc_site_record
    cmp rax, 1
    jne .prof_fail_site_record

    mov rax, [sys_alloc_site_count]
    cmp rax, 1
    jne .prof_fail_site_stats

    mov rax, [sys_alloc_site_total_bytes]
    cmp rax, 4096
    jne .prof_fail_site_stats

    mov rsi, msg_prof_site_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 40.3 Memory Timeline Recorder Test
    ; -------------------------------------------------------------------------
    call timeline_init
    cmp rax, 1
    jne .prof_fail_time_init

    mov rdi, 1                       ; Event type: Alloc
    mov rsi, 0x2000000               ; Virtual Address
    mov rdx, 8192                    ; 8KB
    call timeline_log
    cmp rax, 1
    jne .prof_fail_time_log

    mov rax, [sys_timeline_event_count]
    cmp rax, 1
    jne .prof_fail_time_stats

    mov rsi, msg_prof_time_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 40.4 NUMA Hit/Miss Counters Test
    ; -------------------------------------------------------------------------
    call numa_stat_init
    cmp rax, 1
    jne .prof_fail_numa_init

    mov rdi, 0                       ; Node 0
    mov rsi, 1                       ; Local Hit
    call numa_stat_record
    cmp rax, 1
    jne .prof_fail_numa_record

    mov rdi, 1                       ; Node 1
    mov rsi, 0                       ; Remote Miss
    call numa_stat_record
    cmp rax, 1
    jne .prof_fail_numa_record

    mov rax, [sys_numa_local_hits]
    cmp rax, 1
    jne .prof_fail_numa_stats

    mov rax, [sys_numa_remote_misses]
    cmp rax, 1
    jne .prof_fail_numa_stats

    mov rsi, msg_prof_numa_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 40.5 Memory Bandwidth Saturation Detector Test
    ; -------------------------------------------------------------------------
    call bw_sat_init
    cmp rax, 1
    jne .prof_fail_sat_init

    mov rdi, 45000                   ; 45 GB/s (below threshold)
    call bw_sat_check
    test rax, rax
    jnz .prof_fail_sat_check

    mov rdi, 55000                   ; 55 GB/s (above threshold)
    call bw_sat_check
    cmp rax, 1
    jne .prof_fail_sat_check

    mov rax, [sys_bw_sat_alerts]
    cmp rax, 1
    jne .prof_fail_sat_stats

    mov rsi, msg_prof_sat_ok
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 40.6 Inference Memory Profiler Test
    ; -------------------------------------------------------------------------
    call inf_prof_init
    cmp rax, 1
    jne .prof_fail_inf_init

    ; Record Layer 1: weights=1MB, activations=2MB, kv_cache=512KB
    mov rdi, 1
    mov rsi, 1048576
    mov rdx, 2097152
    mov rcx, 524288
    call inf_prof_record_layer
    cmp rax, 1
    jne .prof_fail_inf_record

    ; Record Layer 2: weights=1MB, activations=1MB, kv_cache=512KB
    mov rdi, 2
    mov rsi, 1048576
    mov rdx, 1048576
    mov rcx, 524288
    call inf_prof_record_layer
    cmp rax, 1
    jne .prof_fail_inf_record

    mov rax, [sys_inf_prof_weight_bytes]
    cmp rax, 2097152
    jne .prof_fail_inf_stats

    mov rax, [sys_inf_prof_kv_cache_bytes]
    cmp rax, 1048576
    jne .prof_fail_inf_stats

    mov rax, [sys_inf_prof_peak_activation_bytes]
    cmp rax, 2097152
    jne .prof_fail_inf_stats

    mov rsi, msg_prof_inf_ok
    call uart_print_str

    ; All profiling tests passed!
    mov rsi, msg_prof_test_passed
    call uart_print_str

    pop r15
    pop r14
    pop r13
    pop r12
    ret

.prof_panic:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp .panic

.prof_fail_hw_init:
    mov rsi, msg_prof_fail_hw_init
    call uart_print_str
    jmp .prof_panic

.prof_fail_hw_sample:
    mov rsi, msg_prof_fail_hw_sample
    call uart_print_str
    jmp .prof_panic

.prof_fail_hw_stats:
    mov rsi, msg_prof_fail_hw_stats
    call uart_print_str
    jmp .prof_panic

.prof_fail_site_init:
    mov rsi, msg_prof_fail_site_init
    call uart_print_str
    jmp .prof_panic

.prof_fail_site_record:
    mov rsi, msg_prof_fail_site_record
    call uart_print_str
    jmp .prof_panic

.prof_fail_site_stats:
    mov rsi, msg_prof_fail_site_stats
    call uart_print_str
    jmp .prof_panic

.prof_fail_time_init:
    mov rsi, msg_prof_fail_time_init
    call uart_print_str
    jmp .prof_panic

.prof_fail_time_log:
    mov rsi, msg_prof_fail_time_log
    call uart_print_str
    jmp .prof_panic

.prof_fail_time_stats:
    mov rsi, msg_prof_fail_time_stats
    call uart_print_str
    jmp .prof_panic

.prof_fail_numa_init:
    mov rsi, msg_prof_fail_numa_init
    call uart_print_str
    jmp .prof_panic

.prof_fail_numa_record:
    mov rsi, msg_prof_fail_numa_record
    call uart_print_str
    jmp .prof_panic

.prof_fail_numa_stats:
    mov rsi, msg_prof_fail_numa_stats
    call uart_print_str
    jmp .prof_panic

.prof_fail_sat_init:
    mov rsi, msg_prof_fail_sat_init
    call uart_print_str
    jmp .prof_panic

.prof_fail_sat_check:
    mov rsi, msg_prof_fail_sat_check
    call uart_print_str
    jmp .prof_panic

.prof_fail_sat_stats:
    mov rsi, msg_prof_fail_sat_stats
    call uart_print_str
    jmp .prof_panic

.prof_fail_inf_init:
    mov rsi, msg_prof_fail_inf_init
    call uart_print_str
    jmp .prof_panic

.prof_fail_inf_record:
    mov rsi, msg_prof_fail_inf_record
    call uart_print_str
    jmp .prof_panic

.prof_fail_inf_stats:
    mov rsi, msg_prof_fail_inf_stats
    call uart_print_str
    jmp .prof_panic

.share_fail_alloc_src_pml4:
    mov rsi, msg_share_fail_alloc_src_pml4
    jmp .share_panic

.share_fail_alloc_dest_pml4:
    mov rsi, msg_share_fail_alloc_dest_pml4
    jmp .share_panic

.share_fail_alloc_page1:
    mov cr3, r15
    mov rsi, msg_share_fail_alloc_page1
    jmp .share_panic

.share_fail_map1:
    mov cr3, r15
    mov rsi, msg_share_fail_map1
    jmp .share_panic

.share_fail_alloc_page2:
    mov cr3, r15
    mov rsi, msg_share_fail_alloc_page2
    jmp .share_panic

.share_fail_map2:
    mov cr3, r15
    mov rsi, msg_share_fail_map2
    jmp .share_panic

.share_fail_call:
    mov rsi, msg_share_fail_call
    jmp .share_panic

.share_fail_verify_val1:
    mov cr3, r15
    mov rsi, msg_share_fail_verify_val1
    jmp .share_panic

.share_fail_verify_val2:
    mov cr3, r15
    mov rsi, msg_share_fail_verify_val2
    jmp .share_panic

.share_fail_ro_check:
    mov rsi, msg_share_fail_ro_check
    jmp .share_panic

.share_fail_desc_not_found:
    mov rsi, msg_share_fail_desc_not_found
    jmp .share_panic

.share_fail_refcount:
    mov rsi, msg_share_fail_refcount
    jmp .share_panic

.share_fail_release_1:
    mov rsi, msg_share_fail_release_1
    jmp .share_panic

.share_fail_refcount_1:
    mov rsi, msg_share_fail_refcount_1
    jmp .share_panic

.share_fail_release_2:
    mov rsi, msg_share_fail_release_2
    jmp .share_panic

.share_fail_desc_not_cleared:
    mov rsi, msg_share_fail_desc_not_cleared
    jmp .share_panic

.reap_fail_pml4:
    mov rsi, msg_reap_fail_pml4
    jmp .share_panic

.reap_fail_alloc1:
    mov rsi, msg_reap_fail_alloc1
    jmp .share_panic

.reap_fail_map1:
    mov rsi, msg_reap_fail_map1
    jmp .share_panic

.reap_fail_count1:
    mov rsi, msg_reap_fail_count1
    jmp .share_panic

.reap_fail_walk:
    mov rsi, msg_reap_fail_walk
    jmp .share_panic

.reap_fail_count2:
    mov rsi, msg_reap_fail_count2
    jmp .share_panic

.reap_fail_pmd_not_cleared:
    mov rsi, msg_reap_fail_pmd_not_cleared
    jmp .share_panic

.coop_fail_queue_alloc:
    mov rsi, msg_coop_fail_queue_alloc
    jmp .share_panic

.coop_fail_slot:
    mov rsi, msg_coop_fail_slot
    jmp .share_panic

.coop_fail_request_val:
    mov rsi, msg_coop_fail_request_val
    jmp .share_panic

.coop_fail_head:
    mov rsi, msg_coop_fail_head
    jmp .share_panic

.coop_fail_tail:
    mov rsi, msg_coop_fail_tail
    jmp .share_panic

.coop_fail_phys_val:
    mov rsi, msg_coop_fail_phys_val
    jmp .share_panic

.zone_fail_init:
    mov rsi, msg_zone_fail_init
    jmp .share_panic

.zone_fail_flag:
    mov rsi, msg_zone_fail_flag
    jmp .share_panic

.zone_fail_alloc:
    mov rsi, msg_zone_fail_alloc
    jmp .share_panic

.zone_fail_movable_alloc:
    mov rsi, msg_zone_fail_movable_alloc
    jmp .share_panic

.aslr_fail_alloc1:
    mov rsi, msg_aslr_fail_alloc1
    jmp .share_panic

.aslr_fail_alloc2:
    mov rsi, msg_aslr_fail_alloc2
    jmp .share_panic

.aslr_fail_map1:
    mov rsi, msg_aslr_fail_map1
    jmp .share_panic

.aslr_fail_sig1:
    mov rsi, msg_aslr_fail_sig1
    jmp .share_panic

.aslr_fail_translate:
    mov rsi, msg_aslr_fail_translate
    jmp .share_panic

.aslr_fail_sig2:
    mov rsi, msg_aslr_fail_sig2
    jmp .share_panic

.pasid_fail_alloc:
    mov rsi, msg_pasid_fail_alloc
    jmp .share_panic

.pasid_fail_entry:
    mov rsi, msg_pasid_fail_entry
    jmp .share_panic

.share_panic:
    call uart_print_str
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    jmp .panic

.percpu_panic:



.panic:
    mov rsi, msg_test_failed
    call uart_print_str
    cli
.hlt_loop:
    hlt
    jmp .hlt_loop

section .data

msg_share_test_start:            db "Running Multi-Process Page Table Sharing Test...", 0x0D, 0x0A, 0
msg_share_test_passed:           db "Multi-Process Page Table Sharing Test PASSED!", 0x0D, 0x0A, 0

msg_share_fail_alloc_src_pml4:   db "Failure: Could not allocate source PML4.", 0x0D, 0x0A, 0
msg_share_fail_alloc_dest_pml4:  db "Failure: Could not allocate destination PML4.", 0x0D, 0x0A, 0
msg_share_fail_alloc_page1:      db "Failure: Could not allocate physical page 1.", 0x0D, 0x0A, 0
msg_share_fail_map1:             db "Failure: Could not map physical page 1 in source PML4.", 0x0D, 0x0A, 0
msg_share_fail_alloc_page2:      db "Failure: Could not allocate physical page 2.", 0x0D, 0x0A, 0
msg_share_fail_map2:             db "Failure: Could not map physical page 2 in source PML4.", 0x0D, 0x0A, 0
msg_share_fail_call:             db "Failure: virt_share_page_directories call returned 0.", 0x0D, 0x0A, 0
msg_share_fail_verify_val1:      db "Failure: Shared page 1 verification signature mismatch in destination PML4.", 0x0D, 0x0A, 0
msg_share_fail_verify_val2:      db "Failure: Shared page 2 verification signature mismatch in destination PML4.", 0x0D, 0x0A, 0
msg_share_fail_ro_check:         db "Failure: Read-only enforcement check failed (PD entry is writable or not present).", 0x0D, 0x0A, 0
msg_share_fail_desc_not_found:   db "Failure: Shared descriptor not found in shared_dir_table.", 0x0D, 0x0A, 0
msg_share_fail_refcount:         db "Failure: Shared descriptor ref_count is not 2.", 0x0D, 0x0A, 0
msg_share_fail_release_1:        db "Failure: virt_shared_page_release 1st call did not return 1.", 0x0D, 0x0A, 0
msg_share_fail_refcount_1:       db "Failure: Shared descriptor ref_count is not 1 after first release.", 0x0D, 0x0A, 0
msg_share_fail_release_2:        db "Failure: virt_shared_page_release 2nd call did not return 0.", 0x0D, 0x0A, 0
msg_share_fail_desc_not_cleared: db "Failure: Shared descriptor not cleared after second release.", 0x0D, 0x0A, 0
msg_reap_test_start:            db "Running Intermediate Page Table Reaping Test...", 0x0D, 0x0A, 0
msg_reap_test_passed:           db "Intermediate Page Table Reaping Test PASSED!", 0x0D, 0x0A, 0
msg_reap_fail_pml4:             db "Failure: Could not allocate dummy PML4 for reaping.", 0x0D, 0x0A, 0
msg_reap_fail_alloc1:           db "Failure: Could not allocate physical page 1 for reaping.", 0x0D, 0x0A, 0
msg_reap_fail_map1:             db "Failure: Could not map physical page 1 in dummy PML4.", 0x0D, 0x0A, 0
msg_reap_fail_count1:           db "Failure: Empty page table reaping executed on non-empty table (count != 0).", 0x0D, 0x0A, 0
msg_reap_fail_walk:             db "Failure: Could not walk table to locate leaf PTE for reaping.", 0x0D, 0x0A, 0
msg_reap_fail_count2:           db "Failure: Empty page table reaping did not reap empty table (count != 1).", 0x0D, 0x0A, 0
msg_reap_fail_pmd_not_cleared:   db "Failure: Parent PMD entry pointing to reaped table was not cleared.", 0x0D, 0x0A, 0

msg_coop_test_start:            db "Running Cooperative Lockless Allocator Test...", 0x0D, 0x0A, 0
msg_coop_test_passed:           db "Cooperative Lockless Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_coop_fail_queue_alloc:      db "Failure: Could not allocate shared queue buffer.", 0x0D, 0x0A, 0
msg_coop_fail_slot:             db "Failure: Claimed queue slot is not 0.", 0x0D, 0x0A, 0
msg_coop_fail_request_val:      db "Failure: Request page count value not stored in queue ring.", 0x0D, 0x0A, 0
msg_coop_fail_head:             db "Failure: head index not incremented to 1 after process.", 0x0D, 0x0A, 0
msg_coop_fail_tail:             db "Failure: tail index mismatch (not 1).", 0x0D, 0x0A, 0
msg_coop_fail_phys_val:         db "Failure: Processed queue slot contains NULL physical address.", 0x0D, 0x0A, 0

msg_zone_test_start:            db "Running Memory Compact Hot-Plug Zones Test (ZONE_MOVABLE)...", 0x0D, 0x0A, 0
msg_zone_test_passed:           db "Memory Compact Hot-Plug Zones Test PASSED!", 0x0D, 0x0A, 0
msg_zone_fail_init:             db "Failure: pages_array was not initialized after zone marking.", 0x0D, 0x0A, 0
msg_zone_fail_flag:             db "Failure: PFN descriptor flag PAGE_MOVABLE was not set.", 0x0D, 0x0A, 0
msg_zone_fail_alloc:            db "Failure: Buddy allocator returned NULL under allocations mask.", 0x0D, 0x0A, 0
msg_zone_fail_movable_alloc:    db "Failure: Buddy allocator returned page inside ZONE_MOVABLE under mask.", 0x0D, 0x0A, 0

msg_aslr_test_start:            db "Running Live Kernel ASLR Re-Shuffling Test...", 0x0D, 0x0A, 0
msg_aslr_test_passed:           db "Live Kernel ASLR Re-Shuffling Test PASSED!", 0x0D, 0x0A, 0
msg_aslr_fail_alloc1:           db "Failure: Could not allocate old physical frame for ASLR migration.", 0x0D, 0x0A, 0
msg_aslr_fail_alloc2:           db "Failure: Could not allocate new physical frame for ASLR migration.", 0x0D, 0x0A, 0
msg_aslr_fail_map1:             db "Failure: Could not map old page in current PML4.", 0x0D, 0x0A, 0
msg_aslr_fail_sig1:             db "Failure: Virtual address reads incorrect signature before ASLR migration.", 0x0D, 0x0A, 0
msg_aslr_fail_translate:        db "Failure: Virtual address translation did not redirect to new page after ASLR migration.", 0x0D, 0x0A, 0
msg_aslr_fail_sig2:             db "Failure: Virtual address reads incorrect signature after ASLR migration.", 0x0D, 0x0A, 0

msg_pasid_test_start:           db "Running PASID Table Binding Test...", 0x0D, 0x0A, 0
msg_pasid_test_passed:          db "PASID Table Binding Test PASSED!", 0x0D, 0x0A, 0
msg_pasid_fail_alloc:           db "Failure: Could not allocate mock PASID table.", 0x0D, 0x0A, 0
msg_pasid_fail_entry:           db "Failure: PASID table entry value is incorrect after binding.", 0x0D, 0x0A, 0

msg_test_start:       db "Running VMM On-Demand Paging Exception Test...", 0x0D, 0x0A, 0
msg_vma_ok:           db "VMA created at 0x70000000. Triggering read/write page fault...", 0x0D, 0x0A, 0
msg_test_passed:      db "VMM On-Demand Paging Test PASSED!", 0x0D, 0x0A, 0
msg_test_failed:      db "VMM Test Suite FAILED! Halting.", 0x0D, 0x0A, 0

msg_fail_vma_str:     db "Failure: Could not create on-demand VMA.", 0x0D, 0x0A, 0
msg_fail_val_str:     db "Failure: Resumed byte value is incorrect.", 0x0D, 0x0A, 0
msg_fail_addr_str:    db "Failure: Unique address verification at offset 32 failed.", 0x0D, 0x0A, 0

msg_cow_test_start:   db "Running VMM Copy-on-Write (COW) Exception Test...", 0x0D, 0x0A, 0
msg_cow_before_write: db "Initial mapping reads (expected COW_PARENT_ORIGINAL_DATA): ", 0
msg_cow_after_write:  db "After write, virtual page reads (expected CHILD_DATA): ", 0
msg_cow_parent_check: db "Parent physical page reads (expected COW_PARENT_ORIGINAL_DATA): ", 0
msg_cow_test_passed:  db "VMM Copy-on-Write (COW) Test PASSED!", 0x0D, 0x0A, 0

msg_cow_parent_data:  db "COW_PARENT_ORIGINAL_DATA", 0
msg_cow_child_data:   db "CHILD_DATA", 0

msg_cow_fail_alloc_str: db "Failure: Could not allocate physical page for COW parent.", 0x0D, 0x0A, 0
msg_cow_fail_vma_str:   db "Failure: Could not create COW VMA.", 0x0D, 0x0A, 0
msg_cow_fail_map_str:   db "Failure: Could not map COW parent page.", 0x0D, 0x0A, 0
msg_cow_fail_iso_str:   db "Failure: Isolation check failed! Parent or child data incorrect.", 0x0D, 0x0A, 0
msg_cow_fail_same_str:  db "Failure: Virtual address still maps to parent physical page (no COW allocate).", 0x0D, 0x0A, 0

msg_zfod_test_start:   db "Running VMM Zero-Fill-on-Demand (ZFOD) Exception Test...", 0x0D, 0x0A, 0
msg_zfod_read_ok:     db "ZFOD Page 1 read verify (returned 0). Shared zero page successfully mapped.", 0x0D, 0x0A, 0
msg_zfod_page1_ok:    db "ZFOD Page 1 write verify & isolation check passed.", 0x0D, 0x0A, 0
msg_zfod_test_passed:  db "VMM Zero-Fill-on-Demand (ZFOD) Test PASSED!", 0x0D, 0x0A, 0

msg_zfod_fail_vma_str:  db "Failure: Could not create ZFOD VMA.", 0x0D, 0x0A, 0
msg_zfod_fail_read_str: db "Failure: Initial ZFOD read returned non-zero value.", 0x0D, 0x0A, 0
msg_zfod_fail_ptr_str:  db "Failure: Shared zero page address pointer not initialized.", 0x0D, 0x0A, 0
msg_zfod_fail_write_str: db "Failure: Value read back from ZFOD Page 1 after write is incorrect.", 0x0D, 0x0A, 0
msg_zfod_fail_iso_str:   db "Failure: Shared zero page was modified by COW write!", 0x0D, 0x0A, 0
msg_zfod_fail_same_str:  db "Failure: Page 1 still maps to shared zero page after write.", 0x0D, 0x0A, 0
msg_zfod_fail_p2val_str: db "Failure: Value read back from ZFOD Page 2 after direct write is incorrect.", 0x0D, 0x0A, 0
msg_zfod_fail_p2same_str: db "Failure: Page 2 maps to shared zero page after direct write.", 0x0D, 0x0A, 0

msg_stack_test_start:  db "Running VMM Stack Auto-Grow Exception Test...", 0x0D, 0x0A, 0
msg_stack_test_passed: db "VMM Stack Auto-Grow Test PASSED!", 0x0D, 0x0A, 0

msg_stack_fail_vma_str: db "Failure: Could not create Stack Auto-Grow VMA.", 0x0D, 0x0A, 0
msg_stack_fail_val_str: db "Failure: Value read back from grown Stack address is incorrect.", 0x0D, 0x0A, 0
msg_stack_fail_map_str: db "Failure: Stack address not mapped in page table after write.", 0x0D, 0x0A, 0

msg_rep_test_start:            db "Running VMM Active/Inactive Page Lists Test...", 0x0D, 0x0A, 0
msg_rep_test_passed:           db "VMM Active/Inactive Page Lists Test PASSED!", 0x0D, 0x0A, 0
msg_rep_fail_init_str:         db "Failure: Initial active/inactive counts not 0.", 0x0D, 0x0A, 0
msg_rep_fail_alloc_str:        db "Failure: Could not allocate physical page for replacement test.", 0x0D, 0x0A, 0
msg_rep_fail_vma_str:          db "Failure: Could not create replacement test VMA.", 0x0D, 0x0A, 0
msg_rep_fail_map_str:          db "Failure: Could not map replacement test page.", 0x0D, 0x0A, 0
msg_rep_fail_active_str:       db "Failure: Page not tracked in active list after mapping.", 0x0D, 0x0A, 0
msg_rep_fail_inactive_str:     db "Failure: Inactive count non-zero after mapping to active.", 0x0D, 0x0A, 0
msg_rep_fail_active_in_str:    db "Failure: Active count non-zero after moving to inactive.", 0x0D, 0x0A, 0
msg_rep_fail_inactive_in_str:  db "Failure: Inactive count not 1 after moving to inactive.", 0x0D, 0x0A, 0
msg_rep_fail_active_back_str:  db "Failure: Active count not 1 after moving back to active.", 0x0D, 0x0A, 0
msg_rep_fail_inactive_back_str:db "Failure: Inactive count non-zero after moving back to active.", 0x0D, 0x0A, 0
msg_rep_fail_final_str:        db "Failure: Counts non-zero after unmapping page.", 0x0D, 0x0A, 0

msg_clock_test_start:          db "Running VMM Clock/Second-Chance Eviction Test...", 0x0D, 0x0A, 0
msg_clock_evicted_ok:          db "Clock eviction successful. Page marked swapped in PTE and physical frame freed.", 0x0D, 0x0A, 0
msg_clock_test_passed:         db "VMM Clock/Second-Chance Eviction Test PASSED!", 0x0D, 0x0A, 0
msg_clock_test_data:           db "SWAP_MOCK_TEST_DATA", 0

msg_clock_fail_alloc_str:      db "Failure: Could not allocate physical page for clock test.", 0x0D, 0x0A, 0
msg_clock_fail_vma_str:        db "Failure: Could not create VMA for clock test.", 0x0D, 0x0A, 0
msg_clock_fail_map_str:        db "Failure: Could not map page for clock test.", 0x0D, 0x0A, 0
msg_clock_fail_inactive_str:   db "Failure: Page not in inactive list before eviction.", 0x0D, 0x0A, 0
msg_clock_fail_walk_str:       db "Failure: Could not walk page table for virtual address.", 0x0D, 0x0A, 0
msg_clock_fail_evict_str:      db "Failure: Clock eviction routine returned failure.", 0x0D, 0x0A, 0
msg_clock_fail_walk_ev_str:    db "Failure: Walk failed for evicted page virtual address.", 0x0D, 0x0A, 0
msg_clock_fail_still_pres_str: db "Failure: Evicted page is still marked present in PTE.", 0x0D, 0x0A, 0
msg_clock_fail_not_swap_str:   db "Failure: Evicted page does not have PAGE_SWAPPED set in PTE.", 0x0D, 0x0A, 0
msg_clock_fail_stats_str:      db "Failure: Swap pages telemetry count not 1 after eviction.", 0x0D, 0x0A, 0
msg_clock_fail_list_str:       db "Failure: Active or inactive counts not 0 after eviction.", 0x0D, 0x0A, 0
msg_clock_fail_data_str:       db "Failure: Swapped-in data is corrupt or mismatch.", 0x0D, 0x0A, 0
msg_clock_fail_stats_res_str:  db "Failure: Telemetry swap pages count not 0 after swap-in.", 0x0D, 0x0A, 0
msg_clock_fail_act_res_str:    db "Failure: Active list count not 1 after swap-in.", 0x0D, 0x0A, 0
msg_clock_fail_inact_res_str:  db "Failure: Inactive list count not 0 after swap-in.", 0x0D, 0x0A, 0

msg_ata_test_start:            db "Running VMM ATA Swap Partition Test...", 0x0D, 0x0A, 0
msg_ata_test_passed:           db "VMM ATA Swap Partition Test PASSED!", 0x0D, 0x0A, 0
msg_ata_test_data:             db "MOCK_ATA_SWAP_DATA", 0

msg_ata_fail_alloc_str:        db "Failure: Could not allocate page for ATA swap test.", 0x0D, 0x0A, 0
msg_ata_fail_vma_str:          db "Failure: Could not create VMA for ATA swap test.", 0x0D, 0x0A, 0
msg_ata_fail_map_str:          db "Failure: Could not map page for ATA swap test.", 0x0D, 0x0A, 0
msg_ata_fail_inactive_str:     db "Failure: Page not inactive before ATA eviction.", 0x0D, 0x0A, 0
msg_ata_fail_walk_str:         db "Failure: Could not walk page table for ATA test.", 0x0D, 0x0A, 0
msg_ata_fail_evict_str:        db "Failure: ATA eviction command returned error.", 0x0D, 0x0A, 0
msg_ata_fail_walk_ev_str:      db "Failure: Walk failed for ATA evicted address.", 0x0D, 0x0A, 0
msg_ata_fail_still_pres_str:   db "Failure: Page still present after ATA eviction.", 0x0D, 0x0A, 0
msg_ata_fail_not_swap_str:     db "Failure: Page not marked swapped in ATA PTE.", 0x0D, 0x0A, 0
msg_ata_fail_data_str:         db "Failure: Swapped-in data corrupt on ATA partition.", 0x0D, 0x0A, 0

msg_nvme_test_start:           db "Running VMM Direct NVMe Swap Queue Test...", 0x0D, 0x0A, 0
msg_nvme_test_passed:          db "VMM Direct NVMe Swap Queue Test PASSED!", 0x0D, 0x0A, 0
msg_nvme_test_data:            db "MOCK_NVME_SWAP_DATA", 0

msg_nvme_fail_alloc_str:       db "Failure: Could not allocate page for NVMe swap test.", 0x0D, 0x0A, 0
msg_nvme_fail_vma_str:         db "Failure: Could not create VMA for NVMe swap test.", 0x0D, 0x0A, 0
msg_nvme_fail_map_str:         db "Failure: Could not map page for NVMe swap test.", 0x0D, 0x0A, 0
msg_nvme_fail_inactive_str:    db "Failure: Page not inactive before NVMe eviction.", 0x0D, 0x0A, 0
msg_nvme_fail_walk_str:        db "Failure: Could not walk page table for NVMe test.", 0x0D, 0x0A, 0
msg_nvme_fail_evict_str:       db "Failure: NVMe eviction command returned error.", 0x0D, 0x0A, 0
msg_nvme_fail_walk_ev_str:     db "Failure: Walk failed for NVMe evicted address.", 0x0D, 0x0A, 0
msg_nvme_fail_still_pres_str:  db "Failure: Page still present after NVMe eviction.", 0x0D, 0x0A, 0
msg_nvme_fail_not_swap_str:    db "Failure: Page not marked swapped in NVMe PTE.", 0x0D, 0x0A, 0
msg_nvme_fail_data_str:        db "Failure: Swapped-in data corrupt on NVMe queue.", 0x0D, 0x0A, 0

msg_kswapd_test_start:         db "Running VMM Page-Out Daemon (kswapd) Watermark Test...", 0x0D, 0x0A, 0
msg_kswapd_test_passed:        db "VMM Page-Out Daemon (kswapd) Watermark Test PASSED!", 0x0D, 0x0A, 0
msg_kswapd_test_data:          db "MOCK_KSWAPD_SWAP_DATA", 0

msg_kswapd_fail_alloc_setup_str: db "Failure: Setup physical page allocation failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_vma_setup_str:   db "Failure: Setup VMA creation failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_map_setup_str:   db "Failure: Setup virtual mapping failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_walk_setup_str:  db "Failure: Setup page table walk failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_alloc_trigger_str: db "Failure: Allocation with watermark trigger failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_walk_ev_str:     db "Failure: Evicted walk failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_still_pres_str:  db "Failure: Page still present after kswapd eviction.", 0x0D, 0x0A, 0
msg_kswapd_fail_not_swap_str:    db "Failure: Page not marked swapped after kswapd eviction.", 0x0D, 0x0A, 0
msg_kswapd_fail_data_str:        db "Failure: Swapped-in data corrupt after kswapd reclaim.", 0x0D, 0x0A, 0

msg_zswap_test_start:         db "Running VMM Zswap Compressed Cache Test...", 0x0D, 0x0A, 0
msg_zswap_evicted_ok:         db "Zswap eviction successful: page compressed and stored in RAM cache.", 0x0D, 0x0A, 0
msg_zswap_comp_passed:        db "Zswap Compressible Page Test PASSED!", 0x0D, 0x0A, 0
msg_zswap_disk_evicted_ok:    db "Zswap uncompressible bypass successful: page evicted directly to disk.", 0x0D, 0x0A, 0
msg_zswap_test_passed:        db "VMM Zswap Compressed Cache Test PASSED!", 0x0D, 0x0A, 0

msg_zswap_comp_sig:           db "COMPRESSIBLE_SIG", 0
msg_zswap_uncomp_sig:         db "UNCOMPRESSIBLE_SIG", 0

msg_zswap_fail_init_tel_str:  db "Failure: Initial Zswap telemetry is not 0.", 0x0D, 0x0A, 0
msg_zswap_fail_alloc1_str:     db "Failure: Could not allocate physical page for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_vma1_str:       db "Failure: Could not create VMA for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_map1_str:       db "Failure: Could not map page for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_walk1_str:      db "Failure: Could not walk page table for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_evict1_str:     db "Failure: clock eviction failed for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_walk_ev1_str:   db "Failure: walk failed after eviction for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_still_pres1_str:db "Failure: Zswap page still present after clock eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_not_swap1_str:  db "Failure: Zswap page does not have PAGE_SWAPPED set.", 0x0D, 0x0A, 0
msg_zswap_fail_not_zswap1_str: db "Failure: Zswap page does not have PAGE_ZSWAPPED set.", 0x0D, 0x0A, 0
msg_zswap_fail_telemetry1_str: db "Failure: Zswap compressed pages telemetry is not 1 after eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_data1_str:      db "Failure: Decompressed data is corrupt or signature mismatch.", 0x0D, 0x0A, 0
msg_zswap_fail_tel_res1_str:   db "Failure: Zswap compressed pages telemetry did not return to 0.", 0x0D, 0x0A, 0

msg_zswap_fail_alloc2_str:     db "Failure: Could not allocate physical page for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_vma2_str:       db "Failure: Could not create VMA for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_map2_str:       db "Failure: Could not map page for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_walk2_str:      db "Failure: Could not walk page table for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_evict2_str:     db "Failure: clock eviction failed for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_walk_ev2_str:   db "Failure: walk failed after eviction for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_still_pres2_str:db "Failure: Page still present after disk bypass eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_not_swap2_str:  db "Failure: Page does not have PAGE_SWAPPED set after disk bypass eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_is_zswap2_str:  db "Failure: Page has PAGE_ZSWAPPED set but should have bypassed Zswap.", 0x0D, 0x0A, 0
msg_zswap_fail_telemetry2_str: db "Failure: Zswap telemetry non-zero for uncompressible page.", 0x0D, 0x0A, 0
msg_zswap_fail_data2_str:      db "Failure: Swapped-in data from disk bypass is corrupt or mismatch.", 0x0D, 0x0A, 0

msg_zram_test_start:             db "Running VMM ZRAM LZ4 Compression & Decompression Tests...", 0x0D, 0x0A, 0
msg_zram_test_passed:            db "VMM ZRAM LZ4 Compression & Decompression Tests PASSED!", 0x0D, 0x0A, 0
msg_zram_evicted_ok:             db "  ZRAM eviction successful: page compressed with LZ4 and stored in RAM cache.", 0x0D, 0x0A, 0
msg_zram_sig:                    db "ZRAM_LZ4_COMPRESSIBLE_PATTERN", 0
msg_zram_fail_init_telemetry_str: db "Failure: Initial ZRAM telemetry is not 0.", 0x0D, 0x0A, 0
msg_zram_fail_alloc_str:         db "Failure: Could not allocate physical page for ZRAM test.", 0x0D, 0x0A, 0
msg_zram_fail_vma_str:           db "Failure: Could not create VMA for ZRAM test.", 0x0D, 0x0A, 0
msg_zram_fail_map_str:           db "Failure: Could not map page for ZRAM test.", 0x0D, 0x0A, 0
msg_zram_fail_walk_str:          db "Failure: Could not walk page table for ZRAM test.", 0x0D, 0x0A, 0
msg_zram_fail_evict_str:         db "Failure: clock eviction failed for ZRAM test.", 0x0D, 0x0A, 0
msg_zram_fail_walk_ev_str:       db "Failure: walk failed after eviction for ZRAM test.", 0x0D, 0x0A, 0
msg_zram_fail_still_present_str: db "Failure: ZRAM page still present after clock eviction.", 0x0D, 0x0A, 0
msg_zram_fail_not_swapped_str:   db "Failure: ZRAM page does not have PAGE_SWAPPED set.", 0x0D, 0x0A, 0
msg_zram_fail_telemetry_str:     db "Failure: ZRAM compressed pages telemetry is not 1 after eviction.", 0x0D, 0x0A, 0
msg_zram_fail_data_corrupt_str:  db "Failure: Decompressed LZ4 data is corrupt or signature mismatch.", 0x0D, 0x0A, 0
msg_zram_fail_telemetry_res_str: db "Failure: ZRAM compressed pages telemetry did not return to 0.", 0x0D, 0x0A, 0

; Zpool Balance Test messages
msg_zpool_balance_test_start:   db "Running VMM Dynamic Zpool Balancing Tests...", 0x0D, 0x0A, 0
msg_zpool_balance_test_passed:  db "VMM Dynamic Zpool Balancing Tests PASSED!", 0x0D, 0x0A, 0
msg_zpool_balance_fail_high_str: db "Failure: Dynamic zpool balancing did not scale limits to 256 for >50% free memory.", 0x0D, 0x0A, 0
msg_zpool_balance_fail_mid_str:  db "Failure: Dynamic zpool balancing did not scale limits to 128 for 20% < free memory <= 50%.", 0x0D, 0x0A, 0
msg_zpool_balance_fail_low_str:  db "Failure: Dynamic zpool balancing did not scale limits to 64 for <=20% free memory.", 0x0D, 0x0A, 0
msg_zpool_balance_fail_reject_zram_str: db "Failure: ZRAM did not reject store allocation when slots usage met scaled limit.", 0x0D, 0x0A, 0
msg_zpool_balance_fail_reject_zswap_str: db "Failure: Zswap did not reject store allocation when slots usage met scaled limit.", 0x0D, 0x0A, 0

; Zpool Compaction Test messages
msg_zpool_compact_test_start:   db "Running VMM Compressed Block Compaction Tests...", 0x0D, 0x0A, 0
msg_zpool_compact_test_passed:  db "VMM Compressed Block Compaction Tests PASSED!", 0x0D, 0x0A, 0
msg_zpool_compact_fail_zswap_inuse_str: db "Failure: Zswap slot in_use metadata incorrect after compaction.", 0x0D, 0x0A, 0
msg_zpool_compact_fail_zswap_data_str:  db "Failure: Zswap compacted page data corruption or mismatch after swap-in.", 0x0D, 0x0A, 0
msg_zpool_compact_fail_zram_inuse_str:  db "Failure: ZRAM slot in_use metadata incorrect after compaction.", 0x0D, 0x0A, 0
msg_zpool_compact_fail_zram_data_str:   db "Failure: ZRAM compacted page data corruption or mismatch after swap-in.", 0x0D, 0x0A, 0

; Zpool Writeback Test messages
msg_zpool_writeback_test_start:   db "Running VMM Physical Swap Writeback Pipeline Tests...", 0x0D, 0x0A, 0
msg_zpool_writeback_test_passed:  db "VMM Physical Swap Writeback Pipeline Tests PASSED!", 0x0D, 0x0A, 0
msg_zpool_writeback_fail_zswap_flags_str: db "Failure: Zswap writeback PTE swap cache flags not correctly updated.", 0x0D, 0x0A, 0
msg_zpool_writeback_fail_zswap_data_str:  db "Failure: Zswap writeback page A data corruption or mismatch after disk swap-in.", 0x0D, 0x0A, 0
msg_zpool_writeback_fail_zram_flags_str:  db "Failure: ZRAM writeback PTE swap cache flags not correctly updated.", 0x0D, 0x0A, 0
msg_zpool_writeback_fail_zram_data_str:   db "Failure: ZRAM writeback page A data corruption or mismatch after disk swap-in.", 0x0D, 0x0A, 0

; Zpool Batch Decompression Test messages
msg_zpool_decomp_test_start:   db "Running VMM Parallel Batch Decompression Rings Tests...", 0x0D, 0x0A, 0
msg_zpool_decomp_test_passed:  db "VMM Parallel Batch Decompression Rings Tests PASSED!", 0x0D, 0x0A, 0
msg_zpool_decomp_fail_comp_str: db "Failure: Could not compress testing pages for batch decompression.", 0x0D, 0x0A, 0
msg_zpool_decomp_fail_submit_str: db "Failure: zpool_batch_decompress_submit did not return success count 2.", 0x0D, 0x0A, 0
msg_zpool_decomp_fail_status_str: db "Failure: Batch request completion status is not set to completed (1).", 0x0D, 0x0A, 0
msg_zpool_decomp_fail_data_str:  db "Failure: Batch decompressed page contents are corrupt or mismatch.", 0x0D, 0x0A, 0

msg_mtrr_test_start:         db "Running VMM MTRR Cache Programming Test...", 0x0D, 0x0A, 0
msg_mtrr_vcnt_str:            db "MTRR supported. Count of variable registers: ", 0
msg_mtrr_test_passed:         db "VMM MTRR Cache Programming Test PASSED!", 0x0D, 0x0A, 0
msg_mtrr_skipped_str:         db "MTRR Cache Programming Test skipped: MTRRs not supported.", 0x0D, 0x0A, 0

msg_mtrr_fail_set_str:        db "Failure: mtrr_set_variable returned 0.", 0x0D, 0x0A, 0
msg_mtrr_fail_get_act_str:    db "Failure: mtrr_get_variable returned 0 for active slot.", 0x0D, 0x0A, 0
msg_mtrr_fail_base_str:       db "Failure: mtrr_get_variable returned incorrect base.", 0x0D, 0x0A, 0
msg_mtrr_fail_size_str:       db "Failure: mtrr_get_variable returned incorrect size.", 0x0D, 0x0A, 0
msg_mtrr_fail_type_str:       db "Failure: mtrr_get_variable returned incorrect type.", 0x0D, 0x0A, 0
msg_mtrr_fail_disable_str:    db "Failure: mtrr_disable_variable returned 0.", 0x0D, 0x0A, 0
msg_mtrr_fail_still_act_str:  db "Failure: mtrr_get_variable indicates slot is active after disable.", 0x0D, 0x0A, 0

; PAT Configuration Test messages
msg_pat_test_start:         db "Running VMM PAT Cache Configuration Test...", 0x0D, 0x0A, 0
msg_pat_test_passed:        db "VMM PAT Cache Configuration Test PASSED!", 0x0D, 0x0A, 0
msg_pat_skipped_str:        db "PAT Cache Configuration Test skipped: PAT not supported.", 0x0D, 0x0A, 0
msg_pat_fail_get_str:       db "Failure: pat_get_msr returned 0.", 0x0D, 0x0A, 0
msg_pat_fail_wb_index_str:  db "Failure: WB index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_wt_index_str:  db "Failure: WT index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_wc_index_str:  db "Failure: WC index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_uc_index_str:  db "Failure: UC index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_set_str:       db "Failure: pat_set_msr returned 0.", 0x0D, 0x0A, 0
msg_pat_fail_wc_swap_str:   db "Failure: WC index search returned incorrect slot after swap.", 0x0D, 0x0A, 0
msg_pat_fail_wp_swap_str:   db "Failure: WP index search returned incorrect slot after swap.", 0x0D, 0x0A, 0
msg_pat_fail_restore_str:   db "Failure: pat_set_msr returned 0 during restore.", 0x0D, 0x0A, 0
msg_pat_fail_rest_ver_str:  db "Failure: WC index search returned incorrect slot after restore.", 0x0D, 0x0A, 0

; Write-Combining Framebuffer messages
msg_fb_test_start_str:      db "Running VMM Write-Combining Video Buffer mapping test...", 0x0D, 0x0A, 0
msg_fb_test_passed_str:     db "VMM Write-Combining Video Buffer mapping test PASSED!", 0x0D, 0x0A, 0
msg_fb_skipped_str:         db "Write-Combining Video Buffer test skipped: No linear framebuffer.", 0x0D, 0x0A, 0
msg_fb_fail_init_str:       db "Failure: Framebuffer mapping initialization failed.", 0x0D, 0x0A, 0
msg_fb_fail_bench_str:      db "Failure: Framebuffer write speed benchmark failed.", 0x0D, 0x0A, 0

; General-Purpose Heap Allocator messages
msg_heap_test_start:        db "Running General-Purpose Heap Allocator Test...", 0x0D, 0x0A, 0
msg_heap_test_passed:       db "General-Purpose Heap Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_heap_fail_active_str:   db "Failure: Heap allocator was not transitioned to free-list mode.", 0x0D, 0x0A, 0
msg_heap_fail_alloc_str:    db "Failure: First heap allocation (64 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_align_str:    db "Failure: First heap allocation pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_heap_fail_alloc2_str:   db "Failure: Second heap allocation (64 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_align2_str:   db "Failure: Second heap allocation pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_heap_fail_alloc3_str:   db "Failure: Third heap allocation (64 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_align3_str:   db "Failure: Third heap allocation pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_heap_fail_spacing_str:  db "Failure: Heap block spacing does not match block_size + header_size.", 0x0D, 0x0A, 0
msg_heap_fail_alloc_split_str: db "Failure: Split heap allocation (16 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_split_ptr_str: db "Failure: Split allocation did not reuse original block B start address.", 0x0D, 0x0A, 0
msg_heap_fail_alloc_split2_str: db "Failure: Second split allocation (16 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_split_rem_str: db "Failure: Second split did not return expected remainder address (B+48).", 0x0D, 0x0A, 0
msg_heap_fail_coalesce_str:  db "Failure: Allocation (256 bytes) from coalesced block returned null.", 0x0D, 0x0A, 0
msg_heap_fail_coalesce_ptr_str: db "Failure: Coalesced allocation did not return block A start address.", 0x0D, 0x0A, 0

; Heap Defragmenter Test Variables & Messages
align 8
ptr_A: dq 0
ptr_B: dq 0
ptr_C: dq 0

msg_defrag_test_start:         db "Running VMM Heap Compaction/Defragmentation Test...", 0x0D, 0x0A, 0
msg_defrag_test_passed:        db "VMM Heap Compaction/Defragmentation Test PASSED!", 0x0D, 0x0A, 0
msg_defrag_fail_alloc_A_str:   db "Failure: Allocation A returned null.", 0x0D, 0x0A, 0
msg_defrag_fail_alloc_B_str:   db "Failure: Allocation B returned null.", 0x0D, 0x0A, 0
msg_defrag_fail_alloc_C_str:   db "Failure: Allocation C returned null.", 0x0D, 0x0A, 0
msg_defrag_fail_reg_str:       db "Failure: Pointer registration returned 0.", 0x0D, 0x0A, 0
msg_defrag_fail_compact_str:   db "Failure: heap_compact returned 0.", 0x0D, 0x0A, 0
msg_defrag_fail_assert_A_str:  db "Failure: A was moved or corrupted during compaction.", 0x0D, 0x0A, 0
msg_defrag_fail_assert_C_str:  db "Failure: C pointer was not updated to B's old address.", 0x0D, 0x0A, 0

; Slab Allocator Test Messages
msg_slab_test_start:         db "Running VMM Slab Allocator Cache Definitions Test...", 0x0D, 0x0A, 0
msg_slab_test_passed:        db "VMM Slab Allocator Cache Definitions Test PASSED!", 0x0D, 0x0A, 0
msg_slab_fail_name_str:      db "Failure: Slab cache name is missing or incorrect.", 0x0D, 0x0A, 0
msg_slab_fail_size_str:      db "Failure: Slab cache object size verification failed.", 0x0D, 0x0A, 0
msg_slab_fail_align_str:     db "Failure: Slab cache alignment verification failed.", 0x0D, 0x0A, 0
msg_slab_fail_lists_str:     db "Failure: Slab cache slab lists are not empty.", 0x0D, 0x0A, 0

; Slab Lists Tracking & Grow Test Messages
msg_slab_grow_test_start:      db "Running VMM Slab Lists Tracking & Grow Test...", 0x0D, 0x0A, 0
msg_slab_grow_test_passed:     db "VMM Slab Lists Tracking & Grow Test PASSED!", 0x0D, 0x0A, 0
msg_slab_fail_grow_str:        db "Failure: kmem_slab_grow returned NULL.", 0x0D, 0x0A, 0
msg_slab_fail_free_list_str:   db "Failure: New slab was not added to the slabs_free list.", 0x0D, 0x0A, 0
msg_slab_fail_magic_str:       db "Failure: Slab magic number is incorrect or corrupt.", 0x0D, 0x0A, 0
msg_slab_fail_count_str:       db "Failure: Slab object capacity (obj_count) is incorrect.", 0x0D, 0x0A, 0
msg_slab_fail_used_str:        db "Failure: New slab used_count is non-zero.", 0x0D, 0x0A, 0
msg_slab_fail_free_head_str:   db "Failure: New slab free_head does not point to mem_start.", 0x0D, 0x0A, 0
msg_slab_fail_free_chain_str:  db "Failure: Slab free objects chain link verification failed.", 0x0D, 0x0A, 0
msg_slab_fail_transition_str:  db "Failure: Slab transition between lists did not update lists correctly.", 0x0D, 0x0A, 0

; Slab Object Constructor Reuse Test Messages
msg_slab_ctor_test_start:      db "Running VMM Slab Object Constructor Reuse Test...", 0x0D, 0x0A, 0
msg_slab_ctor_test_passed:     db "VMM Slab Object Constructor Reuse Test PASSED!", 0x0D, 0x0A, 0
msg_test_cache_name:           db "kmem_test_ctor", 0
msg_slab_fail_ctor_str:        db "Failure: Slab object constructor magic value not found.", 0x0D, 0x0A, 0
msg_slab_fail_ctor_chain_str:  db "Failure: Slab constructor chain contains null next pointer.", 0x0D, 0x0A, 0

; Slab Reaping Test Messages
msg_slab_reap_test_start:       db "Running VMM Slab Reaping Test...", 0x0D, 0x0A, 0
msg_slab_reap_test_passed:      db "VMM Slab Reaping Test PASSED!", 0x0D, 0x0A, 0
msg_slab_reap_fail_setup_str:   db "Failure: Could not setup empty slab in kmem_cache_vma slabs_free.", 0x0D, 0x0A, 0
msg_slab_reap_fail_eviction_str:db "Failure: Empty slab not reaped/removed from slabs_free under RAM pressure.", 0x0D, 0x0A, 0
msg_slab_reap_fail_count_str:   db "Failure: Physical free pages count not incremented after reaping slab.", 0x0D, 0x0A, 0

; Slab Cache Coloring Test Messages
msg_slab_color_test_start:      db "Running VMM Slab Cache Coloring Test...", 0x0D, 0x0A, 0
msg_slab_color_test_passed:     db "VMM Slab Cache Coloring Test PASSED!", 0x0D, 0x0A, 0
msg_test_color_cache_name:      db "kmem_test_color", 0
msg_slab_color_fail_max_str:    db "Failure: Slab cache colour_max calculation is incorrect.", 0x0D, 0x0A, 0
msg_slab_color_fail_offset_str: db "Failure: Slab starting offset is not correctly colored (staggered by 64 bytes).", 0x0D, 0x0A, 0

; Buddy Allocator Test Messages
msg_buddy_test_start:          db "Running Buddy Allocator Initialization Test...", 0x0D, 0x0A, 0
msg_buddy_test_passed:         db "Buddy Allocator Initialization Test PASSED!", 0x0D, 0x0A, 0
msg_buddy_fail_alloc_str:      db "Failure: Could not allocate memory for buddy test.", 0x0D, 0x0A, 0
msg_buddy_fail_config_str:     db "Failure: Buddy allocator config variables (start/end) are incorrect.", 0x0D, 0x0A, 0
msg_buddy_fail_lists_str:      db "Failure: Buddy free list heads are incorrect or not partitioned properly.", 0x0D, 0x0A, 0
msg_buddy_fail_metadata_str:   db "Failure: Buddy page metadata array contents are incorrect.", 0x0D, 0x0A, 0

; Buddy Allocator Splitting Test Messages
msg_buddy_split_test_start:          db "Running Buddy Allocator Block Splitting Test...", 0x0D, 0x0A, 0
msg_buddy_split_test_passed:         db "Buddy Allocator Block Splitting Test PASSED!", 0x0D, 0x0A, 0
msg_buddy_fail_split_alloc_str:      db "Failure: buddy_alloc returned NULL for requested order.", 0x0D, 0x0A, 0
msg_buddy_fail_split_ptr_str:        db "Failure: Allocated pointer is not at expected block address.", 0x0D, 0x0A, 0
msg_buddy_fail_split_lists_str:      db "Failure: Buddy free lists are incorrect after block splitting.", 0x0D, 0x0A, 0
msg_buddy_fail_split_metadata_str:   db "Failure: Buddy page metadata array contents are incorrect after splitting.", 0x0D, 0x0A, 0

; Buddy Allocator Coalescing Test Messages
msg_buddy_coalesce_test_start:       db "Running Buddy Allocator Block Coalescing Test...", 0x0D, 0x0A, 0
msg_buddy_coalesce_test_passed:      db "Buddy Allocator Block Coalescing Test PASSED!", 0x0D, 0x0A, 0
msg_buddy_fail_coal_lists_str:      db "Failure: Buddy free lists are incorrect after block coalescing.", 0x0D, 0x0A, 0
msg_buddy_fail_coal_metadata_str:   db "Failure: Buddy page metadata array contents are incorrect after coalescing.", 0x0D, 0x0A, 0

; Arena Allocator Test Messages
msg_arena_test_start:                db "Running VMM Arena Allocator Test...", 0x0D, 0x0A, 0
msg_arena_test_passed:               db "VMM Arena Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_arena_fail_create_str:           db "Failure: arena_create returned NULL.", 0x0D, 0x0A, 0
msg_arena_fail_config_str:           db "Failure: Arena starting, current, or ending bounds config is incorrect.", 0x0D, 0x0A, 0
msg_arena_fail_alloc_str:            db "Failure: arena_alloc returned NULL.", 0x0D, 0x0A, 0
msg_arena_fail_align_str:            db "Failure: Arena allocation address is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_arena_fail_ptr_str:              db "Failure: First arena allocation did not return aligned start address.", 0x0D, 0x0A, 0
msg_arena_fail_spacing_str:          db "Failure: Arena allocations are not contiguous/spaced correctly.", 0x0D, 0x0A, 0
msg_arena_fail_checkpoint_str:       db "Failure: Arena checkpoint save/restore check failed.", 0x0D, 0x0A, 0
msg_arena_fail_oom_str:              db "Failure: Arena allocation succeeded when it should have returned NULL (OOM).", 0x0D, 0x0A, 0
msg_arena_fail_reset_str:            db "Failure: Arena current pointer was not reset back to start address.", 0x0D, 0x0A, 0
msg_arena_fail_local_init_str:       db "Failure: Thread-local arena init failed or pointer was not stored in gs:[24].", 0x0D, 0x0A, 0
msg_arena_fail_local_alloc_str:      db "Failure: Thread-local arena allocation returned NULL.", 0x0D, 0x0A, 0
msg_arena_fail_local_reset_str:      db "Failure: Thread-local arena reset failed.", 0x0D, 0x0A, 0
msg_arena_fail_local_destroy_str:    db "Failure: Thread-local arena destroy did not clear gs:[24] to NULL.", 0x0D, 0x0A, 0

; Fixed-Size Pool Allocator Test Messages
msg_pool_test_start:                 db "Running VMM Fixed-Size Pool Allocator Test...", 0x0D, 0x0A, 0
msg_pool_test_passed:                db "VMM Fixed-Size Pool Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_pool_fail_create_str:            db "Failure: pool_create returned NULL.", 0x0D, 0x0A, 0
msg_pool_fail_config_str:            db "Failure: Pool config fields (obj_size, capacity, count, memory, free_head) are incorrect.", 0x0D, 0x0A, 0
msg_pool_fail_alloc_str:             db "Failure: pool_alloc returned NULL.", 0x0D, 0x0A, 0
msg_pool_fail_ptr_str:               db "Failure: Allocated pool slot is not at the expected memory address.", 0x0D, 0x0A, 0
msg_pool_fail_oom_str:               db "Failure: pool_alloc succeeded when the pool was fully exhausted.", 0x0D, 0x0A, 0
msg_pool_fail_count_str:             db "Failure: Pool active count value is incorrect.", 0x0D, 0x0A, 0
msg_pool_fail_free_list_str:         db "Failure: Intrusive stack-based free list links are incorrect.", 0x0D, 0x0A, 0
msg_pool_fail_reuse_str:             db "Failure: pool_alloc did not pop the head slot from the free list.", 0x0D, 0x0A, 0
msg_pool_fail_safety_str:            db "Failure: Invalid pool_free call was not ignored or corrupted the count.", 0x0D, 0x0A, 0
msg_pool_fail_tag_str:               db "Failure: Pool generation tag was not updated correctly after CAS operations.", 0x0D, 0x0A, 0
msg_pool_fail_grow_alloc_str:        db "Failure: pool_alloc returned NULL during dynamic pool expansion.", 0x0D, 0x0A, 0
msg_pool_fail_capacity_grow_str:     db "Failure: Pool capacity did not grow correctly.", 0x0D, 0x0A, 0
msg_pool_fail_count_grow_str:        db "Failure: Pool count after growth/free operations is incorrect.", 0x0D, 0x0A, 0

; AVX2 Optimized Memory Primitives Test Messages
msg_memcpy_test_start:               db "Running VMM AVX2-Optimized memcpy Test...", 0x0D, 0x0A, 0
msg_memcpy_test_passed:              db "VMM AVX2-Optimized memcpy Test PASSED!", 0x0D, 0x0A, 0
msg_memcpy_fail_alloc_str:           db "Failure: Could not allocate memory for memcpy test buffers.", 0x0D, 0x0A, 0
msg_memcpy_fail_ret_str:             db "Failure: memcpy did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memcpy_fail_data_str:            db "Failure: memcpy did not copy the data payload correctly.", 0x0D, 0x0A, 0
msg_memcpy_fail_extra_str:           db "Failure: memcpy corrupted memory past the requested copy size.", 0x0D, 0x0A, 0

msg_memset_test_start:               db "Running VMM AVX2-Optimized memset Test...", 0x0D, 0x0A, 0
msg_memset_test_passed:              db "VMM AVX2-Optimized memset Test PASSED!", 0x0D, 0x0A, 0
msg_memset_fail_alloc_str:           db "Failure: Could not allocate memory for memset test buffer.", 0x0D, 0x0A, 0
msg_memset_fail_ret_str:             db "Failure: memset did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memset_fail_data_str:            db "Failure: memset did not fill the data payload correctly.", 0x0D, 0x0A, 0
msg_memset_fail_extra_str:           db "Failure: memset corrupted memory past the requested fill size.", 0x0D, 0x0A, 0

msg_memzero_test_start:              db "Running VMM AVX2-Optimized memzero Test...", 0x0D, 0x0A, 0
msg_memzero_test_passed:             db "VMM AVX2-Optimized memzero Test PASSED!", 0x0D, 0x0A, 0
msg_memzero_fail_alloc_str:          db "Failure: Could not allocate memory for memzero test buffer.", 0x0D, 0x0A, 0
msg_memzero_fail_ret_str:            db "Failure: memzero did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memzero_fail_data_str:           db "Failure: memzero did not zero the data payload correctly.", 0x0D, 0x0A, 0
msg_memzero_fail_extra_str:          db "Failure: memzero corrupted memory past the requested zero size.", 0x0D, 0x0A, 0

msg_memcmp_test_start:               db "Running VMM AVX2-Optimized memcmp Test...", 0x0D, 0x0A, 0
msg_memcmp_test_passed:              db "VMM AVX2-Optimized memcmp Test PASSED!", 0x0D, 0x0A, 0
msg_memcmp_fail_alloc_str:           db "Failure: Could not allocate memory for memcmp test buffers.", 0x0D, 0x0A, 0
msg_memcmp_fail_match_str:           db "Failure: memcmp returned non-zero for identical memory blocks.", 0x0D, 0x0A, 0
msg_memcmp_fail_mismatch_str:        db "Failure: memcmp did not calculate mismatch sign or magnitude correctly.", 0x0D, 0x0A, 0

msg_memmove_test_start:              db "Running VMM AVX2-Optimized memmove Test...", 0x0D, 0x0A, 0
msg_memmove_test_passed:             db "VMM AVX2-Optimized memmove Test PASSED!", 0x0D, 0x0A, 0
msg_memmove_fail_alloc_str:          db "Failure: Could not allocate memory for memmove test buffer.", 0x0D, 0x0A, 0
msg_memmove_fail_ret_str:            db "Failure: memmove did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memmove_fail_data_str:           db "Failure: memmove did not copy/shift the data payload correctly.", 0x0D, 0x0A, 0

msg_numa_test_start:            db "Running VMM NUMA ACPI SRAT/SLIT Parsing & Fallback Test...", 0x0D, 0x0A, 0
msg_numa_test_passed:           db "VMM NUMA ACPI SRAT/SLIT Parsing & Fallback Test PASSED!", 0x0D, 0x0A, 0
msg_numa_ranges_found:          db "NUMA Memory Ranges found in SRAT:", 0x0D, 0x0A, 0
msg_numa_range_base:            db "  Range base: 0x", 0
msg_numa_range_len:             db "  length: 0x", 0
msg_numa_range_node:            db "  Node ID: ", 0
msg_numa_node_count:           db "NUMA Node Count: ", 0
msg_numa_matrix_header:        db "NUMA Node Distance Matrix:", 0x0D, 0x0A, 0
msg_numa_node_prefix:          db "  Node ", 0
msg_numa_node_arrow:           db " -> ", 0
msg_numa_node_colon:           db ": ", 0
msg_numa_local_info_header:  db "NUMA Node-Local Bitmap Info:", 0x0D, 0x0A, 0
msg_numa_node_bmp_base:     db " Bitmap: Base=0x", 0
msg_numa_node_bmp_size:     db " Size=0x", 0
msg_numa_node_bmp_free:     db " FreePages=", 0
msg_numa_sim_oom_start:      db "NUMA: Starting simulated Node 0 memory exhaustion test...", 0x0D, 0x0A, 0
msg_numa_sim_oom_ok:         db "NUMA: Simulated Node 0 memory exhaustion test PASSED!", 0x0D, 0x0A, 0
msg_numa_fail_count_str:        db "Failure: NUMA range count is 0.", 0x0D, 0x0A, 0
msg_numa_fail_lookup_str:       db "Failure: NUMA Node ID lookup for out-of-bounds address did not return 0.", 0x0D, 0x0A, 0
msg_numa_fail_dist_bounds_str: db "Failure: NUMA distance out-of-bounds check did not return 255.", 0x0D, 0x0A, 0
msg_numa_fail_bmp_init_str:  db "Failure: Node-Local bitmaps not initialized or active flag is 0.", 0x0D, 0x0A, 0
msg_numa_fail_alloc_node_str:db "Failure: phys_alloc_page_node returned 0 for Node 0.", 0x0D, 0x0A, 0
msg_numa_fail_affinity_str:  db "Failure: Allocated page Node ID does not match requested Node ID.", 0x0D, 0x0A, 0
msg_numa_fail_fallback_str:  db "Failure: Fallback allocation for out-of-bounds node 99 returned 0.", 0x0D, 0x0A, 0
msg_numa_fail_sim_oom_alloc_str: db "Failure: Fallback allocation under simulated OOM returned 0.", 0x0D, 0x0A, 0
msg_numa_fail_sim_oom_affinity_str: db "Failure: Fallback allocation under simulated OOM did not allocate from adjacent Node 1.", 0x0D, 0x0A, 0

msg_smep_smap_test_start:      db "Running VMM SMEP/SMAP Protection Test...", 0x0D, 0x0A, 0
msg_smep_smap_test_passed:     db "VMM SMEP/SMAP Protection Test PASSED!", 0x0D, 0x0A, 0
msg_smep_smap_test_data:       db "SMAP_TEST_SIGNATURE", 0
msg_smep_smap_fail_alloc_str:  db "Failure: Could not allocate user page.", 0x0D, 0x0A, 0
msg_smep_smap_fail_vma_str:    db "Failure: Could not create user VMA.", 0x0D, 0x0A, 0
msg_smep_smap_fail_map_str:    db "Failure: Could not map user page.", 0x0D, 0x0A, 0
msg_smep_smap_fail_copy_to_str: db "Failure: copy_to_user returned error or failed.", 0x0D, 0x0A, 0
msg_smep_smap_fail_copy_from_str: db "Failure: copy_from_user returned error or failed.", 0x0D, 0x0A, 0
msg_smep_smap_fail_data_str:   db "Failure: Data read back from user page does not match signature.", 0x0D, 0x0A, 0

msg_zof_test_start:             db "Running VMM Zeroing on Free Tests...", 0x0D, 0x0A, 0
msg_zof_test_passed:            db "VMM Zeroing on Free Tests PASSED!", 0x0D, 0x0A, 0
msg_zof_fail_heap_alloc_str:    db "Failure: Could not allocate memory from heap for Zero on Free test.", 0x0D, 0x0A, 0
msg_zof_fail_heap_zero_str:     db "Failure: Heap memory was not zeroed out on free.", 0x0D, 0x0A, 0
msg_zof_fail_phys_alloc_str:    db "Failure: Could not allocate physical page for Zero on Free test.", 0x0D, 0x0A, 0
msg_zof_fail_phys_zero_str:     db "Failure: Physical page was not zeroed out on free.", 0x0D, 0x0A, 0

msg_mmap_test_start:            db "Running VMM Memory-Mapped Files (mmap) Tests...", 0x0D, 0x0A, 0
msg_mmap_test_passed:           db "VMM Memory-Mapped Files (mmap) Tests PASSED!", 0x0D, 0x0A, 0
msg_mmap_fail_create:           db "Failure: Could not create mock file.", 0x0D, 0x0A, 0
msg_mmap_fail_map:              db "Failure: Could not map file to VMA.", 0x0D, 0x0A, 0
msg_mmap_fail_read_val:         db "Failure: Read value from memory-mapped file does not match signature.", 0x0D, 0x0A, 0
msg_mmap_fail_read_offset:      db "Failure: Offset read from memory-mapped file does not match expected.", 0x0D, 0x0A, 0
msg_mmap_fail_pte:              db "Failure: Walk table returned null PTE for memory-mapped page.", 0x0D, 0x0A, 0
msg_mmap_fail_dirty:            db "Failure: PAGE_DIRTY bit not set in PTE after memory write.", 0x0D, 0x0A, 0
msg_mmap_fail_sync:             db "Failure: mmap_msync returned error.", 0x0D, 0x0A, 0
msg_mmap_fail_not_cleared:      db "Failure: PAGE_DIRTY bit not cleared in PTE after msync.", 0x0D, 0x0A, 0
msg_mmap_fail_backing:          db "Failure: Backing mock file block is null after msync.", 0x0D, 0x0A, 0
msg_mmap_fail_backing_data:     db "Failure: backing mock file block data does not match synced RAM page.", 0x0D, 0x0A, 0
msg_mmap_fail_unmap:            db "Failure: mmap_munmap returned error.", 0x0D, 0x0A, 0

msg_ipc_test_start:             db "Running VMM Shared Memory & IPC Tests...", 0x0D, 0x0A, 0
msg_ipc_test_passed:            db "VMM Shared Memory & IPC Tests PASSED!", 0x0D, 0x0A, 0
msg_ipc_fail_pml4:              db "Failure: Could not create secondary PML4.", 0x0D, 0x0A, 0
msg_ipc_fail_alloc:             db "Failure: Could not allocate physical page for shared memory.", 0x0D, 0x0A, 0
msg_ipc_fail_map:               db "Failure: Could not map page in current address space.", 0x0D, 0x0A, 0
msg_ipc_fail_share:             db "Failure: ipc_share_frame returned error.", 0x0D, 0x0A, 0
msg_ipc_fail_shared_val:        db "Failure: Value in shared frame does not match signature.", 0x0D, 0x0A, 0
msg_ipc_fail_ring_create:       db "Failure: Could not create consecutive ring buffer.", 0x0D, 0x0A, 0
msg_ipc_fail_ring_val:          db "Failure: Consecutive ring buffer second half read failed or mismatch.", 0x0D, 0x0A, 0
msg_ipc_fail_ring_cross_val:    db "Failure: Consecutive ring buffer write/read cross-validation mismatch.", 0x0D, 0x0A, 0

msg_leak_test_start:            db "Running VMM Memory Leak Tracker Tests...", 0x0D, 0x0A, 0
msg_leak_test_passed:           db "VMM Memory Leak Tracker Tests PASSED!", 0x0D, 0x0A, 0
msg_leak_fail_initial:          db "Failure: Leak tracker reported non-zero leaks initially.", 0x0D, 0x0A, 0
msg_leak_fail_alloc:            db "Failure: Could not allocate heap memory for leak tracker test.", 0x0D, 0x0A, 0
msg_leak_fail_count:            db "Failure: Leak tracker did not report exactly 1 leak after partial free.", 0x0D, 0x0A, 0
msg_leak_fail_verify:           db "Failure: Logged leak pointer did not match the leaked block.", 0x0D, 0x0A, 0
msg_leak_fail_final:            db "Failure: Leak tracker reported non-zero leaks after all blocks freed.", 0x0D, 0x0A, 0

msg_uaf_test_start:             db "Running VMM Use-After-Free Trap Tests...", 0x0D, 0x0A, 0
msg_uaf_fail_alloc_str:         db "Failure: Could not allocate physical page for UAF test.", 0x0D, 0x0A, 0
msg_uaf_fail_map_str:           db "Failure: Could not map page for UAF test.", 0x0D, 0x0A, 0
msg_uaf_fail_trap:              db "Failure: Access to freed memory did not trigger UAF Trap panic.", 0x0D, 0x0A, 0

msg_tsx_test_start:            db "Running VMM TSX Fault Handling Tests...", 0x0D, 0x0A, 0
msg_tsx_success_ok:            db "  TSX Success Case: Transaction successfully retried and committed.", 0x0D, 0x0A, 0
msg_tsx_abort_ok:              db "  TSX Abort Case: Unresolvable fault successfully redirected to fallback.", 0x0D, 0x0A, 0
msg_tsx_test_passed:           db "VMM TSX Fault Handling Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_test_fail_vma:         db "Failure: Could not create TSX VMA.", 0x0D, 0x0A, 0
msg_tsx_test_fail_data:        db "Failure: TSX success case data mismatch.", 0x0D, 0x0A, 0
msg_tsx_fail_success_fallback: db "Failure: TSX success case entered fallback path.", 0x0D, 0x0A, 0
msg_tsx_fail_no_abort:         db "Failure: Unresolvable fault did not abort transaction to fallback.", 0x0D, 0x0A, 0

msg_tsx_spec_walk_test_start:        db "Running TSX Speculative Directory Walk Engine Tests...", 0x0D, 0x0A, 0
msg_tsx_spec_walk_test_passed:       db "TSX Speculative Directory Walk Engine Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_spec_walk_fail_vma_str:      db "Failure: Could not create speculative walk VMA.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_init_str:     db "Failure: Initial cache hit on unmapped address before walk.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_lookup_str:   db "Failure: Speculative walk did not cache translation mapping.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_mismatch_str: db "Failure: Cached physical address does not match page table walk result.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_inval_str:    db "Failure: Invalidate did not clear cached translation entry.", 0x0D, 0x0A, 0

msg_tsx_lock_test_start:             db "Running TSX Lock-Free Directory Updates (Lock Elision) Tests...", 0x0D, 0x0A, 0
msg_tsx_lock_bypass_ok:              db "  Lock Elision Success: Speculative block bypassed spinlock write.", 0x0D, 0x0A, 0
msg_tsx_lock_traditional_ok:         db "  Lock Fallback Success: Traditional lock acquired when TSX disabled.", 0x0D, 0x0A, 0
msg_tsx_lock_test_passed:            db "TSX Lock-Free Directory Updates Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_lock_fail_active_str:        db "Failure: Speculative acquire did not set tsx_active to 1.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_bypass_str:        db "Failure: Speculative acquire modified lock byte (bypass failed).", 0x0D, 0x0A, 0
msg_tsx_lock_fail_rel_active_str:    db "Failure: Speculative release did not clear tsx_active.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_rel_lock_str:      db "Failure: Speculative release modified lock byte.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_trad_str:          db "Failure: Traditional acquire did not set lock byte to 1.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_trad_rel_str:      db "Failure: Traditional release did not clear lock byte to 0.", 0x0D, 0x0A, 0

msg_hle_test_start:            db "Running HLE Protection & Caching Tests...", 0x0D, 0x0A, 0
msg_hle_test_passed:           db "HLE Protection & Caching Tests PASSED!", 0x0D, 0x0A, 0
msg_hle_fail_alloc_str:        db "Failure: Could not allocate page for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_map_str:          db "Failure: Could not map page for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_walk1_str:        db "Failure: Initial walk failed for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_flags1_str:       db "Failure: Caching flags not set on map for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_walk2_str:        db "Failure: Post-protect walk failed for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_flags2_str:       db "Failure: hle_protect_range did not clear cache flags.", 0x0D, 0x0A, 0
msg_hle_fail_align1_str:       db "Failure: hle_is_cache_aligned returned 0 for aligned address.", 0x0D, 0x0A, 0
msg_hle_fail_align2_str:       db "Failure: hle_is_cache_aligned returned 1 for unaligned address.", 0x0D, 0x0A, 0

msg_tsx_fallback_lock_test_start:          db "Running TSX Fallback Page-Directory Lock Manager Tests...", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_limit_ok:            db "  Fallback Success: Traditional spinlock acquired when limits exceeded.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_decay_ok:            db "  Decay Success: Abort count decayed and lock released traditionally.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_test_passed:          db "TSX Fallback Page-Directory Lock Manager Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_fallback_lock_fail_init_active_str:    db "Failure: Speculative acquire did not set tsx_active on clean lock.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_init_lock_str:      db "Failure: Speculative acquire modified lock byte on clean lock.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_bypass_active_str:  db "Failure: Acquire set tsx_active when abort limits exceeded.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_bypass_lock_str:    db "Failure: Acquire did not write lock byte when abort limits exceeded.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_decay_lock_str:     db "Failure: Traditional release did not clear lock byte.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_decay_count_str:    db "Failure: Traditional release did not decay abort count.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_retry_active_str:   db "Failure: Acquire did not attempt TSX after abort count decayed.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_retry_lock_str:     db "Failure: Acquire modified lock byte after abort count decayed.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_final_count_str:    db "Failure: Speculative release did not reset abort count to 0.", 0x0D, 0x0A, 0

msg_aslr_rand_test_start:     db "Running ASLR Symbol Offset Randomization Tests...", 0x0D, 0x0A, 0
msg_aslr_rand_test_passed:    db "ASLR Symbol Offset Randomization Test PASSED!", 0x0D, 0x0A, 0
msg_aslr_fail_alloc_str:      db "Failure: heap_alloc returned NULL for ASLR test.", 0x0D, 0x0A, 0
msg_aslr_fail_align_str:      db "Failure: ASLR offsetted pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_aslr_fail_bounds_str:     db "Failure: ASLR random gap size is out of bounds or misaligned.", 0x0D, 0x0A, 0

msg_shuffling_test_start:         db "Running Virtual Page Table Shuffling Tests...", 0x0D, 0x0A, 0
msg_shuffling_index_ok:           db "  [Shuffling Test] Verification succeeded: logical index 1 randomized in pml4_shuffle_map.", 0x0D, 0x0A, 0
msg_shuffling_access_ok:          db "  [Shuffling Test] Access (write/read) via physical virtual address succeeded.", 0x0D, 0x0A, 0
msg_shuffling_test_passed:         db "Virtual Page Table Shuffling Tests PASSED!", 0x0D, 0x0A, 0
msg_shuffling_fail_identity_str:  db "Failure: Logical index 1 mapped to identity slot in pml4_shuffle_map (not shuffled).", 0x0D, 0x0A, 0
msg_shuffling_fail_alloc_str:     db "Failure: Could not allocate physical page for shuffling test.", 0x0D, 0x0A, 0
msg_shuffling_fail_map_str:       db "Failure: Could not map page at logical index 1 for shuffling test.", 0x0D, 0x0A, 0
msg_shuffling_fail_phys_vaddr_str: db "Failure: Physical virtual address PML4 index does not match pml4_shuffle_map.", 0x0D, 0x0A, 0
msg_shuffling_fail_data_str:       db "Failure: Data read back from physical virtual address does not match signature.", 0x0D, 0x0A, 0
msg_shuffling_fail_walk_str:       db "Failure: Walk table returned 0 for logical address 0x8000000000.", 0x0D, 0x0A, 0
msg_shuffling_fail_walk_phys_str:  db "Failure: Mapped physical address does not match allocated page frame.", 0x0D, 0x0A, 0

msg_decoy_test_start:         db "Running Decoy Memory Pages Security Tests...", 0x0D, 0x0A, 0
msg_decoy_pte_verify_ok:      db "  [Decoy Test] PTE verification succeeded (mapped to decoy_page_phys and is executable).", 0x0D, 0x0A, 0
msg_decoy_call_ok:            db "  [Decoy Test] Executing decoy call returned successfully.", 0x0D, 0x0A, 0
msg_decoy_test_passed:        db "Decoy Memory Pages Security Tests PASSED!", 0x0D, 0x0A, 0
msg_decoy_fail_map_str:       db "Failure: Could not map page with virt_map_decoy.", 0x0D, 0x0A, 0
msg_decoy_fail_walk_str:      db "Failure: Walk table returned 0 for mapped decoy page.", 0x0D, 0x0A, 0
msg_decoy_fail_pte_present_str: db "Failure: Decoy page is not marked present in PTE.", 0x0D, 0x0A, 0
msg_decoy_fail_pte_nx_str:      db "Failure: Decoy page has PAGE_NX set (must be executable).", 0x0D, 0x0A, 0
msg_decoy_fail_pte_phys_str:    db "Failure: Decoy page does not point to decoy_page_phys.", 0x0D, 0x0A, 0

msg_temporal_test_start:         db "Running Temporal Layout Obfuscation Security Tests...", 0x0D, 0x0A, 0
msg_temporal_test_passed:        db "Temporal Layout Obfuscation Security Tests PASSED!", 0x0D, 0x0A, 0
msg_temporal_fail_init_str:      db "Failure: Could not initialize temporal obfuscation.", 0x0D, 0x0A, 0
msg_temporal_fail_not_moved_str: db "Failure: Code section virtual address was not relocated after tick threshold.", 0x0D, 0x0A, 0
msg_temporal_fail_still_present_str: db "Failure: Old virtual mapping is still present in page table after migration.", 0x0D, 0x0A, 0
msg_temporal_fail_walk_new_str:  db "Failure: Walk table returned 0 for newly migrated address.", 0x0D, 0x0A, 0

msg_stack_offset_test_start:         db "Running Stack Frame Offset Randomization Security Tests...", 0x0D, 0x0A, 0
msg_stack_offset_test_passed:        db "Stack Frame Offset Randomization Security Tests PASSED!", 0x0D, 0x0A, 0
msg_stack_offset_fail_alloc_str:      db "Failure: thread_stack_alloc returned NULL.", 0x0D, 0x0A, 0
msg_stack_offset_fail_align_str:      db "Failure: Allocated stack address is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_stack_offset_fail_vma_str:        db "Failure: Could not find VMA for stack address.", 0x0D, 0x0A, 0
msg_stack_offset_fail_bounds_str:     db "Failure: Stack random offset is out of bounds or misaligned.", 0x0D, 0x0A, 0

msg_dax_test_start:                 db "Running VMM DAX Zero-Cache Block Mapping Tests...", 0x0D, 0x0A, 0
msg_dax_test_passed:                db "VMM DAX Zero-Cache Block Mapping Tests PASSED!", 0x0D, 0x0A, 0
msg_dax_fail_create_str:            db "Failure: Could not create mock file for DAX test.", 0x0D, 0x0A, 0
msg_dax_fail_map_str:               db "Failure: Could not map DAX VMA.", 0x0D, 0x0A, 0
msg_dax_fail_backing_str:           db "Failure: Backing mock file block is null on write.", 0x0D, 0x0A, 0
msg_dax_fail_data_str:              db "Failure: Direct modification of backing block failed or value mismatch.", 0x0D, 0x0A, 0
msg_dax_fail_unmap_str:             db "Failure: Munmap returned error on DAX VMA.", 0x0D, 0x0A, 0
msg_dax_fail_unmap_freed_str:       db "Failure: Backing blocks were freed or cleared on munmap.", 0x0D, 0x0A, 0
msg_dax_fail_unmap_data_str:        db "Failure: Synced values modified or corrupted after munmap.", 0x0D, 0x0A, 0

msg_pmem_test_start:                db "Running VMM PMEM Byte-Addressability Tests...", 0x0D, 0x0A, 0
msg_pmem_test_passed:               db "VMM PMEM Byte-Addressability Tests PASSED!", 0x0D, 0x0A, 0
msg_pmem_fail_alloc_str:            db "Failure: Could not allocate physical page for PMEM test.", 0x0D, 0x0A, 0
msg_pmem_fail_map_str:              db "Failure: Could not map PMEM VMA.", 0x0D, 0x0A, 0
msg_pmem_fail_data_str:             db "Failure: Direct modification of PMEM physical block failed or value mismatch.", 0x0D, 0x0A, 0
msg_pmem_fail_unmap_str:            db "Failure: Munmap returned error on PMEM VMA.", 0x0D, 0x0A, 0
msg_pmem_fail_unmap_data_str:       db "Failure: PMEM physical block data changed after unmap.", 0x0D, 0x0A, 0

msg_window_test_start:              db "Running VMM PMEM Hardware Block Window Tests...", 0x0D, 0x0A, 0
msg_window_test_passed:             db "VMM PMEM Hardware Block Window Tests PASSED!", 0x0D, 0x0A, 0
msg_window_fail_alloc_desc_str:     db "Failure: Could not allocate memory for pmem_window_t descriptor.", 0x0D, 0x0A, 0
msg_window_fail_init_str:           db "Failure: Could not initialize hardware block window data page.", 0x0D, 0x0A, 0
msg_window_fail_map_str:            db "Failure: Could not map pmem window VMA.", 0x0D, 0x0A, 0
msg_window_fail_sig_str:            db "Failure: Static window data page does not contain correct block signature.", 0x0D, 0x0A, 0
msg_window_fail_backing_str:        db "Failure: Backing physical block was not allocated after flush.", 0x0D, 0x0A, 0
msg_window_fail_backing_data_str:   db "Failure: Backing physical block does not contain flushed window data.", 0x0D, 0x0A, 0
msg_window_fail_unmap_str:          db "Failure: Munmap returned error on pmem window VMA.", 0x0D, 0x0A, 0

msg_bypass_test_start:             db "Running VMM PMEM Direct Write Cache Bypass Tests...", 0x0D, 0x0A, 0
msg_bypass_test_passed:            db "VMM PMEM Direct Write Cache Bypass Tests PASSED!", 0x0D, 0x0A, 0
msg_bypass_fail_alloc_str:         db "Failure: Could not allocate source physical page for bypass test.", 0x0D, 0x0A, 0
msg_bypass_fail_alloc_dest_str:    db "Failure: Could not allocate destination physical page for bypass test.", 0x0D, 0x0A, 0
msg_bypass_fail_map_str:           db "Failure: Could not map pages for bypass test.", 0x0D, 0x0A, 0
msg_bypass_fail_data_str:          db "Failure: Direct write bypass data verification mismatch.", 0x0D, 0x0A, 0

msg_barrier_test_start:            db "Running VMM PMEM Hardware Metadata Barrier Flushing Tests...", 0x0D, 0x0A, 0
msg_barrier_test_passed:           db "VMM PMEM Hardware Metadata Barrier Flushing Tests PASSED!", 0x0D, 0x0A, 0
msg_barrier_fail_alloc_str:        db "Failure: Could not allocate physical page for barrier test.", 0x0D, 0x0A, 0
msg_barrier_fail_map_str:          db "Failure: Could not map page for barrier test.", 0x0D, 0x0A, 0
msg_barrier_fail_data_str:         db "Failure: PMEM barrier data integrity verification failed.", 0x0D, 0x0A, 0

msg_xo_test_start:            db "Running Execute-Only (XO) Pages Security Tests...", 0x0D, 0x0A, 0
msg_xo_pku_supported:         db "  [XO Test] Hardware PKU support detected. Enabling CR4.PKE...", 0x0D, 0x0A, 0
msg_xo_pku_unsupported:       db "  [XO Test] Hardware PKU not supported. Using software-fallback (P=0)...", 0x0D, 0x0A, 0
msg_xo_pte_verify_ok:         db "  [XO Test] PTE verification succeeded. Attempting read access...", 0x0D, 0x0A, 0
msg_xo_fail_alloc_str:        db "Failure: Could not allocate physical page for XO test.", 0x0D, 0x0A, 0
msg_xo_fail_map_str:          db "Failure: Could not map page with PAGE_XO for XO test.", 0x0D, 0x0A, 0
msg_xo_fail_walk_str:         db "Failure: virt_walk_table returned 0 for mapped XO page.", 0x0D, 0x0A, 0
msg_xo_fail_pte_present_str:  db "Failure: Hardware PKU mapped page is not present in PTE.", 0x0D, 0x0A, 0
msg_xo_fail_pte_key_str:      db "Failure: Hardware PKU mapped page does not have Key 1 in PTE.", 0x0D, 0x0A, 0
msg_xo_fail_pte_nx_str:       db "Failure: Hardware PKU mapped page has NX set (must be 0 for execution).", 0x0D, 0x0A, 0
msg_xo_fail_pte_absent_str:   db "Failure: Software fallback mapped page is present in PTE (must be 0).", 0x0D, 0x0A, 0
msg_xo_fail_pte_xo_str:       db "Failure: Software fallback mapped page does not have PAGE_XO bit set.", 0x0D, 0x0A, 0
msg_xo_fail_trap:             db "Failure: Read access to Execute-Only page did not trigger page fault violation.", 0x0D, 0x0A, 0

; Dirty Tracing Test messages
msg_dbg_watch_test_start:          db "Running VMM Page-Granular Hardware Debugging & Watchpoints Tests...", 0x0D, 0x0A, 0
msg_dbg_watch_test_passed:         db "VMM Page-Granular Hardware Debugging & Watchpoints Tests PASSED!", 0x0D, 0x0A, 0

msg_dbg_watch_fail_alloc_str:      db "Failure: Could not allocate physical page for dirty tracing test.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_vma_str:        db "Failure: Could not create VMA for dirty tracing test.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_map_str:        db "Failure: Could not map page for dirty tracing test.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_register_str:   db "Failure: dbg_dirty_trace_register returned 0.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_walk_str:       db "Failure: Could not walk page table for registered page.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_protected_str:  db "Failure: Registered page was not write-protected in PTE.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_dirty_init_str: db "Failure: Tracked page reported dirty before write.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_dirty_post_str: db "Failure: Tracked page did not report dirty after write.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_rip_mismatch_str: db "Failure: Logged RIP does not match instruction RIP.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_writable_post_str: db "Failure: PAGE_WRITABLE not restored in PTE after fault.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_clear_str:      db "Failure: Clear dirty status returned 0.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_dirty_clear_str: db "Failure: Tracked page reported dirty after clearing.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_rip_clear_str:   db "Failure: Logged RIP not cleared to 0 after clearing.", 0x0D, 0x0A, 0
msg_dbg_watch_fail_protected_clear_str: db "Failure: Page not write-protected again after clearing.", 0x0D, 0x0A, 0

; Page Watchpoint Test messages
msg_dbg_wp_test_start:            db "Running VMM Page Watchpoint Tests...", 0x0D, 0x0A, 0
msg_dbg_wp_test_passed:           db "VMM Page Watchpoint Tests PASSED!", 0x0D, 0x0A, 0

msg_dbg_wp_fail_alloc_str:        db "Failure: Could not allocate physical page for watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_vma_str:          db "Failure: Could not create VMA for watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_map_str:          db "Failure: Could not map page for watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_register_str:     db "Failure: dbg_watchpoint_register returned 0.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_walk_str:         db "Failure: Could not walk page table for watched page.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_non_present_str:  db "Failure: Watched page is still marked present in PTE.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_hit_init_str:     db "Failure: Watched page reported hit count > 0 before access.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_hit_read_str:     db "Failure: Watched page did not increment hit count after read access.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_rip_read_str:     db "Failure: Logged RIP after read does not match read instruction RIP.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_type_read_str:    db "Failure: Logged type after read is not 0 (read).", 0x0D, 0x0A, 0
msg_dbg_wp_fail_present_read_str: db "Failure: Watched page not restored to present in PTE after read.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_rearm_str:        db "Failure: dbg_watchpoint_rearm returned 0.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_hit_write_str:    db "Failure: Watched page did not increment hit count after write access.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_rip_write_str:    db "Failure: Logged RIP after write does not match write instruction RIP.", 0x0D, 0x0A, 0
msg_dbg_wp_fail_type_write_str:   db "Failure: Logged type after write is not 1 (write).", 0x0D, 0x0A, 0
msg_dbg_wp_fail_deregister_str:   db "Failure: dbg_watchpoint_deregister returned 0.", 0x0D, 0x0A, 0

; Instruction Fetch Trace Test messages
msg_dbg_ift_test_start:            db "Running VMM Instruction Fetch Trace Watchpoint Tests...", 0x0D, 0x0A, 0
msg_dbg_ift_test_passed:           db "VMM Instruction Fetch Trace Watchpoint Tests PASSED!", 0x0D, 0x0A, 0

msg_dbg_ift_fail_alloc_str:        db "Failure: Could not allocate physical page for IFT watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_vma_str:          db "Failure: Could not create VMA for IFT watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_map_str:          db "Failure: Could not map page for IFT watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_register_str:     db "Failure: dbg_ift_register returned 0.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_walk_str:         db "Failure: Could not walk page table for IFT watched page.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_nx_set_str:       db "Failure: IFT watched page does not have NX bit set in PTE.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_hit_init_str:     db "Failure: IFT watched page reported hit count > 0 before access.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_hit_exec_str:     db "Failure: IFT watched page did not increment hit count after execution.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_rip_exec_str:     db "Failure: Logged IFT RIP does not match execution RIP (0x40000000).", 0x0D, 0x0A, 0
msg_dbg_ift_fail_nx_cleared_str:   db "Failure: IFT watched page still has NX set in PTE after execution.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_rearm_str:        db "Failure: dbg_ift_rearm returned 0.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_nx_rearmed_str:   db "Failure: IFT watched page does not have NX bit set in PTE after rearm.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_hit_exec2_str:    db "Failure: IFT watched page did not increment hit count to 2 after second execution.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_rip_exec2_str:    db "Failure: Logged IFT RIP after second execution does not match 0x40000000.", 0x0D, 0x0A, 0
msg_dbg_ift_fail_deregister_str:   db "Failure: dbg_ift_deregister returned 0.", 0x0D, 0x0A, 0

; Access Pattern Histogram Test messages
msg_dbg_hist_test_start:            db "Running VMM Access Pattern Histogram Recorder Tests...", 0x0D, 0x0A, 0
msg_dbg_hist_test_passed:           db "VMM Access Pattern Histogram Recorder Tests PASSED!", 0x0D, 0x0A, 0

msg_dbg_hist_fail_alloc_str:        db "Failure: Could not allocate physical page for access histogram test.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_vma_str:          db "Failure: Could not create VMA for access histogram test.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_map_str:          db "Failure: Could not map page for access histogram test.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_register_str:     db "Failure: dbg_hist_register returned 0.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_walk_str:         db "Failure: Could not walk page table for access histogram page.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_non_present_str:  db "Failure: Access histogram monitored page is still present in PTE.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_count_init_str:   db "Failure: Access histogram reported non-zero hits before access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_read_count_str:   db "Failure: Read count did not increment to 1 after read access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_write_count_str:  db "Failure: Write count incremented on read access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_total_count_str:  db "Failure: Total count did not increment to 1 after read access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_present_restored_str: db "Failure: Monitored page was not restored to present after fault.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_rearm_str:        db "Failure: dbg_hist_rearm returned 0.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_read_count2_str:  db "Failure: Read count modified on write access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_write_count2_str: db "Failure: Write count did not increment to 1 after write access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_total_count2_str: db "Failure: Total count did not increment to 2 after write access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_read_count3_str:  db "Failure: Read count did not increment to 2 after second read.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_write_count3_str: db "Failure: Write count modified on second read access.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_total_count3_str: db "Failure: Total count did not increment to 3 after second read.", 0x0D, 0x0A, 0
msg_dbg_hist_fail_deregister_str:   db "Failure: dbg_hist_deregister returned 0.", 0x0D, 0x0A, 0

; Physical Address Watch Trap Test messages
msg_dbg_phys_wp_test_start:            db "Running VMM Physical Address Watch Trap Tests...", 0x0D, 0x0A, 0
msg_dbg_phys_wp_test_passed:           db "VMM Physical Address Watch Trap Tests PASSED!", 0x0D, 0x0A, 0

msg_dbg_phys_wp_fail_alloc_str:        db "Failure: Could not allocate physical page for physical watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_vma1_str:          db "Failure: Could not create VMA 1 for physical watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_vma2_str:          db "Failure: Could not create VMA 2 for physical watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_map1_str:          db "Failure: Could not map VMA 1 for physical watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_map2_str:          db "Failure: Could not map VMA 2 for physical watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_register_str:     db "Failure: dbg_phys_wp_register returned 0.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_walk_str:         db "Failure: Could not walk page table for physical watchpoint test.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_non_present_str:  db "Failure: Physical watchpoint mapped page is still present in PTE.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_hit_init_str:     db "Failure: Physical watchpoint reported hit count > 0 before access.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_hit_read_str:     db "Failure: Physical watchpoint did not increment hit count after read access.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_rip_read_str:     db "Failure: Logged RIP after read does not match read instruction RIP.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_vaddr_read_str:    db "Failure: Logged virtual address alias does not match 0x30000000.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_type_read_str:    db "Failure: Logged type after read is not 0 (read).", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_present_restored_str: db "Failure: Monitored alias page not restored to present in PTE.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_rearm_str:        db "Failure: dbg_phys_wp_rearm returned 0.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_hit_write_str:    db "Failure: Physical watchpoint did not increment hit count after write access.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_rip_write_str:    db "Failure: Logged RIP after write does not match write instruction RIP.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_vaddr_write_str:   db "Failure: Logged virtual address alias does not match 0x40000000.", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_type_write_str:   db "Failure: Logged type after write is not 1 (write).", 0x0D, 0x0A, 0
msg_dbg_phys_wp_fail_deregister_str:   db "Failure: dbg_phys_wp_deregister returned 0.", 0x0D, 0x0A, 0

; Overcommit Policy Engine Test messages
msg_overcommit_test_start:                 db "Running VMM Overcommit Policy Engine Test...", 0x0D, 0x0A, 0
msg_overcommit_test_passed:                db "VMM Overcommit Policy Engine Test PASSED!", 0x0D, 0x0A, 0
msg_overcommit_fail_always_str:            db "Failure: VMA allocation denied in OVERCOMMIT_ALWAYS mode.", 0x0D, 0x0A, 0
msg_overcommit_fail_never_succeed_str:     db "Failure: VMA allocation denied within physical limits in OVERCOMMIT_NEVER mode.", 0x0D, 0x0A, 0
msg_overcommit_fail_never_fail_str:        db "Failure: VMA allocation allowed beyond physical limits in OVERCOMMIT_NEVER mode.", 0x0D, 0x0A, 0
msg_overcommit_fail_heuristic_succeed_str: db "Failure: VMA allocation denied within heuristic limit in OVERCOMMIT_HEURISTIC mode.", 0x0D, 0x0A, 0
msg_overcommit_fail_heuristic_fail_str:    db "Failure: VMA allocation allowed beyond heuristic limit in OVERCOMMIT_HEURISTIC mode.", 0x0D, 0x0A, 0

; OOM Score Calculator Test messages
msg_oom_score_test_start:                  db "Running VMM OOM Score Calculator Test...", 0x0D, 0x0A, 0
msg_oom_score_test_passed:                 db "VMM OOM Score Calculator Test PASSED!", 0x0D, 0x0A, 0
msg_oom_score_fail_register_str:           db "Failure: Could not register thread for OOM score test.", 0x0D, 0x0A, 0
msg_oom_score_fail_calc_a_str:             db "Failure: Incorrect OOM score calculated for Thread A.", 0x0D, 0x0A, 0
msg_oom_score_fail_calc_b_str:             db "Failure: Incorrect OOM score calculated for Thread B.", 0x0D, 0x0A, 0
msg_oom_score_fail_select_b_str:           db "Failure: OOM select victim did not return Thread B.", 0x0D, 0x0A, 0
msg_oom_score_fail_select_a_str:           db "Failure: OOM select victim did not return Thread A after weight adjustment.", 0x0D, 0x0A, 0

; OOM Killer Test messages
msg_oom_killer_test_start:                 db "Running VMM OOM Killer Test...", 0x0D, 0x0A, 0
msg_oom_killer_test_passed:                db "VMM OOM Killer Test PASSED!", 0x0D, 0x0A, 0
msg_oom_kill_fail_register_str:            db "Failure: Could not register Thread V (victim) for OOM Killer test.", 0x0D, 0x0A, 0
msg_oom_kill_fail_alloc_str:               db "Failure: VMA allocation failed to allocate after OOM Killer execution.", 0x0D, 0x0A, 0
msg_oom_kill_fail_not_terminated_str:      db "Failure: Thread V (victim) was not terminated by OOM Killer.", 0x0D, 0x0A, 0

; OOM Notifier Test messages
msg_oom_notifier_test_start:               db "Running VMM OOM Notifier Test...", 0x0D, 0x0A, 0
msg_oom_notifier_test_passed:              db "VMM OOM Notifier Test PASSED!", 0x0D, 0x0A, 0
msg_oom_callback_executed:                 db "[OOM Callback] Graceful shutdown callback executed successfully.", 0x0D, 0x0A, 0
msg_oom_notify_fail_register_str:          db "Failure: Could not register Thread N (victim) for OOM Notifier test.", 0x0D, 0x0A, 0
msg_oom_notify_fail_alloc_str:             db "Failure: VMA allocation failed to allocate after OOM Notifier execution.", 0x0D, 0x0A, 0
msg_oom_notify_fail_not_terminated_str:     db "Failure: Thread N (victim) was not terminated by OOM Killer after notification.", 0x0D, 0x0A, 0
msg_oom_notify_fail_callback_not_run_str:  db "Failure: Graceful shutdown callback was not executed before process termination.", 0x0D, 0x0A, 0

; OOM Cgroup Test messages
msg_oom_cgroup_test_start:                 db "Running VMM Memory Cgroup Limits Test...", 0x0D, 0x0A, 0
msg_oom_cgroup_test_passed:                db "VMM Memory Cgroup Limits Test PASSED!", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_create_str:            db "Failure: Could not create memory cgroup 500.", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_register_str:          db "Failure: Could not register threads for Memory Cgroup Limits test.", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_soft_alloc_str:        db "Failure: VMA allocation failed under soft limit check.", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_soft_charge_str:       db "Failure: Memory Cgroup usage was not charged correctly under soft limit.", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_hard_alloc_str:        db "Failure: VMA allocation failed under hard limit check.", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_not_killed_str:        db "Failure: Localized OOM killer did not terminate victim Thread B.", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_killed_wrong_str:      db "Failure: Localized OOM killer terminated wrong thread (Thread A).", 0x0D, 0x0A, 0
msg_oom_cgroup_fail_final_charge_str:      db "Failure: Memory Cgroup usage was not correctly charged or released.", 0x0D, 0x0A, 0

; Allocation Retry with Reclaim Test messages
msg_oom_retry_test_start:                 db "Running VMM Allocation Retry with Reclaim Test...", 0x0D, 0x0A, 0
msg_oom_retry_test_passed:                db "VMM Allocation Retry with Reclaim Test PASSED!", 0x0D, 0x0A, 0
msg_oom_retry_fail_register_str:          db "Failure: Could not register Thread V for allocation retry test.", 0x0D, 0x0A, 0
msg_oom_retry_fail_alloc_str:             db "Failure: VMA allocation failed despite mock reclaim resolving pressure.", 0x0D, 0x0A, 0
msg_oom_retry_fail_killed_str:            db "Failure: Candidate Thread V was prematurely killed during retry sweeps.", 0x0D, 0x0A, 0

; PSI Test messages
msg_oom_psi_test_start:                 db "Running VMM Pressure Stall Information (PSI) Test...", 0x0D, 0x0A, 0
msg_oom_psi_test_passed:                db "VMM Pressure Stall Information (PSI) Test PASSED!", 0x0D, 0x0A, 0
msg_oom_psi_fail_init_str:              db "Failure: Could not retrieve current thread for PSI test.", 0x0D, 0x0A, 0
msg_oom_psi_fail_sys_some_str:          db "Failure: System-wide PSI some_total did not increase.", 0x0D, 0x0A, 0
msg_oom_psi_fail_sys_full_str:          db "Failure: System-wide PSI full_total did not increase.", 0x0D, 0x0A, 0
msg_oom_psi_fail_cgroup_create_str:     db "Failure: Could not create memory cgroup for PSI test.", 0x0D, 0x0A, 0
msg_oom_psi_fail_register_str:          db "Failure: Could not register threads for PSI test.", 0x0D, 0x0A, 0
msg_oom_psi_fail_cg_some_zero_str:      db "Failure: Cgroup PSI some_total was zero under memory pressure.", 0x0D, 0x0A, 0
msg_oom_psi_fail_cg_full_nonzero_str:   db "Failure: Cgroup PSI full_total was non-zero when only some threads stalled.", 0x0D, 0x0A, 0
msg_oom_psi_fail_cg_some_noinc_str:     db "Failure: Cgroup PSI some_total did not increase when all threads stalled.", 0x0D, 0x0A, 0
msg_oom_psi_fail_cg_full_zero_str:      db "Failure: Cgroup PSI full_total was zero when all threads stalled.", 0x0D, 0x0A, 0

; Watermark Test messages
msg_watermark_test_start:            db "Running VMM Memory Watermarks Test...", 0x0D, 0x0A, 0
msg_watermark_test_passed:           db "VMM Memory Watermarks Test PASSED!", 0x0D, 0x0A, 0
msg_watermark_fail_config_str:       db "Failure: Could not configure NUMA Node 0 watermarks.", 0x0D, 0x0A, 0
msg_watermark_fail_val_str:          db "Failure: Watermark thresholds not updated correctly in numa_node_t.", 0x0D, 0x0A, 0
msg_watermark_fail_alloc_setup_str:  db "Failure: Could not allocate setup page frame.", 0x0D, 0x0A, 0
msg_watermark_fail_map_setup_str:    db "Failure: Could not map test VMA.", 0x0D, 0x0A, 0
msg_watermark_fail_walk_setup_str:   db "Failure: Walk table failed for test VMA address.", 0x0D, 0x0A, 0
msg_watermark_fail_kswapd_alloc_str: db "Failure: Allocation from Node 0 failed under kswapd pressure.", 0x0D, 0x0A, 0
msg_watermark_fail_pte_str:          db "Failure: PTE missing for test address after reclaim.", 0x0D, 0x0A, 0
msg_watermark_fail_present_str:      db "Failure: Candidate page not evicted (PTE is still marked present).", 0x0D, 0x0A, 0
msg_watermark_fail_swapped_str:      db "Failure: Candidate page not swapped (PAGE_SWAPPED bit is 0).", 0x0D, 0x0A, 0
msg_watermark_fail_direct_alloc_str: db "Failure: Allocation from Node 0 failed under direct reclaim pressure.", 0x0D, 0x0A, 0
msg_watermark_fail_reject_str:       db "Failure: Allocation succeeded when free pages dropped below pages_min and reclaim failed.", 0x0D, 0x0A, 0
 
; Proactive Reclaim Test messages
msg_proactive_reclaim_test_start:            db "Running VMM Proactive Reclaim Test...", 0x0D, 0x0A, 0
msg_proactive_reclaim_test_passed:           db "VMM Proactive Reclaim Test PASSED!", 0x0D, 0x0A, 0
msg_proactive_fail_config_str:       db "Failure: Could not configure NUMA Node 0 watermarks/headroom for proactive reclaim.", 0x0D, 0x0A, 0
msg_proactive_fail_alloc_setup_str:  db "Failure: Could not allocate setup page frame for proactive reclaim.", 0x0D, 0x0A, 0
msg_proactive_fail_map_setup_str:    db "Failure: Could not map test VMA for proactive reclaim.", 0x0D, 0x0A, 0
msg_proactive_fail_walk_setup_str:   db "Failure: Walk table failed for test VMA address under proactive reclaim.", 0x0D, 0x0A, 0
msg_proactive_fail_direct_reclaim_str: db "Failure: virt_proactive_reclaim returned unexpected page count.", 0x0D, 0x0A, 0
msg_proactive_fail_direct_reclaim_node_str: db "Failure: virt_proactive_reclaim_node returned unexpected page count.", 0x0D, 0x0A, 0
msg_proactive_fail_kswapd_alloc_str: db "Failure: Allocation failed under proactive reclaim test.", 0x0D, 0x0A, 0
msg_proactive_fail_pte_str:          db "Failure: PTE missing for test address after proactive reclaim.", 0x0D, 0x0A, 0
msg_proactive_fail_present_str:      db "Failure: Proactive reclaim candidate page not evicted (PTE is still marked present).", 0x0D, 0x0A, 0
msg_proactive_fail_swapped_str:      db "Failure: Proactive reclaim candidate page not swapped (PAGE_SWAPPED bit is 0).", 0x0D, 0x0A, 0

; Memory Balloon Driver Test messages
msg_balloon_test_start:             db "Running VMM Memory Balloon Driver Test...", 0x0D, 0x0A, 0
msg_balloon_test_passed:            db "VMM Memory Balloon Driver Test PASSED!", 0x0D, 0x0A, 0
msg_balloon_fail_init_str:          db "Failure: Balloon initial size/target is not zero.", 0x0D, 0x0A, 0
msg_balloon_fail_inflate_str:       db "Failure: Balloon inflation target or current size mismatch.", 0x0D, 0x0A, 0
msg_balloon_fail_deflate_str:       db "Failure: Balloon deflation target or current size mismatch.", 0x0D, 0x0A, 0
msg_balloon_fail_deflate_all_str:   db "Failure: Balloon complete deflation target or current size mismatch.", 0x0D, 0x0A, 0

; cgroup memory.high Throttling Test messages
msg_throttling_test_start:             db "Running VMM cgroup memory.high Throttling Test...", 0x0D, 0x0A, 0
msg_throttling_test_passed:            db "VMM cgroup memory.high Throttling Test PASSED!", 0x0D, 0x0A, 0
msg_throttling_fail_create_str:        db "Failure: Could not create memory cgroup for throttling test.", 0x0D, 0x0A, 0
msg_throttling_fail_thread_str:        db "Failure: Could not retrieve current thread pointer.", 0x0D, 0x0A, 0
msg_throttling_fail_vma1_str:          db "Failure: Could not allocate non-throttled VMA 1.", 0x0D, 0x0A, 0
msg_throttling_fail_vma2_str:          db "Failure: Could not allocate throttled VMA 2.", 0x0D, 0x0A, 0

; Unified Page Cache Test messages
msg_page_cache_test_start:             db "Running VMM Unified Page Cache Test...", 0x0D, 0x0A, 0
msg_page_cache_test_passed:            db "VMM Unified Page Cache Test PASSED!", 0x0D, 0x0A, 0
msg_page_cache_fail_read_str:          db "Failure: virt_file_read did not return expected byte count.", 0x0D, 0x0A, 0
msg_page_cache_fail_counters1_str:     db "Failure: Page cache hit/miss counters incorrect after first read.", 0x0D, 0x0A, 0
msg_page_cache_fail_counters2_str:     db "Failure: Page cache hit/miss counters incorrect after second read.", 0x0D, 0x0A, 0
msg_page_cache_fail_write_str:         db "Failure: virt_file_write did not return expected byte count.", 0x0D, 0x0A, 0
msg_page_cache_fail_counters3_str:     db "Failure: Page cache hit/miss counters incorrect after write.", 0x0D, 0x0A, 0
msg_page_cache_fail_sync_str:          db "Failure: Block page not allocated on sync target.", 0x0D, 0x0A, 0
msg_page_cache_fail_sync_data_str:     db "Failure: Written data did not match content in storage after sync.", 0x0D, 0x0A, 0

; Readahead Engine Test messages
msg_readahead_test_start:             db "Running VMM Readahead Engine Test...", 0x0D, 0x0A, 0
msg_readahead_test_passed:            db "VMM Readahead Engine Test PASSED!", 0x0D, 0x0A, 0
msg_readahead_fail_create_str:        db "Failure: Could not create mock file for readahead test.", 0x0D, 0x0A, 0
msg_readahead_fail_read_str:          db "Failure: virt_file_read returned unexpected bytes.", 0x0D, 0x0A, 0
msg_readahead_fail_prefetched_str:    db "Failure: sys_readahead_prefetched_pages mismatch.", 0x0D, 0x0A, 0
msg_readahead_fail_hits_str:          db "Failure: sys_page_cache_hits mismatch.", 0x0D, 0x0A, 0
msg_readahead_fail_misses_str:        db "Failure: sys_page_cache_misses mismatch.", 0x0D, 0x0A, 0

; Writeback Throttling Test messages
msg_writeback_test_start:             db "Running VMM Writeback Throttling Test...", 0x0D, 0x0A, 0
msg_writeback_test_passed:            db "VMM Writeback Throttling Test PASSED!", 0x0D, 0x0A, 0
msg_writeback_fail_create_str:        db "Failure: Could not create mock file for writeback test.", 0x0D, 0x0A, 0
msg_writeback_fail_write_str:         db "Failure: virt_file_write failed during writeback test.", 0x0D, 0x0A, 0
msg_writeback_fail_throttled_init_str: db "Failure: sys_writeback_throttled_pages is not zero initially.", 0x0D, 0x0A, 0
msg_writeback_fail_throttled_post_str: db "Failure: sys_writeback_throttled_pages mismatch after sync.", 0x0D, 0x0A, 0

; Page Cache Bypass (O_DIRECT) Test messages
msg_direct_test_start:             db "Running VMM Page Cache Bypass (O_DIRECT) Test...", 0x0D, 0x0A, 0
msg_direct_test_passed:            db "VMM Page Cache Bypass (O_DIRECT) Test PASSED!", 0x0D, 0x0A, 0
msg_direct_fail_create_str:        db "Failure: Could not create mock file for direct test.", 0x0D, 0x0A, 0
msg_direct_fail_vma_str:           db "Failure: Could not create VMA for direct test.", 0x0D, 0x0A, 0
msg_direct_fail_alloc_str:         db "Failure: Could not allocate physical page for direct test.", 0x0D, 0x0A, 0
msg_direct_fail_map_str:           db "Failure: Could not map page for direct test.", 0x0D, 0x0A, 0
msg_direct_fail_read_str:          db "Failure: virt_file_read failed in direct test.", 0x0D, 0x0A, 0
msg_direct_fail_bypass_str:        db "Failure: Cache was not bypassed in direct test (hit/miss counter changed).", 0x0D, 0x0A, 0
msg_direct_fail_populate_str:      db "Failure: Cache was populated during direct read (subsequent cached read did not miss).", 0x0D, 0x0A, 0

; Multi-Gen LRU (MGLRU) Test messages
msg_mglru_test_start:             db "Running VMM Multi-Gen LRU (MGLRU) Test...", 0x0D, 0x0A, 0
msg_mglru_test_passed:            db "VMM Multi-Gen LRU (MGLRU) Test PASSED!", 0x0D, 0x0A, 0
msg_mglru_fail_vma_str:           db "Failure: Could not create VMA for MGLRU test.", 0x0D, 0x0A, 0
msg_mglru_fail_alloc_str:         db "Failure: Could not allocate physical page for MGLRU test.", 0x0D, 0x0A, 0
msg_mglru_fail_map_str:           db "Failure: Could not map page for MGLRU test.", 0x0D, 0x0A, 0
msg_mglru_fail_init_count_str:    db "Failure: Generation counts not correct after initial mapping.", 0x0D, 0x0A, 0
msg_mglru_fail_age_count_str:     db "Failure: Generation counts not correct after aging pages.", 0x0D, 0x0A, 0
msg_mglru_fail_evict_str:         db "Failure: page_replace_clock_evict returned 0 under MGLRU.", 0x0D, 0x0A, 0
msg_mglru_fail_telemetry_str:     db "Failure: MGLRU reclaim or promotion counter incorrect.", 0x0D, 0x0A, 0
msg_mglru_fail_pte_str:           db "Failure: PTE not found after eviction.", 0x0D, 0x0A, 0
msg_mglru_fail_present_evicted_str: db "Failure: Evicted page present bit is not zero.", 0x0D, 0x0A, 0
msg_mglru_fail_not_swapped_str:   db "Failure: Evicted page swapped bit is not set.", 0x0D, 0x0A, 0
msg_mglru_fail_not_present_promoted_str: db "Failure: Promoted page present bit is zero.", 0x0D, 0x0A, 0
msg_mglru_fail_final_count_str:   db "Failure: MGLRU counts not correct after eviction & promotion.", 0x0D, 0x0A, 0

; Folio Support Test messages
msg_folio_test_start:             db "Running VMM Folio Support Test...", 0x0D, 0x0A, 0
msg_folio_test_passed:            db "VMM Folio Support Test PASSED!", 0x0D, 0x0A, 0
msg_folio_fail_create_str:        db "Failure: Could not create mock file for folio test.", 0x0D, 0x0A, 0
msg_folio_fail_read_str:          db "Failure: virt_file_read failed in folio test.", 0x0D, 0x0A, 0
msg_folio_fail_misses_init_str:   db "Failure: sys_page_cache_misses is not 1 after initial folio load.", 0x0D, 0x0A, 0
msg_folio_fail_count_init_str:    db "Failure: sys_page_cache_count is not 1 after initial folio load.", 0x0D, 0x0A, 0
msg_folio_fail_hits_str:           db "Failure: sys_page_cache_hits mismatch in folio test.", 0x0D, 0x0A, 0
msg_folio_fail_write_str:          db "Failure: virt_file_write failed in folio test.", 0x0D, 0x0A, 0

; Kernel Memory Accounting Test messages
msg_kmem_acc_test_start:             db "Running VMM Kernel Memory Accounting Test...", 0x0D, 0x0A, 0
msg_kmem_acc_test_passed:            db "VMM Kernel Memory Accounting Test PASSED!", 0x0D, 0x0A, 0
msg_kmem_acc_fail_create_cg_str:      db "Failure: Could not create mock cgroup for kmem test.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_alloc_heap_str:     db "Failure: Could not allocate heap block for kmem test.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_usage_val_str:      db "Failure: Cgroup kmem_usage was not charged correctly on heap alloc.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_pages_val_str:      db "Failure: Cgroup pages usage was not charged correctly on heap alloc.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_map_str:            db "Failure: Could not map page for kmem test.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_pgtable_charge_str: db "Failure: Cgroup was not charged for intermediate page tables.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_uncharge_val_str:   db "Failure: Cgroup kmem_usage not uncharged correctly on heap free.", 0x0D, 0x0A, 0
msg_kmem_acc_fail_uncharge_pages_str: db "Failure: Cgroup pages usage not uncharged correctly on heap free.", 0x0D, 0x0A, 0

; Per-CPU Memory Counters Test messages (Subfeature 34.2)
msg_percpu_stat_test_start:         db "Running VMM Per-CPU Memory Counters Test...", 0x0D, 0x0A, 0
msg_percpu_stat_test_passed:        db "VMM Per-CPU Memory Counters Test PASSED!", 0x0D, 0x0A, 0
msg_percpu_fail_init_str:           db "Failure: Global counter non-zero after percpu_stat_init.", 0x0D, 0x0A, 0
msg_percpu_fail_delta_stat_str:     db "Failure: Per-CPU vm_stat delta incorrect before sync.", 0x0D, 0x0A, 0
msg_percpu_fail_delta_anon_str:     db "Failure: Per-CPU vm_stat anon delta not zero after inc+dec.", 0x0D, 0x0A, 0
msg_percpu_fail_delta_event_str:    db "Failure: Per-CPU vm_event delta incorrect before sync.", 0x0D, 0x0A, 0
msg_percpu_fail_presync_str:        db "Failure: Global counter non-zero before percpu_sync was called.", 0x0D, 0x0A, 0
msg_percpu_fail_postsync_delta_str: db "Failure: Per-CPU delta not reset to zero after percpu_sync.", 0x0D, 0x0A, 0
msg_percpu_fail_global_stat_str:    db "Failure: Global vm_stat counter incorrect after percpu_sync.", 0x0D, 0x0A, 0
msg_percpu_fail_global_event_str:   db "Failure: Global vm_event counter incorrect after percpu_sync.", 0x0D, 0x0A, 0
msg_percpu_fail_sync_count_str:     db "Failure: sys_percpu_sync_count telemetry counter incorrect.", 0x0D, 0x0A, 0
msg_percpu_fail_idempotent_str:     db "Failure: Global vm_stat changed on second no-delta sync.", 0x0D, 0x0A, 0
msg_percpu_fail_multicpu_stat_str:  db "Failure: vm_stat global counter incorrect after multi-CPU simulation sync.", 0x0D, 0x0A, 0
msg_percpu_fail_multicpu_event_str: db "Failure: vm_event global counter incorrect after multi-CPU simulation sync.", 0x0D, 0x0A, 0

; Memory Map Statistics Test messages (Subfeature 34.3)
msg_meminfo_test_start:             db "Running VMM Memory Map Statistics Test (meminfo)...", 0x0D, 0x0A, 0
msg_meminfo_test_passed:            db "VMM Memory Map Statistics Test PASSED!", 0x0D, 0x0A, 0
msg_meminfo_fail_snap_count_str:    db "Failure: sys_meminfo_snap_count not 1 after first snapshot.", 0x0D, 0x0A, 0
msg_meminfo_fail_total_str:         db "Failure: MemTotal is zero after meminfo_snapshot.", 0x0D, 0x0A, 0
msg_meminfo_fail_free_str:          db "Failure: MemFree is zero after meminfo_snapshot.", 0x0D, 0x0A, 0
msg_meminfo_fail_free_exceeds_str:  db "Failure: MemFree exceeds MemTotal (impossible).", 0x0D, 0x0A, 0
msg_meminfo_fail_buffers_str:       db "Failure: Buffers field did not reflect sys_buf_pages increment.", 0x0D, 0x0A, 0
msg_meminfo_fail_shmem_str:         db "Failure: Shmem field did not reflect sys_shmem_pages increment.", 0x0D, 0x0A, 0
msg_meminfo_fail_ptr_str:           db "Failure: meminfo_get_snapshot_ptr returned null.", 0x0D, 0x0A, 0
msg_meminfo_fail_struct_str:        db "Failure: MemTotal in snapshot struct does not match get_field value.", 0x0D, 0x0A, 0

; Per-Process Memory Stats Test messages (Subfeature 34.4)
msg_proc_memstat_test_start:        db "Running VMM Per-Process Memory Stats Test (VSZ/RSS/PSS/USS)...", 0x0D, 0x0A, 0
msg_proc_memstat_test_passed:       db "VMM Per-Process Memory Stats Test PASSED!", 0x0D, 0x0A, 0
msg_proc_memstat_fail_alloc_str:    db "Failure: heap_alloc failed for proc_memstat_t output struct.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_page_str:     db "Failure: phys_alloc_page failed for proc_memstat test.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_vma_str:      db "Failure: vma_create failed for 0xB0000000 in proc_memstat test.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_map_str:      db "Failure: virt_map failed for 0xB0000000 in proc_memstat test.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_vsz_str:      db "Failure: VSZ is less than 4096 after mapping one page.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_rss_str:      db "Failure: RSS is less than 4096 after mapping one resident page.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_pss_str:      db "Failure: PSS does not equal RSS for a single unshared mapping.", 0x0D, 0x0A, 0
msg_proc_memstat_fail_uss_str:      db "Failure: USS does not equal RSS for a uniquely owned mapping.", 0x0D, 0x0A, 0

; Memory Bandwidth Monitoring Test messages (Subfeature 34.5)
msg_mbm_test_start:                 db "Running VMM Memory Bandwidth Monitoring (MBM/RDT) Test...", 0x0D, 0x0A, 0
msg_mbm_test_passed:                db "VMM Memory Bandwidth Monitoring Test PASSED!", 0x0D, 0x0A, 0
msg_mbm_hw_detected:                db "MBM: Intel RDT hardware detected.", 0x0D, 0x0A, 0
msg_mbm_hw_unsupported:             db "MBM: Intel RDT not available; running graceful-degradation path.", 0x0D, 0x0A, 0
msg_mbm_fail_init_str:              db "Failure: mbm_init returned 0 on hardware-supported system.", 0x0D, 0x0A, 0
msg_mbm_fail_scale_str:             db "Failure: sys_mbm_scale is zero after mbm_init.", 0x0D, 0x0A, 0
msg_mbm_fail_assign_str:            db "Failure: mbm_assign_rmid returned 0 (no free RMID).", 0x0D, 0x0A, 0
msg_mbm_fail_rmid_count_str:        db "Failure: sys_mbm_active_rmids is not 1 after first assignment.", 0x0D, 0x0A, 0
msg_mbm_fail_total_bw_str:          db "Failure: mbm_read_bw total returned less than injected raw value.", 0x0D, 0x0A, 0
msg_mbm_fail_local_bw_str:          db "Failure: mbm_read_bw local returned less than injected raw value.", 0x0D, 0x0A, 0
msg_mbm_fail_local_exceeds_str:     db "Failure: Local memory bandwidth exceeds total bandwidth (impossible).", 0x0D, 0x0A, 0
msg_mbm_fail_snapshot_str:          db "Failure: mbm_bw_snapshot does not match mbm_read_bw result.", 0x0D, 0x0A, 0
msg_mbm_fail_saturated_low_str:     db "Failure: mbm_is_saturated returned 0 for threshold=0 MB (always saturated).", 0x0D, 0x0A, 0
msg_mbm_fail_saturated_high_str:    db "Failure: mbm_is_saturated returned 1 for 1TB threshold (should never saturate).", 0x0D, 0x0A, 0
msg_mbm_fail_flag_str:              db "Failure: sys_mbm_supported is non-zero after detect reported unsupported.", 0x0D, 0x0A, 0
msg_mbm_fail_init_notsup_str:       db "Failure: mbm_init returned non-zero on unsupported hardware.", 0x0D, 0x0A, 0
msg_mbm_fail_bw_notsup_str:         db "Failure: mbm_read_bw returned non-zero when MBM is not supported.", 0x0D, 0x0A, 0

; AMD SEV Test messages (Subfeature 35.1)
msg_sev_test_start:                 db "Running VMM AMD SEV (Secure Encrypted Virtualization) Test...", 0x0D, 0x0A, 0
msg_sev_test_passed:                db "VMM AMD SEV Test PASSED!", 0x0D, 0x0A, 0
msg_sev_capable:                    db "SEV: AMD SEV capable CPU detected.", 0x0D, 0x0A, 0
msg_sev_not_capable:                db "SEV: AMD SEV not available; running simulation path.", 0x0D, 0x0A, 0
msg_sev_fail_flag_str:              db "Failure: sys_sev_supported does not match sev_detect() return value.", 0x0D, 0x0A, 0
msg_sev_fail_init_count_str:        db "Failure: sys_sev_init_count is not 1 after sev_init().", 0x0D, 0x0A, 0
msg_sev_fail_encrypt_str:           db "Failure: sev_encrypt_gpa did not return 1 for valid GPA.", 0x0D, 0x0A, 0
msg_sev_fail_count_str:             db "Failure: sys_sev_encrypted_pages counter does not match expected value.", 0x0D, 0x0A, 0
msg_sev_fail_is_encrypted_str:      db "Failure: sev_is_encrypted returned 0 for a page that was encrypted.", 0x0D, 0x0A, 0
msg_sev_fail_is_not_encrypted_str:  db "Failure: sev_is_encrypted returned 1 for a page that was never encrypted.", 0x0D, 0x0A, 0
msg_sev_fail_decrypt_str:           db "Failure: sev_decrypt_gpa did not return 1 for valid GPA.", 0x0D, 0x0A, 0
msg_sev_fail_decrypt_verify_str:    db "Failure: sev_is_encrypted returned 1 after sev_decrypt_gpa (still encrypted).", 0x0D, 0x0A, 0
msg_sev_fail_validate_str:          db "Failure: sev_validate_page did not set encryption bit for GPA.", 0x0D, 0x0A, 0

; Intel TDX Test messages (Subfeature 35.2)
msg_tdx_test_start:                 db "Running VMM Intel TDX (Trust Domain Extensions) Test...", 0x0D, 0x0A, 0
msg_tdx_test_passed:                db "VMM Intel TDX Test PASSED!", 0x0D, 0x0A, 0
msg_tdx_capable:                    db "TDX: Intel TDX capable platform detected.", 0x0D, 0x0A, 0
msg_tdx_not_capable:                db "TDX: Intel TDX not available; running simulation path.", 0x0D, 0x0A, 0
msg_tdx_fail_flag_str:              db "Failure: sys_tdx_supported does not match tdx_detect() return value.", 0x0D, 0x0A, 0
msg_tdx_fail_init_count_str:        db "Failure: sys_tdx_init_count is not 1 after tdx_init().", 0x0D, 0x0A, 0
msg_tdx_fail_share_str:             db "Failure: tdx_share_gpa did not return 1 for valid GPA.", 0x0D, 0x0A, 0
msg_tdx_fail_count_str:             db "Failure: sys_tdx_shared_pages counter does not match expected value.", 0x0D, 0x0A, 0
msg_tdx_fail_is_shared_str:         db "Failure: tdx_is_shared returned 0 for a GPA that was shared.", 0x0D, 0x0A, 0
msg_tdx_fail_is_not_shared_str:     db "Failure: tdx_is_shared returned 1 for a GPA that was never shared.", 0x0D, 0x0A, 0
msg_tdx_fail_private_str:           db "Failure: tdx_private_gpa did not return 1 for valid GPA.", 0x0D, 0x0A, 0
msg_tdx_fail_private_verify_str:    db "Failure: tdx_is_shared returned 1 after tdx_private_gpa (still shared).", 0x0D, 0x0A, 0
msg_tdx_fail_accept_str:            db "Failure: tdx_accept_page returned non-zero (accept failed).", 0x0D, 0x0A, 0
msg_tdx_fail_accept_verify_str:     db "Failure: tdx_is_shared returned 1 for an accepted (private) page.", 0x0D, 0x0A, 0
msg_tdx_fail_report_str:            db "Failure: tdx_report returned non-zero for a valid 1024-byte buffer.", 0x0D, 0x0A, 0
msg_tdx_fail_report_marker_str:     db "Failure: tdx_report marker at offset 0 does not match expected signature.", 0x0D, 0x0A, 0
msg_tdx_fail_report_null_str:       db "Failure: tdx_report returned 0 for a null buffer (should be error).", 0x0D, 0x0A, 0

; ARM CCA Test messages (Subfeature 35.3)
msg_cca_test_start:                 db "Running VMM ARM CCA (Confidential Compute Architecture) Test...", 0x0D, 0x0A, 0
msg_cca_test_passed:                db "VMM ARM CCA Test PASSED!", 0x0D, 0x0A, 0
msg_cca_not_capable:                db "CCA: ARM CCA not available; running simulation path.", 0x0D, 0x0A, 0
msg_cca_fail_flag:                  db "Failure: sys_cca_supported does not match expected state.", 0x0D, 0x0A, 0
msg_cca_fail_init:                  db "Failure: cca_init returned 0 (init failed).", 0x0D, 0x0A, 0
msg_cca_fail_init_count:            db "Failure: sys_cca_init_count is not 1 after cca_init().", 0x0D, 0x0A, 0
msg_cca_fail_count:                 db "Failure: CCA counts (realm/page) do not match expected value.", 0x0D, 0x0A, 0
msg_cca_fail_create:                db "Failure: cca_realm_create returned 0.", 0x0D, 0x0A, 0
msg_cca_fail_map:                   db "Failure: cca_map_gpa returned 0.", 0x0D, 0x0A, 0
msg_cca_fail_unmap:                 db "Failure: cca_unmap_gpa returned 0.", 0x0D, 0x0A, 0
msg_cca_fail_destroy:               db "Failure: cca_realm_destroy returned 0.", 0x0D, 0x0A, 0
msg_cca_fail_is_realm_page:         db "Failure: cca_is_realm_page returned incorrect value for mapped page.", 0x0D, 0x0A, 0
msg_cca_fail_is_not_realm_page:     db "Failure: cca_is_realm_page returned non-zero for unmapped page.", 0x0D, 0x0A, 0
msg_cca_fail_smc_version:           db "Failure: SMC Version call returned incorrect version.", 0x0D, 0x0A, 0
msg_cca_fail_smc_map:               db "Failure: SMC Map call returned error code.", 0x0D, 0x0A, 0

; Encrypted Swapping Test messages (Subfeature 35.4)
msg_enc_swap_test_start:            db "Running VMM Encrypted Swap Test...", 0x0D, 0x0A, 0
msg_enc_swap_test_passed:           db "VMM Encrypted Swap Test PASSED!", 0x0D, 0x0A, 0
msg_enc_swap_fail_init:             db "Failure: enc_swap_init returned 0 (init failed).", 0x0D, 0x0A, 0
msg_enc_swap_fail_enabled:          db "Failure: sys_enc_swap_enabled is not 1 after init.", 0x0D, 0x0A, 0
msg_enc_swap_fail_counters:         db "Failure: Encrypted swap stats/counters do not match expected.", 0x0D, 0x0A, 0
msg_enc_swap_fail_encrypt:          db "Failure: enc_swap_encrypt_page returned 0.", 0x0D, 0x0A, 0
msg_enc_swap_fail_decrypt:          db "Failure: enc_swap_decrypt_page returned 0.", 0x0D, 0x0A, 0
msg_enc_swap_fail_verify_encryption:db "Failure: Encrypted destination page matches source (no encryption occurred).", 0x0D, 0x0A, 0
msg_enc_swap_fail_verify_decryption:db "Failure: Decrypted destination page does not match original plaintext.", 0x0D, 0x0A, 0

; Memory Tagging Test messages (Subfeature 35.5)
msg_mte_test_start:                 db "Running VMM Memory Tagging Extension (MTE) Test...", 0x0D, 0x0A, 0
msg_mte_test_passed:                db "VMM MTE Test PASSED!", 0x0D, 0x0A, 0
msg_mte_fail_detect:                db "Failure: sys_mte_supported does not match expected state.", 0x0D, 0x0A, 0
msg_mte_fail_init:                  db "Failure: mte_init returned 0 (init failed).", 0x0D, 0x0A, 0
msg_mte_fail_active:                db "Failure: sys_mte_active is not 1 after init.", 0x0D, 0x0A, 0
msg_mte_fail_fault_count:           db "Failure: MTE fault counter does not match expected value.", 0x0D, 0x0A, 0
msg_mte_fail_set_tag:               db "Failure: mte_set_granule_tag returned 0.", 0x0D, 0x0A, 0
msg_mte_fail_get_tag:               db "Failure: mte_get_granule_tag returned incorrect tag.", 0x0D, 0x0A, 0
msg_mte_fail_adjacent_tag:          db "Failure: adjacent granule tag was unexpectedly modified.", 0x0D, 0x0A, 0
msg_mte_fail_validation:            db "Failure: mte_validate_ptr returned invalid for matching tag.", 0x0D, 0x0A, 0
msg_mte_fail_validation_mismatch:   db "Failure: mte_validate_ptr returned valid for mismatched tag.", 0x0D, 0x0A, 0
msg_mte_fail_tag_page:              db "Failure: mte_tag_page returned 0.", 0x0D, 0x0A, 0
msg_mte_fail_page_tag_verify:       db "Failure: page granule verification failed after page tag.", 0x0D, 0x0A, 0
msg_mte_fail_tagged_pages_count:    db "Failure: sys_mte_tagged_pages counter does not match expected value.", 0x0D, 0x0A, 0
msg_mte_fail_tag_free_page:         db "Failure: mte_tag_free_page returned 0.", 0x0D, 0x0A, 0
msg_mte_fail_free_tag_verify:       db "Failure: granule verification failed after tagging free page.", 0x0D, 0x0A, 0
; AI/Inference Specific Memory Test messages (Subfeature 36)
msg_ai_mem_test_start:              db "Running VMM AI/Inference Specific Memory Features Test...", 0x0D, 0x0A, 0
msg_ai_mem_test_passed:             db "VMM AI/Inference Specific Memory Features Test PASSED!", 0x0D, 0x0A, 0
msg_ai_tensor_pool_ok:              db "  Tensor Memory Pool: Alloc and O(1) dealloc verified.", 0x0D, 0x0A, 0
msg_ai_weight_cache_ok:             db "  Weight Cache: Pinning, LRU eviction and access tracking verified.", 0x0D, 0x0A, 0
msg_ai_kv_alloc_ok:                 db "  KV Cache: Contiguous page allocator and TurboQuant 3.5-bit packing verified.", 0x0D, 0x0A, 0
msg_ai_act_recycler_ok:             db "  Activation Recycler: Page-table physical page sharing verified.", 0x0D, 0x0A, 0
msg_ai_prefetch_ok:                 db "  Prefetch-Aware Allocator: 64-byte alignment and hardware prefetch hints verified.", 0x0D, 0x0A, 0
msg_ai_quant_ok:                    db "  Quantized Layout: INT4 AVX2 32-byte alignment packing/unpacking verified.", 0x0D, 0x0A, 0

msg_ai_fail_tensor_init:            db "Failure: tensor_pool_init returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_tensor_count:           db "Failure: sys_tensor_pool_total_blocks is 0 after init.", 0x0D, 0x0A, 0
msg_ai_fail_tensor_alloc:           db "Failure: tensor_pool_alloc returned NULL.", 0x0D, 0x0A, 0
msg_ai_fail_tensor_allocated_count: db "Failure: sys_tensor_pool_allocated_blocks counter mismatch.", 0x0D, 0x0A, 0
msg_ai_fail_tensor_distinct:        db "Failure: consecutive tensor_pool_alloc returned identical pointer.", 0x0D, 0x0A, 0
msg_ai_fail_tensor_free:            db "Failure: tensor_pool_free returned 0.", 0x0D, 0x0A, 0

msg_ai_fail_weight_init:            db "Failure: weight_cache_init returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_weight_config:          db "Failure: sys_weight_cache_max_bytes is incorrect.", 0x0D, 0x0A, 0
msg_ai_fail_weight_pin:             db "Failure: weight_cache_pin returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_weight_stats:           db "Failure: weight cache telemetry count/bytes mismatch.", 0x0D, 0x0A, 0
msg_ai_fail_weight_unpin:           db "Failure: weight_cache_unpin returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_weight_evicted:         db "Failure: unpinned LRU model weights were not evicted under pressure.", 0x0D, 0x0A, 0
msg_ai_fail_weight_access:          db "Failure: weight_cache_access failed for resident model.", 0x0D, 0x0A, 0

msg_ai_fail_kv_init:                db "Failure: kv_cache_init returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_kv_alloc:               db "Failure: kv_cache_alloc_block returned NULL.", 0x0D, 0x0A, 0
msg_ai_fail_kv_stats:               db "Failure: KV cache page stats/counters mismatch.", 0x0D, 0x0A, 0
msg_ai_fail_kv_free:                db "Failure: kv_cache_free_block returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_turboquant_pack:        db "Failure: kv_cache_pack_turboquant returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_turboquant_unpack:      db "Failure: kv_cache_unpack_turboquant returned incorrect element count.", 0x0D, 0x0A, 0
msg_ai_fail_turboquant_mismatch:    db "Failure: unpacked TurboQuant data does not match original bytes.", 0x0D, 0x0A, 0

msg_ai_fail_act_init:               db "Failure: activation_recycler_init returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_act_register:           db "Failure: activation_recycler_register returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_act_stats:              db "Failure: activation recycler counts mismatch.", 0x0D, 0x0A, 0
msg_ai_fail_act_map:                db "Failure: activation_recycler_map returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_act_translate:          db "Failure: virt_translate returned 0 for activation virtual address.", 0x0D, 0x0A, 0
msg_ai_fail_act_distinct:           db "Failure: layers mapped to different physical frames (recycler fail).", 0x0D, 0x0A, 0
msg_ai_fail_act_unmap:              db "Failure: activation_recycler_unmap returned 0.", 0x0D, 0x0A, 0

msg_ai_fail_prefetch_alloc:         db "Failure: prefetch_alloc_aligned returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_prefetch_stats:         db "Failure: sys_prefetch_aligned_allocations count mismatch.", 0x0D, 0x0A, 0
msg_ai_fail_prefetch_align:         db "Failure: prefetch allocator returned address that is not 64-byte aligned.", 0x0D, 0x0A, 0
msg_ai_fail_prefetch_hint:          db "Failure: prefetch_alloc_hint returned 0.", 0x0D, 0x0A, 0

msg_ai_fail_quant_pack:             db "Failure: quant_layout_pack_int4 returned 0.", 0x0D, 0x0A, 0
msg_ai_fail_quant_stats:            db "Failure: quantized layout telemetry counts mismatch.", 0x0D, 0x0A, 0
msg_ai_fail_quant_unpack:           db "Failure: quant_layout_unpack_int4 returned incorrect count.", 0x0D, 0x0A, 0
msg_ai_fail_quant_mismatch:         db "Failure: unpacked INT4 data does not match original bytes.", 0x0D, 0x0A, 0
; Real-Time Memory Test messages (Subfeature 37)
msg_rt_mem_test_start:              db "Running VMM Real-Time Memory Management Test...", 0x0D, 0x0A, 0
msg_rt_mem_test_passed:             db "VMM Real-Time Memory Management Test PASSED!", 0x0D, 0x0A, 0
msg_rt_mlock_ok:                    db "  mlockall & Pre-fault: locking and warm up allocations verified.", 0x0D, 0x0A, 0
msg_rt_det_alloc_ok:                db "  Deterministic Alloc: O(1) TLSF-like constant-time segregated allocations verified.", 0x0D, 0x0A, 0
msg_rt_isr_alloc_ok:                db "  Interrupt-Safe Alloc: lock-free CAS popped/pushed pages verified.", 0x0D, 0x0A, 0
msg_rt_reserve_ok:                  db "  Memory Reservation: boot-time reserve pool allocations verified.", 0x0D, 0x0A, 0

msg_rt_fail_vma:                    db "Failure: Could not create Real-Time test VMA.", 0x0D, 0x0A, 0
msg_rt_fail_prefault:               db "Failure: rt_prefault_vma returned 0.", 0x0D, 0x0A, 0
msg_rt_fail_prefault_count:         db "Failure: sys_rt_prefaulted_pages count mismatch.", 0x0D, 0x0A, 0
msg_rt_fail_prefault_map:           db "Failure: pre-faulted page not present in translation tables.", 0x0D, 0x0A, 0
msg_rt_fail_mlockall:               db "Failure: rt_mlockall returned 0.", 0x0D, 0x0A, 0
msg_rt_fail_mlock_active:           db "Failure: sys_rt_mlockall_active status mismatch.", 0x0D, 0x0A, 0
msg_rt_fail_locked_count:           db "Failure: sys_rt_locked_pages counter mismatch.", 0x0D, 0x0A, 0
msg_rt_fail_locked_verify:          db "Failure: rt_is_locked query returned incorrect result.", 0x0D, 0x0A, 0
msg_rt_fail_munlockall:             db "Failure: rt_munlockall returned 0.", 0x0D, 0x0A, 0

msg_rt_fail_det_init:               db "Failure: rt_det_alloc_init returned 0.", 0x0D, 0x0A, 0
msg_rt_fail_det_alloc:              db "Failure: rt_det_alloc returned NULL.", 0x0D, 0x0A, 0
msg_rt_fail_det_stats:              db "Failure: rt deterministic allocator stats mismatch.", 0x0D, 0x0A, 0
msg_rt_fail_det_free:               db "Failure: rt_det_free returned 0.", 0x0D, 0x0A, 0

msg_rt_fail_isr_init:               db "Failure: rt_isr_alloc_init returned 0.", 0x0D, 0x0A, 0
msg_rt_fail_isr_stats:              db "Failure: rt isr allocator ring pointers/telemetry mismatch.", 0x0D, 0x0A, 0
msg_rt_fail_isr_alloc:              db "Failure: rt_isr_alloc returned NULL.", 0x0D, 0x0A, 0
msg_rt_fail_isr_free:               db "Failure: rt_isr_free returned 0.", 0x0D, 0x0A, 0

msg_rt_fail_reserve_boot:           db "Failure: rt_reserve_boot_memory returned 0.", 0x0D, 0x0A, 0
msg_rt_fail_reserve_stats:          db "Failure: rt reservation telemetry stats mismatch.", 0x0D, 0x0A, 0
msg_rt_fail_reserve_alloc:          db "Failure: rt_reserve_alloc returned NULL.", 0x0D, 0x0A, 0
msg_rt_fail_reserve_free:           db "Failure: rt_reserve_free returned 0.", 0x0D, 0x0A, 0
; RAS Memory Test messages (Subfeature 38)
msg_ras_mem_test_start:             db "Running VMM Memory Error Handling (RAS) Test...", 0x0D, 0x0A, 0
msg_ras_mem_test_passed:            db "VMM Memory Error Handling (RAS) Test PASSED!", 0x0D, 0x0A, 0
msg_ras_ecc_ok:                     db "  ECC Detection: Correctable single-bit error logging verified.", 0x0D, 0x0A, 0
msg_ras_mce_poison_ok:              db "  MCE & Poison: MCE intercept, graceful user recovery & page poisoning verified.", 0x0D, 0x0A, 0
msg_ras_dimm_ok:                    db "  DIMM Health: ECC error counters & pre-emptive page migration verified.", 0x0D, 0x0A, 0
msg_ras_scrub_ok:                     db "  Memory Scrubbing: background scanner ticks & bit flip intercept verified.", 0x0D, 0x0A, 0

msg_ras_fail_ecc_init:              db "Failure: ras_ecc_init returned 0.", 0x0D, 0x0A, 0
msg_ras_fail_ecc_report:            db "Failure: ras_ecc_report returned 0.", 0x0D, 0x0A, 0
msg_ras_fail_ecc_counters:          db "Failure: sys_ras_ecc_single_bit_errors count mismatch.", 0x0D, 0x0A, 0
msg_ras_fail_mce_init:              db "Failure: ras_mce_init returned 0.", 0x0D, 0x0A, 0
msg_ras_fail_mce_recover:           db "Failure: ras_mce_handler failed to recover user space error.", 0x0D, 0x0A, 0
msg_ras_fail_mce_stats:             db "Failure: MCE telemetry statistics counters mismatch.", 0x0D, 0x0A, 0
msg_ras_fail_poison_verify:         db "Failure: Poison bitmap tracking verification mismatch.", 0x0D, 0x0A, 0
msg_ras_fail_mce_fatal:             db "Failure: ras_mce_handler recovered a kernel error instead of panicking.", 0x0D, 0x0A, 0
msg_ras_fail_dimm_log:              db "Failure: ras_ecc_report logging DIMM errors failed.", 0x0D, 0x0A, 0
msg_ras_fail_dimm_migrate:          db "Failure: DIMM failure prediction did not trigger page migration.", 0x0D, 0x0A, 0
msg_ras_fail_dimm_stats:            db "Failure: DIMM error rates were not reset after page migration.", 0x0D, 0x0A, 0
msg_ras_fail_scrub_init:            db "Failure: ras_scrub_init returned 0.", 0x0D, 0x0A, 0
msg_ras_fail_scrub_tick:            db "Failure: ras_scrub_tick returned incorrect page count.", 0x0D, 0x0A, 0
msg_ras_fail_scrub_stats:           db "Failure: sys_ras_scrubbed_pages telemetry counter mismatch.", 0x0D, 0x0A, 0
msg_ras_fail_scrub_flip:            db "Failure: background scrubber failed to intercept mock bit flip.", 0x0D, 0x0A, 0
; CXL Memory Test messages (Subfeature 39)
msg_cxl_mem_test_start:             db "Running VMM CXL (Compute Express Link) Memory Test...", 0x0D, 0x0A, 0
msg_cxl_mem_test_passed:            db "VMM CXL (Compute Express Link) Memory Test PASSED!", 0x0D, 0x0A, 0
msg_cxl_t1_ok:                      db "  CXL Type 1: Device coherence protocols and bandwidth verified.", 0x0D, 0x0A, 0
msg_cxl_t3_ok:                      db "  CXL Type 3: Memory capacity expansion range hot-plugging verified.", 0x0D, 0x0A, 0
msg_cxl_tier_ok:                    db "  CXL Tiering: Automatic promotion and demotion page sweeps verified.", 0x0D, 0x0A, 0
msg_cxl_pmem_ok:                    db "  CXL Persistent: Byte-addressable cache flushes and NVRAM sync verified.", 0x0D, 0x0A, 0
msg_cxl_fabric_ok:                  db "  CXL Fabric: orchestration allocations and shared pool releases verified.", 0x0D, 0x0A, 0

msg_cxl_fail_t1_init:               db "Failure: cxl_t1_init returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_t1_active:             db "Failure: sys_cxl_t1_active_devices count mismatch.", 0x0D, 0x0A, 0
msg_cxl_fail_t1_bandwidth:          db "Failure: cxl_t1_get_bandwidth returned incorrect value.", 0x0D, 0x0A, 0
msg_cxl_fail_t3_init:               db "Failure: cxl_t3_init returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_t3_hotplug:            db "Failure: cxl_t3_hotplug returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_t3_stats:              db "Failure: CXL Type 3 capacity metrics mismatch.", 0x0D, 0x0A, 0
msg_cxl_fail_tier_init:             db "Failure: cxl_tier_init returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_tier_demote:           db "Failure: cxl_tier_demote returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_tier_promote:          db "Failure: cxl_tier_promote returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_tier_stats:            db "Failure: CXL memory tiering telemetry counters mismatch.", 0x0D, 0x0A, 0
msg_cxl_fail_pmem_init:             db "Failure: cxl_pmem_init returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_pmem_flush:            db "Failure: cxl_pmem_flush returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_pmem_stats:            db "Failure: sys_cxl_pmem_flushed_bytes count mismatch.", 0x0D, 0x0A, 0
msg_cxl_fail_fabric_init:           db "Failure: cxl_fabric_init returned 0.", 0x0D, 0x0A, 0
msg_cxl_fail_fabric_alloc:          db "Failure: cxl_fabric_allocate returned NULL.", 0x0D, 0x0A, 0
msg_cxl_fail_fabric_stats:          db "Failure: CXL Fabric telemetry stats count mismatch.", 0x0D, 0x0A, 0
msg_cxl_fail_fabric_release:        db "Failure: cxl_fabric_release returned 0.", 0x0D, 0x0A, 0
; Memory Profiling & Telemetry Test messages (Subfeature 40)
msg_prof_test_start:                db "Running VMM Memory Profiling & Telemetry Test...", 0x0D, 0x0A, 0
msg_prof_test_passed:               db "VMM Memory Profiling & Telemetry Test PASSED!", 0x0D, 0x0A, 0
msg_prof_hw_ok:                     db "  Perf Counters: LLC misses, bus bandwidth and latencies verified.", 0x0D, 0x0A, 0
msg_prof_site_ok:                   db "  Alloc Sites: Call site instruction pointers and byte counts verified.", 0x0D, 0x0A, 0
msg_prof_time_ok:                   db "  Timeline: Alloc/free flight recorders and TSC logs verified.", 0x0D, 0x0A, 0
msg_prof_numa_ok:                   db "  NUMA Stats: Node-local hits and node-remote misses verified.", 0x0D, 0x0A, 0
msg_prof_sat_ok:                    db "  Saturation Det: Bandwidth thresholds and saturation alerts verified.", 0x0D, 0x0A, 0
msg_prof_inf_ok:                    db "  Inference Prof: Layer parameter, activation and KV cache verified.", 0x0D, 0x0A, 0
msg_prof_fail_hw_init:              db "Failure: hw_perf_init returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_hw_sample:            db "Failure: hw_perf_sample returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_hw_stats:             db "Failure: LLC miss, bandwidth or latency stats mismatch.", 0x0D, 0x0A, 0
msg_prof_fail_site_init:            db "Failure: alloc_site_init returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_site_record:          db "Failure: alloc_site_record returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_site_stats:           db "Failure: Call site stats count or byte metrics mismatch.", 0x0D, 0x0A, 0
msg_prof_fail_time_init:            db "Failure: timeline_init returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_time_log:             db "Failure: timeline_log returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_time_stats:           db "Failure: Timeline recorder event counts mismatch.", 0x0D, 0x0A, 0
msg_prof_fail_numa_init:            db "Failure: numa_stat_init returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_numa_record:          db "Failure: numa_stat_record returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_numa_stats:           db "Failure: NUMA hits or misses count mismatch.", 0x0D, 0x0A, 0
msg_prof_fail_sat_init:             db "Failure: bw_sat_init returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_sat_check:            db "Failure: bw_sat_check returned incorrect saturation state.", 0x0D, 0x0A, 0
msg_prof_fail_sat_stats:            db "Failure: Bandwidth saturation alerts count mismatch.", 0x0D, 0x0A, 0
msg_prof_fail_inf_init:             db "Failure: inf_prof_init returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_inf_record:           db "Failure: inf_prof_record_layer returned 0.", 0x0D, 0x0A, 0
msg_prof_fail_inf_stats:            db "Failure: Inference weights, activations or cache metrics mismatch.", 0x0D, 0x0A, 0

section .bss

align 8
smep_smap_test_buf:            resb 32
align 8
req_A: resb 40
req_B: resb 40
req_ptrs: resq 2
dest_phys_A: resq 1
dest_phys_B: resq 1

; AI/Inference Specific Memory Test buffers
align 64
sys_tensor_pool_test_buf:   resb 16384

align 32
sys_kv_src_bytes:           resb 8
align 32
sys_kv_packed_dword:        resd 1
align 32
sys_kv_unpacked_bytes:      resb 8

align 32
sys_quant_src_bytes:        resb 8
align 32
sys_quant_packed_bytes:     resb 4
align 32
sys_quant_unpacked_bytes:   resb 8

align 64
sys_rt_det_test_pool:       resb 65536

; BSS variables for dirty tracing test
align 8
dbg_watch_phys_page: resq 1
dbg_watch_vma_ptr:   resq 1

; BSS variables for watchpoint test
align 8
dbg_wp_phys_page: resq 1
dbg_wp_vma_ptr:   resq 1

; BSS variables for IFT watchpoint test
align 8
dbg_ift_phys_page: resq 1
dbg_ift_vma_ptr:   resq 1

; BSS variables for access histogram test
align 8
dbg_hist_phys_page: resq 1
dbg_hist_vma_ptr:   resq 1

; BSS variables for physical watchpoint test
align 8
dbg_phys_wp_phys_page: resq 1
dbg_phys_wp_vma1_ptr:  resq 1
dbg_phys_wp_vma2_ptr:  resq 1

align 8
oom_callback_flag:     resq 1

%endif ; LIB_MEM_VIRT_DBG_WATCH_ASM




