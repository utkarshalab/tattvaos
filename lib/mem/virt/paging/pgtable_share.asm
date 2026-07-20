; =============================================================================
; Tattva OS — lib/mem/virt/paging/pgtable_share.asm
; =============================================================================
; Multi-Process Page Table Sharing (Part 1).
; Allows distinct processes to share intermediate page table directories (PT pages)
; for large read-only segments to minimize page table memory overhead.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_SHARE_ASM
%define LIB_MEM_VIRT_PGTABLE_SHARE_ASM

[BITS 64]

; Struct definition for shared page table directory tracking descriptor
struc shared_dir_desc_t
    .phys_addr:    resq 1  ; Physical address of the shared PT page
    .ref_count:    resq 1  ; Reference count (active processes sharing this PT)
    .lock:         resq 1  ; Quad-aligned spinlock flag (0 = free, 1 = busy)
endstruc

section .text



; -----------------------------------------------------------------------------
; virt_share_page_directories — shares page table (PT) pages from source to dest
; Input:
;   RDI = target_pml4_addr (virtual address of destination PML4)
;   RSI = source_pml4_addr (virtual address of source PML4)
;   RDX = start_vaddr      (start of shared address space, aligned to 2MB boundary)
;   RCX = size             (byte size to share, multiple of 2MB)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R15
; -----------------------------------------------------------------------------
global virt_share_page_directories
virt_share_page_directories:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi                    ; R12 = dest PML4 virtual address
    mov r13, rsi                    ; R13 = source PML4 virtual address
    mov r14, rdx                    ; R14 = start virtual address (current loop pointer)
    
    ; Calculate end address
    mov r15, rdx
    add r15, rcx                    ; R15 = end virtual address (exclusive)

.share_loop:
    ; Compare current pointer with end address
    cmp r14, r15
    jae .success

    ; -------------------------------------------------------------------------
    ; 1. Walk Source PML4 to find the Page Table (PT) physical page address
    ; -------------------------------------------------------------------------
    ; PML4 Index
    mov rax, r14
    shr rax, 39
    and rax, 0x1FF                  ; RAX = logical PML4 index
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]  ; RAX = physical shuffled PML4 index
    
    mov rbx, [r13 + rax * 8]        ; RBX = PML4 Entry
    test rbx, 0x01                  ; Present?
    jz .fail

    ; PDPT Index
    and rbx, 0xFFFFFFFFFFFFF000     ; RBX = physical PDPT address
    mov rax, r14
    shr rax, 30
    and rax, 0x1FF                  ; RAX = PDPT index
    mov r8, [rbx + rax * 8]         ; R8 = PDPT Entry
    test r8, 0x01                  ; Present?
    jz .fail
    test r8, 0x80                  ; Huge/Super 1GB Page? (We don't share at 1GB level here)
    jnz .fail

    ; PD (PMD) Index
    and r8, 0xFFFFFFFFFFFFF000      ; R8 = physical PD address
    mov rax, r14
    shr rax, 21
    and rax, 0x1FF                  ; RAX = PD index
    mov r9, [r8 + rax * 8]          ; R9 = PD Entry (pointing to PT page)
    test r9, 0x01                  ; Present?
    jz .fail
    test r9, 0x80                  ; Huge 2MB Page? (We can only share a PT page directory)
    jnz .fail

    ; Clean target physical address of the PT page
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = physical address of the shared PT page

    ; -------------------------------------------------------------------------
    ; 2. Register/Lock PT Page in the shared descriptor table
    ; -------------------------------------------------------------------------
    call ._get_or_create_shared_desc ; RAX = pointer to shared_dir_desc_t, CF=1 on success
    jnc .fail
    mov rbp, rax                    ; RBP = pointer to shared_dir_desc_t

    ; -------------------------------------------------------------------------
    ; 3. Walk Destination PML4 and map the shared PT page
    ; -------------------------------------------------------------------------
    ; PML4 Index for Dest
    mov rax, r14
    shr rax, 39
    and rax, 0x1FF
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]
    
    mov rbx, [r12 + rax * 8]
    test rbx, 0x01                  ; Present?
    jnz .have_dest_pdpt

    ; Allocate missing PDPT
    push rax
    call virt_pgtable_share_alloc_zeroed
    pop rcx
    test rax, rax
    jz .fail_unlock
    
    mov rbx, rax
    or rbx, 0x07                    ; Present | Writable | User
    mov [r12 + rcx * 8], rbx
    
.have_dest_pdpt:
    ; PDPT Index for Dest
    and rbx, 0xFFFFFFFFFFFFF000
    mov rax, r14
    shr rax, 30
    and rax, 0x1FF
    mov r8, [rbx + rax * 8]
    test r8, 0x01
    jnz .have_dest_pd

    ; Allocate missing PD
    push rbx
    push rax
    push rcx
    call virt_pgtable_share_alloc_zeroed
    pop rcx
    pop rdx
    pop rbx
    test rax, rax
    jz .fail_unlock
    
    mov r8, rax
    or r8, 0x07                    ; Present | Writable | User
    mov [rbx + rcx * 8], r8

.have_dest_pd:
    ; PD Index for Dest
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, r14
    shr rax, 21
    and rax, 0x1FF                  ; RAX = PD index
    
    ; Write the shared page table pointer to the destination's PMD entry
    ; Enforce read-only sharing: Present=1, R/W=0, User=1, Global=1
    mov rdx, [rbp + shared_dir_desc_t.phys_addr] ; shared PT page physical address (r9 may be clobbered by allocations)
    or rdx, 0x105                   ; Present | User | Global (No R/W)
    mov [r8 + rax * 8], rdx         ; Write PMD entry

    ; Invalidate TLB for the 2MB range
    invlpg [r14]

    ; Release spinlock on descriptor
    mov qword [rbp + shared_dir_desc_t.lock], 0

    ; Advance virtual address by 2MB (0x200000)
    add r14, 0x200000
    jmp .share_loop

.success:
    mov rax, 1
    jmp .exit

.fail_unlock:
    ; Release spinlock on descriptor if locked
    test rbp, rbp
    jz .fail
    mov qword [rbp + shared_dir_desc_t.lock], 0

.fail:
    xor rax, rax

.exit:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; .get_or_create_shared_desc — Finds or allocates a shared descriptor
; Input:
;   R9 = physical address of the page table page
; Output:
;   RAX = pointer to shared_dir_desc_t
;   CF = 1 on success, 0 on failure (table full)
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
._get_or_create_shared_desc:
    lea rdx, [shared_dir_table]
    xor rcx, rcx                    ; rcx = index

.search_existing:
    cmp rcx, 128
    jge .find_empty_slot
    
    mov rax, rcx
    imul rax, shared_dir_desc_t_size
    add rax, rdx
    cmp [rax + shared_dir_desc_t.phys_addr], r9
    jne .next_existing

    ; Found existing mapping! Acquire spinlock
.lock_existing:
    mov r10, 1
    lock xchg [rax + shared_dir_desc_t.lock], r10
    test r10, r10
    jz .acquired_existing
    pause
    jmp .lock_existing

.acquired_existing:
    ; Double check if phys_addr was cleared while spinning
    cmp [rax + shared_dir_desc_t.phys_addr], r9
    je .increment_existing
    ; It was cleared, release and look again
    mov qword [rax + shared_dir_desc_t.lock], 0
    jmp .search_existing

.increment_existing:
    ; Increment ref count atomically
    lock inc qword [rax + shared_dir_desc_t.ref_count]
    stc                             ; CF = 1 (success)
    ret

.next_existing:
    inc rcx
    jmp .search_existing

.find_empty_slot:
    xor rcx, rcx
.search_empty:
    cmp rcx, 128
    jge .table_full
    
    mov rax, rcx
    imul rax, shared_dir_desc_t_size
    add rax, rdx
    cmp qword [rax + shared_dir_desc_t.phys_addr], 0
    jne .next_empty

    ; Found empty slot! Try locking it with CAS
    xor r10, r10
    mov r11, 1
    lock cmpxchg [rax + shared_dir_desc_t.lock], r11
    jnz .next_empty                 ; lock failed, someone else got it

    ; Lock acquired, double check if it is still empty
    cmp qword [rax + shared_dir_desc_t.phys_addr], 0
    jne .unlock_and_next            ; slot filled while locking

    ; Initialize the descriptor
    mov [rax + shared_dir_desc_t.phys_addr], r9
    mov qword [rax + shared_dir_desc_t.ref_count], 2 ; Source + Dest = 2
    stc
    ret

.unlock_and_next:
    mov qword [rax + shared_dir_desc_t.lock], 0
.next_empty:
    inc rcx
    jmp .search_empty

.table_full:
    clc                             ; CF = 0 (failure)
    ret

; -----------------------------------------------------------------------------
; virt_shared_page_release — decrements refcount of a shared page table page
; Input:
;   RDI = physical address of the page table page to release
; Output:
;   RAX = 1 if page is still shared and should NOT be freed
;   RAX = 0 if page is safe to free
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global virt_shared_page_release
virt_shared_page_release:
    lea rdx, [shared_dir_table]
    xor rcx, rcx

.find_loop:
    cmp rcx, 128
    jge .not_found
    
    mov rax, rcx
    imul rax, shared_dir_desc_t_size
    add rax, rdx
    cmp [rax + shared_dir_desc_t.phys_addr], rdi
    je .lock_found
    
    inc rcx
    jmp .find_loop

.lock_found:
    ; Acquire spinlock
.lock_spin:
    mov r10, 1
    lock xchg [rax + shared_dir_desc_t.lock], r10
    test r10, r10
    jz .acquired
    pause
    jmp .lock_spin

.acquired:
    ; Verify it didn't change under us
    cmp [rax + shared_dir_desc_t.phys_addr], rdi
    jne .lock_spin_fail

    ; Decrement reference count
    mov r10, [rax + shared_dir_desc_t.ref_count]
    dec r10
    mov [rax + shared_dir_desc_t.ref_count], r10
    
    test r10, r10
    jg .still_shared

    ; Ref count is 0, clear descriptor
    mov qword [rax + shared_dir_desc_t.phys_addr], 0
    mov qword [rax + shared_dir_desc_t.lock], 0
    xor rax, rax                    ; return 0 (safe to free)
    ret

.still_shared:
    mov qword [rax + shared_dir_desc_t.lock], 0
    mov rax, 1                      ; return 1 (still shared, do not free)
    ret

.lock_spin_fail:
    mov qword [rax + shared_dir_desc_t.lock], 0
    jmp .find_loop

.not_found:
    xor rax, rax                    ; return 0 (not registered, safe to free)
    ret

virt_pgtable_share_alloc_zeroed:
    call phys_alloc_page
    test rax, rax
    jz .alloc_exit
    
    push rax
    mov rdi, rax
    mov rsi, 4096
    call memzero
    pop rax
.alloc_exit:
    ret

; -----------------------------------------------------------------------------
; Data — Shared directory descriptors
; -----------------------------------------------------------------------------
section .bss
align 8
global shared_dir_table
shared_dir_table: resb shared_dir_desc_t_size * 128

%endif ; LIB_MEM_VIRT_PGTABLE_SHARE_ASM
