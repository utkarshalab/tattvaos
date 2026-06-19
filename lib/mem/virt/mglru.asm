; =============================================================================
; Tattva OS — lib/mem/virt/mglru.asm
; =============================================================================
; Multi-Gen LRU (MGLRU) Page Replacement Engine.
; Maintains pages in 4 generations (Gen 0 oldest to Gen 3 youngest).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_MGLRU_ASM
%define LIB_MEM_VIRT_MGLRU_ASM

[BITS 64]

; Page Table Entry Flags (re-defined locally for assembly safety)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_ACCESSED   equ (1 << 5)
PAGE_SWAPPED    equ (1 << 10)
PAGE_ZSWAPPED   equ (1 << 11)

; Node structure for tracked page frames (matches replacement.asm)
struc page_node_t
    .phys_addr  resq 1          ; Physical address of the 4KB page frame
    .virt_addr  resq 1          ; Virtual address where it is mapped
    .flags      resq 1          ; Flags (Generation index 0-3 when MGLRU active)
    .prev       resq 1          ; Previous node pointer
    .next       resq 1          ; Next node pointer
endstruc

section .text

; External references
extern heap_alloc
extern heap_free
extern virt_walk_table
extern phys_free_page
extern swap_alloc_slot
extern swap_write_page
extern swap_free_slot
extern zswap_compress_and_store
extern zswap_free_slot
extern replacement_lock_acquire
extern replacement_lock_release
extern phys_state
extern phys_state_t

; -----------------------------------------------------------------------------
; virt_mglru_init — initializes the MGLRU page tracking structures
; -----------------------------------------------------------------------------
global virt_mglru_init
virt_mglru_init:
    push rdi
    push rcx
    push rax

    ; Zero heads, tails, counts
    lea rdi, [sys_mglru_head]
    mov rcx, 4
    xor rax, rax
    rep stosq

    lea rdi, [sys_mglru_tail]
    mov rcx, 4
    xor rax, rax
    rep stosq

    lea rdi, [sys_mglru_count]
    mov rcx, 4
    xor rax, rax
    rep stosq

    mov qword [sys_mglru_promotions], 0
    mov qword [sys_mglru_reclaims], 0
    mov qword [sys_mglru_ages], 0

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; virt_mglru_add — tracks page in MGLRU generation
; Input: RDI = phys, RSI = virt, RDX = gen (0-3)
; -----------------------------------------------------------------------------
global virt_mglru_add
virt_mglru_add:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                    ; phys
    mov r13, rsi                    ; virt
    mov r14, rdx                    ; gen

    ; 1. Allocate node
    mov rdi, page_node_t_size
    call heap_alloc
    test rax, rax
    jz .exit

    mov rbx, rax                    ; rbx = node
    mov [rbx + page_node_t.phys_addr], r12
    mov [rbx + page_node_t.virt_addr], r13
    mov [rbx + page_node_t.flags], r14     ; store gen in flags
    mov qword [rbx + page_node_t.prev], 0
    mov qword [rbx + page_node_t.next], 0

    call replacement_lock_acquire

    ; Prepend to generation R14 list
    mov rcx, [sys_mglru_head + r14 * 8]
    test rcx, rcx
    jz .first_node

    mov [rbx + page_node_t.next], rcx
    mov [rcx + page_node_t.prev], rbx
    mov [sys_mglru_head + r14 * 8], rbx
    jmp .inserted

.first_node:
    mov [sys_mglru_head + r14 * 8], rbx
    mov [sys_mglru_tail + r14 * 8], rbx

.inserted:
    inc qword [sys_mglru_count + r14 * 8]
    call replacement_lock_release

.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_mglru_remove — untracks page from MGLRU
; Input: RDI = phys
; -----------------------------------------------------------------------------
global virt_mglru_remove
virt_mglru_remove:
    push rbx
    push r12
    push r13
    mov r12, rdi

    call replacement_lock_acquire

    ; Find page in generations
    xor r13, r13                    ; r13 = gen loop index
.loop:
    cmp r13, 4
    jae .unlock_done

    mov rbx, [sys_mglru_head + r13 * 8]
.node_loop:
    test rbx, rbx
    jz .next_gen
    cmp [rbx + page_node_t.phys_addr], r12
    je .found
    mov rbx, [rbx + page_node_t.next]
    jmp .node_loop

.next_gen:
    inc r13
    jmp .loop

.found:
    ; Unlink from generation R13 list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]

    test r8, r8
    jz .is_head
    mov [r8 + page_node_t.next], r9
    jmp .check_tail

.is_head:
    mov [sys_mglru_head + r13 * 8], r9

.check_tail:
    test r9, r9
    jz .is_tail
    mov [r9 + page_node_t.prev], r8
    jmp .done_unlink

.is_tail:
    mov [sys_mglru_tail + r13 * 8], r8

.done_unlink:
    dec qword [sys_mglru_count + r13 * 8]
    call replacement_lock_release

    ; Free node structure
    mov rdi, rbx
    call heap_free
    jmp .exit

.unlock_done:
    call replacement_lock_release
.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_mglru_move — moves a page to another generation
; Input: RDI = phys, RSI = target_gen
; -----------------------------------------------------------------------------
global virt_mglru_move
virt_mglru_move:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                    ; phys
    mov r13, rsi                    ; target_gen

    call replacement_lock_acquire

    ; Find page in generations
    xor r14, r14                    ; source gen
.loop:
    cmp r14, 4
    jae .unlock_done

    mov rbx, [sys_mglru_head + r14 * 8]
.node_loop:
    test rbx, rbx
    jz .next_gen
    cmp [rbx + page_node_t.phys_addr], r12
    je .found
    mov rbx, [rbx + page_node_t.next]
    jmp .node_loop

.next_gen:
    inc r14
    jmp .loop

.found:
    cmp r14, r13
    je .unlock_done                 ; already in target gen

    ; 1. Unlink from source gen list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]

    test r8, r8
    jz .is_head
    mov [r8 + page_node_t.next], r9
    jmp .check_tail

.is_head:
    mov [sys_mglru_head + r14 * 8], r9

.check_tail:
    test r9, r9
    jz .is_tail
    mov [r9 + page_node_t.prev], r8
    jmp .done_unlink

.is_tail:
    mov [sys_mglru_tail + r14 * 8], r8

.done_unlink:
    dec qword [sys_mglru_count + r14 * 8]

    ; 2. Prepend to target gen list
    mov [rbx + page_node_t.flags], r13     ; set new gen in flags
    mov qword [rbx + page_node_t.prev], 0
    mov rcx, [sys_mglru_head + r13 * 8]
    mov [rbx + page_node_t.next], rcx

    test rcx, rcx
    jz .first_node_target
    mov [rcx + page_node_t.prev], rbx
    mov [sys_mglru_head + r13 * 8], rbx
    jmp .done_link

.first_node_target:
    mov [sys_mglru_head + r13 * 8], rbx
    mov [sys_mglru_tail + r13 * 8], rbx

.done_link:
    inc qword [sys_mglru_count + r13 * 8]

.unlock_done:
    call replacement_lock_release
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_mglru_age — ages pages by shifting generations (Gen 3->2->1->0)
; -----------------------------------------------------------------------------
global virt_mglru_age
virt_mglru_age:
    push rbx
    push rcx
    push rdx

    call replacement_lock_acquire

    ; Shift Gen 1 to Gen 0:
    mov rbx, [sys_mglru_head + 1 * 8]
.loop1:
    test rbx, rbx
    jz .done1
    mov qword [rbx + page_node_t.flags], 0
    mov rcx, [rbx + page_node_t.next]
    test rcx, rcx
    jnz .next1

    ; Link tail of Gen 1 to head of Gen 0
    mov rdx, [sys_mglru_head + 0 * 8]
    mov [rbx + page_node_t.next], rdx
    test rdx, rdx
    jz .empty0
    mov [rdx + page_node_t.prev], rbx
    jmp .link0_done
.empty0:
    mov rdx, [sys_mglru_tail + 1 * 8]
    mov [sys_mglru_tail + 0 * 8], rdx
.link0_done:
    mov rdx, [sys_mglru_head + 1 * 8]
    mov [sys_mglru_head + 0 * 8], rdx

.next1:
    mov rbx, rcx
    jmp .loop1
.done1:
    mov qword [sys_mglru_head + 1 * 8], 0
    mov qword [sys_mglru_tail + 1 * 8], 0
    mov rax, [sys_mglru_count + 1 * 8]
    add [sys_mglru_count + 0 * 8], rax
    mov qword [sys_mglru_count + 1 * 8], 0

    ; Shift Gen 2 to Gen 1:
    mov rbx, [sys_mglru_head + 2 * 8]
.loop2:
    test rbx, rbx
    jz .done2
    mov qword [rbx + page_node_t.flags], 1
    mov rcx, [rbx + page_node_t.next]
    test rcx, rcx
    jnz .next2

    mov rdx, [sys_mglru_head + 1 * 8]
    mov [rbx + page_node_t.next], rdx
    test rdx, rdx
    jz .empty1
    mov [rdx + page_node_t.prev], rbx
    jmp .link1_done
.empty1:
    mov rdx, [sys_mglru_tail + 2 * 8]
    mov [sys_mglru_tail + 1 * 8], rdx
.link1_done:
    mov rdx, [sys_mglru_head + 2 * 8]
    mov [sys_mglru_head + 1 * 8], rdx
.next2:
    mov rbx, rcx
    jmp .loop2
.done2:
    mov qword [sys_mglru_head + 2 * 8], 0
    mov qword [sys_mglru_tail + 2 * 8], 0
    mov rax, [sys_mglru_count + 2 * 8]
    add [sys_mglru_count + 1 * 8], rax
    mov qword [sys_mglru_count + 2 * 8], 0

    ; Shift Gen 3 to Gen 2:
    mov rbx, [sys_mglru_head + 3 * 8]
.loop3:
    test rbx, rbx
    jz .done3
    mov qword [rbx + page_node_t.flags], 2
    mov rcx, [rbx + page_node_t.next]
    test rcx, rcx
    jnz .next3

    mov rdx, [sys_mglru_head + 2 * 8]
    mov [rbx + page_node_t.next], rdx
    test rdx, rdx
    jz .empty2
    mov [rdx + page_node_t.prev], rbx
    jmp .link2_done
.empty2:
    mov rdx, [sys_mglru_tail + 3 * 8]
    mov [sys_mglru_tail + 2 * 8], rdx
.link2_done:
    mov rdx, [sys_mglru_head + 3 * 8]
    mov [sys_mglru_head + 2 * 8], rdx
.next3:
    mov rbx, rcx
    jmp .loop3
.done3:
    mov qword [sys_mglru_head + 3 * 8], 0
    mov qword [sys_mglru_tail + 3 * 8], 0
    mov rax, [sys_mglru_count + 3 * 8]
    add [sys_mglru_count + 2 * 8], rax
    mov qword [sys_mglru_count + 3 * 8], 0

    inc qword [sys_mglru_ages]

    call replacement_lock_release
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_mglru_evict — page reclamation via Multi-Gen LRU
; Output: RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global virt_mglru_evict
virt_mglru_evict:
    push rbx
    push r12
    push r13
    push r14
    push r15

.try_reclaim:
    call replacement_lock_acquire

    ; Scan Gen 0 oldest list from tail to head
    mov rbx, [sys_mglru_tail + 0 * 8]
    test rbx, rbx
    jnz .scan_loop

    ; Gen 0 is empty! Run an aging step to shift generations 3->2->1->0
    call replacement_lock_release
    call virt_mglru_age
    call replacement_lock_acquire

    ; Re-check Gen 0 after aging
    mov rbx, [sys_mglru_tail + 0 * 8]
    test rbx, rbx
    jnz .scan_loop

    ; Still empty after aging (no pages mapped at all in MGLRU!)
    call replacement_lock_release
    xor rax, rax                    ; return 0 (failed to evict)
    jmp .exit

.scan_loop:
    test rbx, rbx
    jz .aging_needed

    mov r12, [rbx + page_node_t.prev] ; save prev pointer for tail->head traversal

    ; Check Accessed bit of Gen 0 page
    mov rdi, [rbx + page_node_t.virt_addr]
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE, RDX = level
    test rax, rax
    jz .unmapped_node

    mov rcx, [rax]
    test rcx, PAGE_ACCESSED
    jnz .promote_node               ; Accessed bit set, promote to Gen 3!

    ; Accessed is 0! Evict page to swap
    mov r13, rax                    ; PTE address
    mov r14, rcx                    ; PTE value
    mov r15, [rbx + page_node_t.phys_addr]

    call replacement_lock_release

    ; 1. Try Zswap first
    mov rdi, r15
    call zswap_compress_and_store
    cmp rax, -1
    je .fallback_disk_swap

    mov r10, rax                    ; Zswap slot
    mov r8, 1
    jmp .commit_eviction

.fallback_disk_swap:
    call swap_alloc_slot
    cmp rax, -1
    je .fail_swap_full

    mov r10, rax                    ; disk swap slot
    mov rdi, r15
    mov rsi, r10
    call swap_write_page
    mov r8, 0

.commit_eviction:
    call replacement_lock_acquire

    ; Verify PTE didn't change
    mov rdi, [rbx + page_node_t.virt_addr]
    xor rsi, rsi
    push r8
    push r10
    call virt_walk_table
    pop r10
    pop r8
    cmp rax, r13
    jne .abort_evict

    ; Write new PTE
    mov rcx, r14
    and rcx, 0xFFF                  ; lower flags
    mov r11, (1 << 63)
    and r11, r14
    or rcx, r11                     ; NX flag

    and rcx, ~PAGE_PRESENT
    and rcx, ~PAGE_ACCESSED
    or rcx, PAGE_SWAPPED

    test r8, r8
    jz .pte_flags_done
    or rcx, PAGE_ZSWAPPED
.pte_flags_done:

    mov r9, r10
    shl r9, 12
    or rcx, r9
    mov [r13], rcx

    invlpg [rdi]                    ; TLB flush

    ; Unlink from Gen 0
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .gen0_head
    mov [r8 + page_node_t.next], r9
    jmp .gen0_tail_check
.gen0_head:
    mov [sys_mglru_head + 0 * 8], r9
.gen0_tail_check:
    test r9, r9
    jz .gen0_tail
    mov [r9 + page_node_t.prev], r8
    jmp .gen0_done
.gen0_tail:
    mov [sys_mglru_tail + 0 * 8], r8
.gen0_done:
    dec qword [sys_mglru_count + 0 * 8]

    call replacement_lock_release

    ; Free physical page
    mov rdi, r15
    call phys_free_page

    ; Free node
    mov rdi, rbx
    call heap_free

    ; Telemetry
    inc qword [phys_state + phys_state_t.swap_pages]
    inc qword [sys_mglru_reclaims]

    mov rax, 1                      ; return 1 (success)
    jmp .exit

.promote_node:
    ; Page was accessed! Clear Accessed bit, promote to Gen 3
    and qword [rax], ~PAGE_ACCESSED
    invlpg [rdi]

    ; Unlink from Gen 0
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .prom_head
    mov [r8 + page_node_t.next], r9
    jmp .prom_tail_check
.prom_head:
    mov [sys_mglru_head + 0 * 8], r9
.prom_tail_check:
    test r9, r9
    jz .prom_tail
    mov [r9 + page_node_t.prev], r8
    jmp .prom_done
.prom_tail:
    mov [sys_mglru_tail + 0 * 8], r8
.prom_done:
    dec qword [sys_mglru_count + 0 * 8]

    ; Prepend to Gen 3
    mov qword [rbx + page_node_t.flags], 3 ; Gen 3
    mov qword [rbx + page_node_t.prev], 0
    mov rcx, [sys_mglru_head + 3 * 8]
    mov [rbx + page_node_t.next], rcx
    test rcx, rcx
    jz .prom_first
    mov [rcx + page_node_t.prev], rbx
    mov [sys_mglru_head + 3 * 8], rbx
    jmp .prom_linked
.prom_first:
    mov [sys_mglru_head + 3 * 8], rbx
    mov [sys_mglru_tail + 3 * 8], rbx
.prom_linked:
    inc qword [sys_mglru_count + 3 * 8]
    inc qword [sys_mglru_promotions]

    ; Move to next candidate in Gen 0
    mov rbx, r12
    jmp .scan_loop

.unmapped_node:
    ; Unlink and free unmapped node from Gen 0
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .unmap_head
    mov [r8 + page_node_t.next], r9
    jmp .unmap_tail_check
.unmap_head:
    mov [sys_mglru_head + 0 * 8], r9
.unmap_tail_check:
    test r9, r9
    jz .unmap_tail
    mov [r9 + page_node_t.prev], r8
    jmp .unmap_done
.unmap_tail:
    mov [sys_mglru_tail + 0 * 8], r8
.unmap_done:
    dec qword [sys_mglru_count + 0 * 8]

    call replacement_lock_release
    mov rdi, rbx
    call heap_free

    call replacement_lock_acquire
    mov rbx, r12
    jmp .scan_loop

.abort_evict:
    call replacement_lock_release
    mov rdi, r10
    test r8, r8
    jz .abort_disk_swap
    call zswap_free_slot
    jmp .abort_done
.abort_disk_swap:
    call swap_free_slot
.abort_done:
    call replacement_lock_acquire
    mov rbx, r12
    jmp .scan_loop

.fail_swap_full:
    call replacement_lock_acquire
.aging_needed:
    call replacement_lock_release
    call virt_mglru_age
    jmp .try_reclaim

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global sys_mglru_head
global sys_mglru_tail
global sys_mglru_count
global sys_mglru_enabled
global sys_mglru_promotions
global sys_mglru_reclaims
global sys_mglru_ages

sys_mglru_head:       times 4 dq 0
sys_mglru_tail:       times 4 dq 0
sys_mglru_count:      times 4 dq 0
sys_mglru_enabled:    dq 0            ; Disabled by default (toggled in tests)
sys_mglru_promotions: dq 0
sys_mglru_reclaims:   dq 0
sys_mglru_ages:       dq 0

%endif ; LIB_MEM_VIRT_MGLRU_ASM
