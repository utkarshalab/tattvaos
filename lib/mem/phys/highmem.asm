; =============================================================================
; Tattva OS — sparse high-memory identity mapping and publication
; =============================================================================
;
; Physical addresses are still used as pointers throughout the kernel.  Keep
; the loader's [0, 4 GiB) contiguous identity aperture, then add mappings only
; for canonical usable E820 extents below PHYS_IDENTITY_VA_LIMIT.  High PFNs
; remain reserved in the allocator bitmap until every mapping is verified.
; =============================================================================

%ifndef LIB_MEM_PHYS_HIGHMEM_ASM
%define LIB_MEM_PHYS_HIGHMEM_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; phys_highmem_init — transactionally map, verify, publish, and exercise RAM
; above 4 GiB.  Must run after phys_init/virt_shuffle_pml4_init and before NUMA.
; Output: RAX = 1 on success (including no-high-memory skip), 0 on failure
; Clobbers: none except RAX
; -----------------------------------------------------------------------------
global phys_highmem_init
phys_highmem_init:
    push rbx
    push rbp
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    cmp qword [phys_state + phys_state_t.high_pages], 0
    je .no_high_memory

    mov rax, [boot_info_ptr]
    mov r12, [rax + BOOT_INFO_E820_PTR_OFF]
    mov r13d, [rax + BOOT_INFO_E820_COUNT_OFF]
    xor r14, r14

.map_entry_loop:
    cmp r14, r13
    jae .map_complete

    mov r15, r14
    imul r15, e820_entry_size
    add r15, r12
    mov rdi, r15
    call phys_highmem_clip_extent
    test rax, rax
    jz .map_entry_next

    mov rdi, rax                    ; aligned/clipped start
    mov rsi, rdx                    ; aligned/clipped exclusive end
    call phys_highmem_map_extent
    test rax, rax
    jz .failed

.map_entry_next:
    inc r14
    jmp .map_entry_loop

.map_complete:
    call phys_highmem_verify_holes
    test rax, rax
    jz .failed

    mov rsi, msg_highmem_map_ok
    call uart_print_str

    ; Publication is a separate pass.  An OOM or verification failure above
    ; therefore leaves all high frames reserved even if harmless partial page
    ; tables were installed.
    xor r14, r14
.publish_entry_loop:
    cmp r14, r13
    jae .publish_complete

    mov r15, r14
    imul r15, e820_entry_size
    add r15, r12
    mov rdi, r15
    call phys_highmem_clip_extent
    test rax, rax
    jz .publish_entry_next

    mov rdi, rax
    mov rsi, rdx
    call phys_highmem_publish_extent

.publish_entry_next:
    inc r14
    jmp .publish_entry_loop

.publish_complete:
    call phys_recount_free_pages
    cmp rax, [phys_state + phys_state_t.total_pages]
    ja .failed
    mov [phys_state + phys_state_t.free_pages], rax
    mov rdx, [phys_state + phys_state_t.total_pages]
    sub rdx, rax
    mov [phys_state + phys_state_t.reserved_pages], rdx
    mov qword [phys_state + phys_state_t.highmem_ready], 1

    ; Prove allocator selection, hardware access, zero-on-free, and counter
    ; restoration on one real frame above 4 GiB before NUMA snapshots state.
    mov r12, [phys_state + phys_state_t.free_pages]
    call phys_alloc_high_page
    test rax, rax
    jz .failed
    mov rbx, rax
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    cmp rbx, rdx
    jb .release_failed

    mov rax, 0x5441545448494748     ; "TATTHIGH"
    mov [rbx], rax
    mov rdx, 0x5041474550415353     ; "PAGEPASS"
    mov [rbx + 4088], rdx
    cmp [rbx], rax
    jne .release_failed
    cmp [rbx + 4088], rdx
    jne .release_failed

    mov rdi, rbx
    call phys_free_page
    cmp [phys_state + phys_state_t.free_pages], r12
    jne .failed
    cmp qword [rbx], 0
    jne .failed
    cmp qword [rbx + 4088], 0
    jne .failed

    mov rsi, msg_highmem_rw_pass
    call uart_print_str
    mov rax, rbx
    call uart_print_hex64
    mov rsi, msg_highmem_newline
    call uart_print_str
    mov rax, 1
    jmp .exit

.release_failed:
    mov rdi, rbx
    call phys_free_page

.failed:
    call phys_highmem_rollback
    mov rsi, msg_highmem_map_fail
    call uart_print_str
    xor rax, rax
    jmp .exit

.no_high_memory:
    mov qword [phys_state + phys_state_t.highmem_ready], 1
    mov rsi, msg_highmem_map_skip
    call uart_print_str
    mov rsi, msg_highmem_rw_skip
    call uart_print_str
    mov rax, 1

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_highmem_rollback — revoke every candidate high PFN after any mapping,
; publication, allocation, or R/W verification failure.  Mappings may remain
; installed but cannot be allocated while readiness is clear and occupancy is
; restored.  Runs before AP/NUMA startup, so no other allocator can race it.
; -----------------------------------------------------------------------------
phys_highmem_rollback:
    push rax
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov qword [phys_state + phys_state_t.highmem_ready], 0
    mov rax, [boot_info_ptr]
    mov r12, [rax + BOOT_INFO_E820_PTR_OFF]
    mov r13d, [rax + BOOT_INFO_E820_COUNT_OFF]
    xor r14d, r14d
.rollback_entry_loop:
    cmp r14, r13
    jae .rollback_recount
    mov r15, r14
    imul r15, e820_entry_size
    add r15, r12
    mov rdi, r15
    call phys_highmem_clip_extent
    test rax, rax
    jz .rollback_entry_next
    mov rdi, rax
    mov rsi, rdx
    call phys_highmem_revoke_extent
.rollback_entry_next:
    inc r14
    jmp .rollback_entry_loop

.rollback_recount:
    call phys_recount_free_pages
    mov [phys_state + phys_state_t.free_pages], rax
    mov rdx, [phys_state + phys_state_t.total_pages]
    sub rdx, rax
    mov [phys_state + phys_state_t.reserved_pages], rdx

    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rax
    ret

; -----------------------------------------------------------------------------
; phys_highmem_clip_extent
; Input:  RDI = e820_entry pointer
; Output: RAX = clipped page-aligned start, RDX = exclusive end
;         RAX = 0 when the entry has no supported high usable pages
; -----------------------------------------------------------------------------
phys_highmem_clip_extent:
    xor eax, eax
    cmp dword [rdi + e820_entry.type], 1
    jne .done

    mov rax, [rdi + e820_entry.base]
    mov rdx, [rdi + e820_entry.length]
    add rdx, rax
    jc .none                        ; phys_init already rejects this map
    add rax, 4095
    jc .none
    and rax, -4096
    and rdx, -4096

    mov rcx, PHYS_BOOTSTRAP_MAP_LIMIT
    cmp rax, rcx
    jae .start_ready
    mov rax, rcx
.start_ready:
    mov rcx, [phys_state + phys_state_t.address_limit]
    cmp rdx, rcx
    jbe .end_ready
    mov rdx, rcx
.end_ready:
    cmp rdx, rax
    ja .done
.none:
    xor eax, eax
.done:
    ret

; -----------------------------------------------------------------------------
; phys_highmem_map_extent
; Input: RDI = aligned start, RSI = aligned exclusive end
; Output: RAX = 1 on success, 0 on mapping/translation failure
; -----------------------------------------------------------------------------
phys_highmem_map_extent:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, PAGE_WRITABLE | PAGE_GLOBAL | PAGE_NX

.leading_pages:
    cmp r12, r13
    jae .success
    test r12, 0x1FFFFF
    jz .huge_pages
    call .map_4k
    test rax, rax
    jz .failure
    add r12, 4096
    jmp .leading_pages

.huge_pages:
    mov rbx, r12
    add rbx, 0x200000
    jc .failure
    cmp rbx, r13
    ja .trailing_pages

    mov rdi, r12
    mov rsi, r12
    mov rdx, r14
    call virt_map_huge_2mb
    test rax, rax
    jz .failure

    mov rdi, r12
    mov rsi, r12
    mov rdx, 3                     ; 2 MiB leaf
    call phys_highmem_verify_leaf
    test rax, rax
    jz .failure
    lea rdi, [r12 + 0x1FFFFF]
    mov rsi, rdi
    mov rdx, 3
    call phys_highmem_verify_leaf
    test rax, rax
    jz .failure

    add r12, 0x200000
    jmp .huge_pages

.trailing_pages:
    cmp r12, r13
    jae .success
    call .map_4k
    test rax, rax
    jz .failure
    add r12, 4096
    jmp .trailing_pages

.map_4k:
    mov rdi, r12
    mov rsi, r12
    mov rdx, r14
    call virt_map
    test rax, rax
    jz .map_4k_done
    mov rdi, r12
    mov rsi, r12
    mov rdx, 4                     ; 4 KiB leaf with LA57 disabled
    call phys_highmem_verify_leaf
.map_4k_done:
    ret

.success:
    mov rax, 1
    jmp .exit
.failure:
    xor rax, rax
.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_highmem_verify_leaf — validate exact leaf level, PA, and kernel flags.
; Input: RDI = virtual address, RSI = expected physical address
;        RDX = expected level (3 for 2 MiB, 4 for 4 KiB under four-level paging)
; Output: RAX = 1 when exact, 0 otherwise
; -----------------------------------------------------------------------------
phys_highmem_verify_leaf:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r14, 4
    jne .walk
    mov rax, cr4
    test rax, 1 << 12              ; LA57
    jz .walk
    inc r14

.walk:
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jz .invalid
    cmp rdx, r14
    jne .invalid

    mov rbx, [rax]
    mov rcx, rbx
    and rcx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_GLOBAL
    cmp rcx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_GLOBAL
    jne .invalid
    test rbx, PAGE_USER
    jnz .invalid

    cmp byte [cpu_has_nx], 0
    je .nx_must_be_clear
    bt rbx, 63
    jnc .invalid
    jmp .address
.nx_must_be_clear:
    bt rbx, 63
    jc .invalid

.address:
    cmp r14, 3
    jne .page_4k
    test rbx, PAGE_HUGE
    jz .invalid
    mov rax, PAGE_ADDR_MASK_2M
    and rbx, rax
    mov rax, r12
    and rax, 0x1FFFFF
    add rbx, rax
    jmp .compare

.page_4k:
    test rbx, PAGE_HUGE            ; PAT is not requested on high RAM leaves
    jnz .invalid
    mov rax, PAGE_ADDR_MASK_4K
    and rbx, rax
    mov rax, r12
    and rax, 0xFFF
    add rbx, rax

.compare:
    cmp rbx, r13
    jne .invalid
    mov eax, 1
    jmp .verify_exit
.invalid:
    xor eax, eax
.verify_exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_highmem_verify_holes — prove that one complete page from every
; representable reserved descriptor or undescribed high gap remains unmapped.
; Output: RAX = 1 on success, 0 if any sampled hole is mapped
; -----------------------------------------------------------------------------
phys_highmem_verify_holes:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rax, [boot_info_ptr]
    mov r12, [rax + BOOT_INFO_E820_PTR_OFF]
    mov r13d, [rax + BOOT_INFO_E820_COUNT_OFF]
    mov r14, PHYS_BOOTSTRAP_MAP_LIMIT ; cursor
    xor r15, r15

.hole_entry_loop:
    cmp r15, r13
    jae .tail_gap
    mov rax, r15
    imul rax, e820_entry_size
    lea rbp, [r12 + rax]

    mov rbx, [rbp + e820_entry.base]
    mov rdx, [rbp + e820_entry.length]
    test rdx, rdx
    jz .hole_next                    ; parser ignores empty descriptors too
    add rdx, rbx
    jc .hole_invalid
    mov rcx, PHYS_BOOTSTRAP_MAP_LIMIT
    cmp rdx, rcx
    jbe .hole_next
    mov rax, [phys_state + phys_state_t.address_limit]
    cmp rbx, rax
    jae .tail_gap

    ; Sample a complete page in the undescribed gap before this descriptor.
    mov rax, r14
    add rax, 4095
    jc .hole_invalid
    and rax, -4096
    mov rcx, rax
    add rcx, 4096
    jc .hole_invalid
    cmp rcx, rbx
    ja .descriptor_sample
    mov rdi, rax
    push rdx
    call virt_translate
    pop rdx
    test rax, rax
    jnz .hole_invalid

.descriptor_sample:
    cmp dword [rbp + e820_entry.type], 1
    je .advance_cursor
    mov rax, rbx
    mov rcx, PHYS_BOOTSTRAP_MAP_LIMIT
    cmp rax, rcx
    cmovb rax, rcx                 ; never inspect the mapped low aperture
    add rax, 4095
    jc .hole_invalid
    and rax, -4096
    mov rcx, rdx
    and rcx, -4096
    mov rdi, [phys_state + phys_state_t.address_limit]
    cmp rcx, rdi
    jbe .reserved_end_ready
    mov rcx, rdi
.reserved_end_ready:
    cmp rcx, rax
    jbe .advance_cursor
    mov rdi, rax
    push rdx
    call virt_translate
    pop rdx
    test rax, rax
    jnz .hole_invalid

.advance_cursor:
    mov rax, [phys_state + phys_state_t.address_limit]
    cmp rdx, rax
    jbe .cursor_end_ready
    mov rdx, rax
.cursor_end_ready:
    cmp rdx, r14
    jbe .hole_next
    mov r14, rdx
.hole_next:
    inc r15
    jmp .hole_entry_loop

.tail_gap:
    mov rax, r14
    add rax, 4095
    jc .hole_invalid
    and rax, -4096
    mov rcx, rax
    add rcx, 4096
    jc .hole_invalid
    cmp rcx, [phys_state + phys_state_t.address_limit]
    ja .holes_valid
    mov rdi, rax
    call virt_translate
    test rax, rax
    jnz .hole_invalid

.holes_valid:
    mov eax, 1
    jmp .holes_exit
.hole_invalid:
    xor eax, eax
.holes_exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_highmem_publish_extent — clear exactly one mapped usable bitmap run.
; Input: RDI = aligned start, RSI = aligned exclusive end
; -----------------------------------------------------------------------------
phys_highmem_publish_extent:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    push r8

    mov rbx, rdi
    shr rbx, 12                     ; starting PFN
    mov r8, rsi
    shr r8, 12                      ; exclusive ending PFN

.leading_bits:
    cmp rbx, r8
    jae .done
    test rbx, 63
    jz .whole_words
    mov rdi, rbx
    call bitmap_clear_bit
    inc rbx
    jmp .leading_bits

.whole_words:
    mov rax, r8
    sub rax, rbx
    shr rax, 6                      ; complete qwords
    jz .trailing_bits

    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    mov rdx, rbx
    shr rdx, 6
    lea rdi, [rdi + rdx * 8]
    mov rcx, rax
    xor eax, eax
    cld
    rep stosq

    mov rax, rcx                    ; RCX is zero after REP
    mov rax, r8
    sub rax, rbx
    and rax, -64
    add rbx, rax

.trailing_bits:
    cmp rbx, r8
    jae .done
    mov rdi, rbx
    call bitmap_clear_bit
    inc rbx
    jmp .trailing_bits

.done:
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; phys_highmem_revoke_extent — restore one published high range to permanent
; occupancy and remove any dynamic ownership left by a failed boot self-test.
; Input: RDI = aligned start, RSI = aligned exclusive end
; -----------------------------------------------------------------------------
phys_highmem_revoke_extent:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    push r9

    mov rbx, rdi
    shr rbx, 12                     ; starting PFN
    mov r8, rsi
    shr r8, 12                      ; exclusive ending PFN

.leading_bits:
    cmp rbx, r8
    jae .done
    test rbx, 63
    jz .whole_words
    mov rdi, rbx
    call bitmap_set_bit
    mov rdi, rbx
    call alloc_bitmap_clear_bit
    inc rbx
    jmp .leading_bits

.whole_words:
    mov r9, r8
    sub r9, rbx
    shr r9, 6                       ; complete qwords
    jz .trailing_bits

    mov rdx, rbx
    shr rdx, 6
    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    lea rdi, [rdi + rdx * 8]
    mov rcx, r9
    mov rax, -1
    cld
    rep stosq

    mov rdi, [phys_state + phys_state_t.alloc_bitmap_addr]
    lea rdi, [rdi + rdx * 8]
    mov rcx, r9
    xor eax, eax
    rep stosq

    shl r9, 6
    add rbx, r9

.trailing_bits:
    cmp rbx, r8
    jae .done
    mov rdi, rbx
    call bitmap_set_bit
    mov rdi, rbx
    call alloc_bitmap_clear_bit
    inc rbx
    jmp .trailing_bits

.done:
    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; phys_alloc_high_page — boot-only first-fit allocation at/above 4 GiB.
; High bits are already published and no AP or NUMA allocator is active yet.
; Output: RAX = allocated physical page or 0
; -----------------------------------------------------------------------------
phys_alloc_high_page:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8

    mov rbx, PHYS_BOOTSTRAP_MAP_LIMIT >> 12
    mov r8, [phys_state + phys_state_t.frame_count]
    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    pushfq
    cli
    call phys_lock_acquire

.scan_word:
    cmp rbx, r8
    jae .not_found

    mov rdx, rbx
    shr rdx, 6
    mov rax, [rsi + rdx * 8]
    not rax
    test rax, rax
    jz .next_word
    bsf rcx, rax

    shl rdx, 6
    add rdx, rcx                    ; candidate PFN
    cmp rdx, r8
    jae .not_found

    mov rdi, rdx
    call bitmap_set_bit
    mov rdi, rdx
    call alloc_bitmap_set_bit
    dec qword [phys_state + phys_state_t.free_pages]
    inc qword [phys_state + phys_state_t.reserved_pages]
    call phys_lock_release
    popfq
    mov rax, rdx
    shl rax, 12
    jmp .done

.next_word:
    add rbx, 64
    jmp .scan_word

.not_found:
    call phys_lock_release
    popfq
    xor eax, eax
.done:
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

section .rodata
msg_highmem_map_ok:   db "Paging high map verify: OK", 0x0D, 0x0A, 0
msg_highmem_map_fail: db "Paging high map verify: FAIL", 0x0D, 0x0A, 0
msg_highmem_map_skip: db "Paging high map verify: SKIP (no supported RAM above 4 GiB)", 0x0D, 0x0A, 0
msg_highmem_rw_pass:  db "Highmem direct-map R/W: PASS phys=", 0
msg_highmem_rw_skip:  db "Highmem direct-map R/W: SKIP (no supported RAM above 4 GiB)", 0x0D, 0x0A, 0
msg_highmem_newline:  db 0x0D, 0x0A, 0

%endif ; LIB_MEM_PHYS_HIGHMEM_ASM
