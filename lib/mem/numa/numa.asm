; =============================================================================
; Tattva OS — lib/mem/numa/numa.asm
; =============================================================================
; NUMA Range structures and Node ID lookup functions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_NUMA_NUMA_ASM
%define LIB_MEM_NUMA_NUMA_ASM

[BITS 64]



; Maximum memory ranges we support parsing from SRAT
NUMA_MAX_RANGES equ 32

; NUMA node distance matrix constants
NUMA_MAX_NODES equ 8
NUMA_DEFAULT_LOCAL_DISTANCE equ 10
NUMA_DEFAULT_REMOTE_DISTANCE equ 20

section .text

; -----------------------------------------------------------------------------
; numa_get_node_by_phys — finds the NUMA Node ID for a physical address
; Input:
;   RDI = physical address
; Output:
;   RAX = Node ID (32-bit), or 0 if not found / UMA fallback
; -----------------------------------------------------------------------------
global numa_get_node_by_phys
numa_get_node_by_phys:
    push rbx
    push rcx
    push rdx

    mov rcx, [numa_range_count]
    test rcx, rcx
    jz .fallback

    lea rbx, [numa_ranges]
    xor rdx, rdx                    ; index i = 0

.loop:
    cmp rdx, rcx
    jge .fallback

    ; Calculate offset of range entry
    mov rax, rdx
    imul rax, numa_range_t_size
    lea r8, [rbx + rax]

    ; Check if entry is enabled (flags bit 0)
    mov eax, [r8 + numa_range_t.flags]
    test al, 1
    jz .next

    ; Check if RDI >= base
    mov rax, [r8 + numa_range_t.base]
    cmp rdi, rax
    jb .next

    ; Check if RDI < base + length
    add rax, [r8 + numa_range_t.length]
    cmp rdi, rax
    jb .found

.next:
    inc rdx
    jmp .loop

.found:
    mov eax, dword [r8 + numa_range_t.node_id]
    jmp .exit

.fallback:
    xor rax, rax                    ; default to Node 0

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_range_owner — prove a byte range is continuously covered by enabled
; NUMA ranges belonging to one node.
; Input:  RDI = physical start, RSI = exclusive physical end
; Output: RAX = node ID, or -1 for a gap, mixed ownership, or malformed range
; Clobbers: none except RAX
; -----------------------------------------------------------------------------
global numa_range_owner
numa_range_owner:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11

    mov r8, rdi                     ; covered-through cursor
    mov r9, rsi
    mov r10, -1                    ; owner not selected yet
    cmp r8, r9
    jae .strict_not_found

.strict_cover:
    cmp r8, r9
    jae .strict_found
    xor ebx, ebx

.strict_scan:
    cmp rbx, [numa_range_count]
    jae .strict_not_found
    mov rax, rbx
    imul rax, numa_range_t_size
    lea rbp, [numa_ranges + rax]
    test dword [rbp + numa_range_t.flags], 1
    jz .strict_next

    mov rdx, [rbp + numa_range_t.base]
    mov rcx, [rbp + numa_range_t.length]
    add rcx, rdx
    jc .strict_not_found
    cmp r8, rdx
    jb .strict_next
    cmp r8, rcx
    jae .strict_next

    mov eax, [rbp + numa_range_t.node_id]
    cmp r10, -1
    je .strict_set_owner
    cmp rax, r10
    jne .strict_not_found
    jmp .strict_advance
.strict_set_owner:
    mov r10, rax
.strict_advance:
    mov r8, rcx
    cmp r8, r9
    jbe .strict_cover
    mov r8, r9
    jmp .strict_cover

.strict_next:
    inc rbx
    jmp .strict_scan

.strict_found:
    mov rax, r10
    jmp .strict_exit
.strict_not_found:
    mov rax, -1
.strict_exit:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_get_distance — gets relative memory distance between two nodes
; Input:
;   RDI = node_from (Node ID)
;   RSI = node_to (Node ID)
; Output:
;   RAX = relative distance (e.g. 10 = local, 20 = default remote, 255 = unreachable)
; -----------------------------------------------------------------------------
global numa_get_distance
numa_get_distance:
    push rbx
    push rcx
    push rdx

    ; 1. Check bounds against numa_node_count
    mov rcx, [numa_node_count]
    test rcx, rcx
    jz .local_check                 ; if count is 0 (uninitialized), do UMA check

    cmp rdi, rcx
    jae .out_of_bounds
    cmp rsi, rcx
    jae .out_of_bounds

    ; Calculate index: node_from * numa_node_count + node_to
    mov rax, rdi
    imul rax, rcx
    add rax, rsi                    ; RAX = index
    
    ; Load distance byte from matrix
    lea rbx, [numa_distance_matrix]
    movzx rax, byte [rbx + rax]
    jmp .exit

.local_check:
    ; Fallback UMA check: if node_from == node_to, distance is 10, else 255
    cmp rdi, rsi
    je .local
    mov rax, 255
    jmp .exit
.local:
    mov rax, NUMA_DEFAULT_LOCAL_DISTANCE
    jmp .exit

.out_of_bounds:
    mov rax, 255                    ; unreachable/invalid

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_count_usable_pages — count canonical E820 usable pages inside a PFN span
; Input:  RDI = first PFN, RSI = exclusive ending PFN
; Output: RAX = page count
; Clobbers: none except RAX
; -----------------------------------------------------------------------------
numa_count_usable_pages:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11

    mov r8, rdi
    mov r9, rsi
    xor r10d, r10d
    cmp r8, r9
    jae .usable_count_done

    mov rax, [boot_info_ptr]
    test rax, rax
    jz .usable_count_done
    mov r11, [rax + BOOT_INFO_E820_PTR_OFF]
    mov ebp, [rax + BOOT_INFO_E820_COUNT_OFF]
    xor ebx, ebx

.usable_count_loop:
    cmp rbx, rbp
    jae .usable_count_done
    mov rax, rbx
    imul rax, e820_entry_size
    add rax, r11
    cmp dword [rax + e820_entry.type], 1
    jne .usable_count_next

    mov rdx, [rax + e820_entry.base]
    mov rcx, [rax + e820_entry.length]
    add rcx, rdx
    jc .usable_count_next
    add rdx, 4095
    jc .usable_count_next
    and rdx, -4096
    and rcx, -4096
    shr rdx, 12                    ; aligned E820 first PFN
    shr rcx, 12                    ; aligned E820 exclusive PFN

    cmp rdx, r8
    cmovb rdx, r8
    cmp rcx, r9
    cmova rcx, r9
    cmp rdx, rcx
    jae .usable_count_next
    sub rcx, rdx
    add r10, rcx

.usable_count_next:
    inc rbx
    jmp .usable_count_loop

.usable_count_done:
    mov rax, r10
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; alloc_local_pages_for_bitmap — allocate contiguous pages within a node's physical ranges
; Input:
;   RDI = pointer to numa_node_t
;   RSI = page_count
; Output:
;   RAX = physical address, or 0 if failed
; Clobbers: RAX, RCX, RDX, R8, R9, R10, R11
; -----------------------------------------------------------------------------
alloc_local_pages_for_bitmap:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov r12, rdi                    ; r12 = node_ptr
    mov r13, rsi                    ; r13 = page_count
    mov r14d, [r12 + numa_node_t.node_id]

    ; Walk all numa_ranges to find one that belongs to node_id R14D
    xor rbx, rbx                    ; rbx = range index i = 0
.range_loop:
    cmp rbx, [numa_range_count]
    jae .failed

    mov rax, rbx
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]

    ; Check if range is enabled and belongs to our node
    mov eax, [rdx + numa_range_t.flags]
    test al, 1                      ; enabled?
    jz .next_range
    mov eax, [rdx + numa_range_t.node_id]
    cmp eax, r14d
    jne .next_range

    ; USABLE RANGE found! Search for consecutive free pages inside [base .. base+length]
    mov r8, [rdx + numa_range_t.base]
    mov r9, [rdx + numa_range_t.length]
    
    ; Convert base and end to page indices
    shr r8, 12                      ; r8 = start page
    mov r10, r8
    shr r9, 12
    add r10, r9                     ; r10 = end page (exclusive)

    ; Search from r8 to r10 - r13
    mov rdi, r8                     ; rdi = current search index
.search_loop:
    mov rcx, rdi
    add rcx, r13
    cmp rcx, r10
    ja .next_range                  ; exceeds this range

    ; Verify if r13 pages starting at rdi are all free in the global bitmap
    xor rcx, rcx                    ; rcx = offset 0 .. r13-1
.check_free:
    cmp rcx, r13
    jae .found_block

    mov rax, rdi
    add rax, rcx                    ; page index to test

    ; Test page index in the global bitmap
    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov rdx, rax
    shr rdx, 6                      ; qword index
    and rax, 63                     ; bit offset
    bt qword [rsi + rdx * 8], rax
    jc .blocked                     ; bit set = occupied

    inc rcx
    jmp .check_free

.blocked:
    add rdi, rcx                    ; skip checked pages
    inc rdi
    jmp .search_loop

.found_block:
    ; Reserve these pages in the global bitmap
    xor rcx, rcx
.reserve_loop:
    cmp rcx, r13
    jae .reserve_done

    mov rax, rdi
    add rax, rcx

    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov rdx, rax
    shr rdx, 6                      ; qword index
    and rax, 63                     ; bit offset
    bts qword [rsi + rdx * 8], rax

    inc rcx
    jmp .reserve_loop

.reserve_done:
    ; This is a permanent allocator-metadata reservation, not a dynamic
    ; allocation: update occupancy counters but leave ownership bits clear.
    sub [phys_state + phys_state_t.free_pages], r13
    add [phys_state + phys_state_t.reserved_pages], r13

    ; Return physical address
    mov rax, rdi
    shl rax, 12                     ; convert to phys address
    jmp .exit

.next_range:
    inc rbx
    jmp .range_loop

.failed:
    xor rax, rax                    ; return 0

.exit:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_init_local_bitmaps — allocates and transitions to node-local bitmaps
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global numa_init_local_bitmaps
numa_init_local_bitmaps:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov qword [numa_local_bitmaps_active], 0

    mov r14, [numa_node_count]
    test r14, r14
    jz .exit                        ; if 0 nodes, exit

    ; 1. Calculate boundaries for each node
    xor r15, r15                    ; r15 = node index k = 0
.node_setup_loop:
    cmp r15, r14
    jae .init_bitmaps_start

    mov rax, r15
    imul rax, numa_node_t_size
    lea r12, [numa_nodes + rax]     ; r12 = current node descriptor

    ; Initialize default values
    mov dword [r12 + numa_node_t.node_id], r15d
    mov dword [r12 + numa_node_t.flags], 0
    mov qword [r12 + numa_node_t.start_page], -1 ; 0xFFFFFFFFFFFFFFFF
    mov qword [r12 + numa_node_t.end_page], 0
    mov qword [r12 + numa_node_t.total_pages], 0
    mov qword [r12 + numa_node_t.free_pages], 0
    mov qword [r12 + numa_node_t.reserved_pages], 0
    mov qword [r12 + numa_node_t.pages_min], 128
    mov qword [r12 + numa_node_t.pages_low], 256
    mov qword [r12 + numa_node_t.pages_high], 512
    mov qword [r12 + numa_node_t.proactive_reclaim_headroom], 0

    ; Scan numa_ranges to find boundaries
    xor rbx, rbx                    ; rbx = range index = 0
.node_ranges_loop:
    cmp rbx, [numa_range_count]
    jae .node_setup_next

    mov rax, rbx
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]

    ; Check enabled
    mov eax, [rdx + numa_range_t.flags]
    test al, 1
    jz .next_range_setup
    ; Check matching node_id
    mov eax, [rdx + numa_range_t.node_id]
    cmp eax, r15d
    jne .next_range_setup

    ; Mark node active (bit 0 = 1)
    or dword [r12 + numa_node_t.flags], 1

    ; Get page bounds
    mov r8, [rdx + numa_range_t.base]
    mov r9, [rdx + numa_range_t.length]
    
    shr r8, 12                      ; range start page
    mov r10, r8
    shr r9, 12
    add r10, r9                     ; range end page (exclusive)

    ; Update node start_page
    mov rcx, [r12 + numa_node_t.start_page]
    cmp rcx, -1
    je .set_start_page
    cmp r8, rcx
    jae .check_end_page
.set_start_page:
    mov [r12 + numa_node_t.start_page], r8

.check_end_page:
    mov rcx, [r12 + numa_node_t.end_page]
    cmp r10, rcx
    jbe .account_total_pages
    mov [r12 + numa_node_t.end_page], r10

.account_total_pages:
    ; SRAT spans can include firmware/MMIO holes.  Node totals describe only
    ; page-aligned type-1 E820 RAM managed by the global allocator.
    mov rdi, r8
    mov rsi, r10
    call numa_count_usable_pages
    add [r12 + numa_node_t.total_pages], rax

.next_range_setup:
    inc rbx
    jmp .node_ranges_loop

.node_setup_next:
    ; SRAT may advertise a domain whose ranges contain no canonical type-1
    ; E820 pages.  Keep it out of the allocator instead of allocating a huge
    ; all-reserved bitmap (or panicking) for memory the PMM can never use.
    cmp qword [r12 + numa_node_t.total_pages], 0
    jne .node_setup_advance
    mov dword [r12 + numa_node_t.flags], 0
    mov qword [r12 + numa_node_t.start_page], -1
    mov qword [r12 + numa_node_t.end_page], 0
.node_setup_advance:
    inc r15
    jmp .node_setup_loop

.init_bitmaps_start:
    ; 2. Allocate and initialize bitmap for each active node
    xor r15, r15                    ; r15 = node index k = 0
.node_bitmap_loop:
    cmp r15, r14
    jae .complete_transition

    mov rax, r15
    imul rax, numa_node_t_size
    lea r12, [numa_nodes + rax]     ; r12 = current node descriptor

    ; Check if node is active
    mov eax, [r12 + numa_node_t.flags]
    test al, 1
    jz .node_bitmap_next

    ; Calculate bitmap size in bytes
    mov rax, [r12 + numa_node_t.end_page]
    sub rax, [r12 + numa_node_t.start_page] ; page count
    add rax, 63
    shr rax, 6
    shl rax, 3                      ; qword-safe bitmap size in bytes
    mov [r12 + numa_node_t.bitmap_size], rax

    ; Calculate bitmap page count
    add rax, 4095
    shr rax, 12                      ; bitmap pages needed
    mov r13, rax                    ; r13 = bitmap page count

    ; Allocate local memory from this node for the bitmap
    mov rdi, r12
    mov rsi, r13
    call alloc_local_pages_for_bitmap
    test rax, rax
    jnz .local_alloc_ok

    ; Fallback to global allocator if local allocation failed
    mov rdi, r13
    call phys_alloc_pages
    test rax, rax
    jz .fallback_uma

.local_alloc_ok:
    mov [r12 + numa_node_t.bitmap_addr], rax

    ; Node bitmap backing is permanent metadata even when the global allocator
    ; supplied it through the fallback path.
    mov rbx, rax
    shr rbx, 12
    xor rcx, rcx
.clear_bitmap_ownership:
    cmp rcx, r13
    jae .bitmap_ownership_cleared
    mov rdi, rbx
    add rdi, rcx
    push rcx
    call alloc_bitmap_clear_bit
    pop rcx
    inc rcx
    jmp .clear_bitmap_ownership
.bitmap_ownership_cleared:

    ; A fallback allocation can land in a node whose bitmap was initialized
    ; earlier.  Reflect this new permanent reservation there immediately;
    ; current/later nodes will observe it while they snapshot the global map.
    xor rcx, rcx
.sync_initialized_owner:
    cmp rcx, r13
    jae .owner_sync_done
    mov rdi, rbx
    add rdi, rcx                    ; absolute PFN
    shl rdi, 12
    lea rsi, [rdi + 4096]
    push rcx
    call numa_range_owner
    pop rcx
    cmp rax, -1
    je .owner_sync_next
    cmp rax, [numa_node_count]
    jae .owner_sync_next
    imul rax, numa_node_t_size
    lea rbp, [numa_nodes + rax]
    test dword [rbp + numa_node_t.flags], 2
    jz .owner_sync_next

    mov rdx, rbx
    add rdx, rcx                    ; absolute PFN
    cmp rdx, [rbp + numa_node_t.start_page]
    jb .owner_sync_next
    cmp rdx, [rbp + numa_node_t.end_page]
    jae .owner_sync_next
    sub rdx, [rbp + numa_node_t.start_page]

    mov rdi, rbp
    mov rsi, rdx
    push rcx
    call bitmap_test_bit_local
    pop rcx
    test rax, rax
    jnz .owner_sync_next
    mov rdi, rbp
    mov rsi, rdx
    push rcx
    call bitmap_set_bit_local
    pop rcx
    dec qword [rbp + numa_node_t.free_pages]
    inc qword [rbp + numa_node_t.reserved_pages]

.owner_sync_next:
    inc rcx
    jmp .sync_initialized_owner
.owner_sync_done:

    ; Start reserved.  Only globally-free PFNs in this node's own enabled SRAT
    ; ranges are cleared below; holes and another node's RAM must stay busy.
    mov rdi, [r12 + numa_node_t.bitmap_addr]
    mov rcx, [r12 + numa_node_t.bitmap_size]
    mov al, 0xFF
    cld
    rep stosb

.populate_from_global:
    ; 3. Visit only this node's enabled ranges and clear a local bit when the
    ; corresponding global PFN is free.  This handles discontiguous nodes
    ; without publishing intervening holes or another node's memory.
    xor rbp, rbp                    ; NUMA range index
.populate_range_loop:
    cmp rbp, [numa_range_count]
    jae .recount_node_free_pages
    mov rax, rbp
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]
    test dword [rdx + numa_range_t.flags], 1
    jz .populate_next_range
    mov eax, [rdx + numa_range_t.node_id]
    cmp eax, [r12 + numa_node_t.node_id]
    jne .populate_next_range

    mov r10, [rdx + numa_range_t.base]
    shr r10, 12
    mov r11, [rdx + numa_range_t.length]
    shr r11, 12
    add r11, r10                    ; exclusive absolute PFN

.populate_range_pages:
    cmp r10, r11
    jae .populate_next_range
    mov rax, r10
    mov rdx, rax
    shr rdx, 6                      ; qword index
    and rax, 63                     ; bit offset
    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    bt qword [rsi + rdx * 8], rax
    jc .populate_next_page          ; globally occupied stays locally reserved

    mov rax, r10
    sub rax, [r12 + numa_node_t.start_page]
    mov rdx, rax
    shr rdx, 6
    and rax, 63
    mov rdi, [r12 + numa_node_t.bitmap_addr]
    btr qword [rdi + rdx * 8], rax

.populate_next_page:
    inc r10
    jmp .populate_range_pages
.populate_next_range:
    inc rbp
    jmp .populate_range_loop

.recount_node_free_pages:
    ; 4. Authoritative recount of free pages for this node
    mov rsi, [r12 + numa_node_t.bitmap_addr]
    mov rax, [r12 + numa_node_t.end_page]
    sub rax, [r12 + numa_node_t.start_page] ; page count
    mov rcx, rax

    xor r8, r8                      ; r8 = free page counter
    xor r9, r9                      ; r9 = relative page index
.node_recount_loop:
    cmp r9, rcx
    jae .node_recount_done

    mov rax, r9
    shr rax, 6                      ; qword index
    mov rbx, r9
    and rbx, 63                     ; bit offset
    bt qword [rsi + rax * 8], rbx
    jc .node_recount_next           ; if bit set, page is reserved

    inc r8                          ; page is free

.node_recount_next:
    inc r9
    jmp .node_recount_loop

.node_recount_done:
    mov [r12 + numa_node_t.free_pages], r8
    mov rax, [r12 + numa_node_t.total_pages]
    sub rax, r8
    mov [r12 + numa_node_t.reserved_pages], rax

    ; Mark bitmap initialized (bit 1 = 1)
    or dword [r12 + numa_node_t.flags], 2

.node_bitmap_next:
    inc r15
    jmp .node_bitmap_loop

.complete_transition:
    ; Set active flag to 1
    mov qword [numa_local_bitmaps_active], 1

    ; Print success message
    mov rsi, msg_numa_local_bitmaps_ok
    call uart_print_str

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

.fallback_uma:
    ; Node-local mirrors are an optimization.  The global occupancy bitmap is
    ; still authoritative, so allocation failure must degrade to UMA instead
    ; of making an otherwise usable machine unbootable.  Previously allocated
    ; backing remains permanently reserved; hide all partial descriptors.
    mov qword [numa_local_bitmaps_active], 0
    xor ecx, ecx
.hide_partial_bitmaps:
    cmp rcx, r14
    jae .fallback_uma_log
    mov rax, rcx
    imul rax, numa_node_t_size
    lea rdx, [numa_nodes + rax]
    and dword [rdx + numa_node_t.flags], ~2
    mov qword [rdx + numa_node_t.bitmap_addr], 0
    mov qword [rdx + numa_node_t.bitmap_size], 0
    inc rcx
    jmp .hide_partial_bitmaps
.fallback_uma_log:
    mov rsi, msg_numa_bitmap_fallback
    call uart_print_str
    jmp .exit

; -----------------------------------------------------------------------------
; numa_set_watermarks — configures watermarks for a specific node
; Input:
;   RDI = node_id
;   RSI = pages_min
;   RDX = pages_low
;   RCX = pages_high
; Output:
;   RAX = 1 (success), 0 (invalid node_id or inactive node)
; -----------------------------------------------------------------------------
global numa_set_watermarks
numa_set_watermarks:
    push rbx
    
    ; Check if node_id < numa_node_count
    mov rax, [numa_node_count]
    cmp rdi, rax
    jae .err
    
    ; Get node descriptor
    imul rdi, numa_node_t_size
    lea rbx, [numa_nodes + rdi]
    
    ; Check if active
    mov eax, [rbx + numa_node_t.flags]
    test al, 1
    jz .err
    
    ; Set watermarks
    mov [rbx + numa_node_t.pages_min], rsi
    mov [rbx + numa_node_t.pages_low], rdx
    mov [rbx + numa_node_t.pages_high], rcx
    
    mov rax, 1
    pop rbx
    ret
.err:
    xor rax, rax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_set_proactive_headroom — configures proactive reclaim headroom for a node
; Input:
;   RDI = node_id
;   RSI = headroom_pages
; Output:
;   RAX = 1 (success), 0 (invalid node_id or inactive node)
; -----------------------------------------------------------------------------
global numa_set_proactive_headroom
numa_set_proactive_headroom:
    push rbx
    
    ; Check if node_id < numa_node_count
    mov rax, [numa_node_count]
    cmp rdi, rax
    jae .err
    
    ; Get node descriptor
    imul rdi, numa_node_t_size
    lea rbx, [numa_nodes + rdi]
    
    ; Check if active
    mov eax, [rbx + numa_node_t.flags]
    test al, 1
    jz .err
    
    ; Set headroom
    mov [rbx + numa_node_t.proactive_reclaim_headroom], rsi
    
    mov rax, 1
    pop rbx
    ret
.err:
    xor rax, rax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Data Section — NUMA ranges array and count
; -----------------------------------------------------------------------------
section .data

align 8
global numa_ranges
global numa_range_count
global numa_node_count
global numa_distance_matrix
global numa_nodes
global numa_local_bitmaps_active
global msg_numa_fallback_prefix
global msg_numa_fallback_middle
global msg_numa_fallback_dist
global msg_numa_fallback_suffix


numa_ranges:          times NUMA_MAX_RANGES * numa_range_t_size db 0
numa_range_count:     dq 0
numa_node_count:      dq 0
numa_distance_matrix: times NUMA_MAX_NODES * NUMA_MAX_NODES db 0
numa_nodes:          times NUMA_MAX_NODES * numa_node_t_size db 0
numa_local_bitmaps_active:   dq 0

msg_numa_local_bitmaps_ok:   db "NUMA: Node-Local Bitmaps successfully initialized.", 0x0D, 0x0A, 0
msg_numa_bitmap_fallback:    db "NUMA: node-local bitmap allocation failed; continuing with global PMM.", 0x0D, 0x0A, 0

msg_numa_fallback_prefix: db "NUMA: Node ", 0
msg_numa_fallback_middle: db " OOM, falling back to Node ", 0
msg_numa_fallback_dist:   db " (distance ", 0
msg_numa_fallback_suffix: db ")", 0x0D, 0x0A, 0

%endif ; LIB_MEM_NUMA_NUMA_ASM
