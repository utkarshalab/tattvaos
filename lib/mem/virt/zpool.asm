; =============================================================================
; Tattva OS — lib/mem/virt/zpool.asm
; =============================================================================
; Dynamic Zpool Balancing, Compaction, and Writeback (Section 28.2 - 28.4).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ZPOOL_ASM
%define LIB_MEM_VIRT_ZPOOL_ASM

[BITS 64]

; Zpool/Zswap limits
ZRAM_MAX_SLOTS    equ 256
ZRAM_SLOT_SIZE    equ 2048
ZSWAP_MAX_SLOTS   equ 256
ZSWAP_SLOT_SIZE   equ 2048

section .text

; External helper functions
extern phys_state
extern phys_alloc_page
extern phys_free_page
extern memcpy

; Physical disk swap functions (mock RAM swap helpers)
extern ram_swap_alloc_slot
extern ram_swap_free_slot
extern ram_swap_write_page

; Pool specific decompressors/readers
extern zswap_decompress_and_free
extern zram_read_page

; -----------------------------------------------------------------------------
; zpool_balance — dynamically scales zswap and zram maximum slots
;                  based on free physical memory levels.
; -----------------------------------------------------------------------------
global zpool_balance
zpool_balance:
    push rax
    push rcx
    push rdx

    ; Calculate: percentage = (phys_state.free_pages * 100) / phys_state.total_pages
    mov rax, [phys_state + phys_state_t.free_pages]
    imul rax, 100
    mov rcx, [phys_state + phys_state_t.total_pages]
    test rcx, rcx
    jz .fallback

    xor rdx, rdx
    div rcx                     ; RAX = free percentage (0-100)

    ; Scale compression pools based on free memory percentage:
    ; - free memory > 50%: 100% capacity (256 slots)
    ; - 20% < free memory <= 50%: 50% capacity (128 slots)
    ; - free memory <= 20%: 25% capacity (64 slots)
    cmp rax, 50
    ja .high_mem

    cmp rax, 20
    ja .mid_mem

.low_mem:
    mov qword [zswap_max_slots], 64
    mov qword [zram_max_slots], 64
    jmp .done

.mid_mem:
    mov qword [zswap_max_slots], 128
    mov qword [zram_max_slots], 128
    jmp .done

.high_mem:
.fallback:
    mov qword [zswap_max_slots], 256
    mov qword [zram_max_slots], 256

.done:
    pop rdx
    pop rcx
    pop rax
    ret

; -----------------------------------------------------------------------------
; zpool_update_pte — scans page tables to update slot index for swapped pages
; Input:
;   RDI = slot_src
;   RSI = slot_dest
;   RDX = is_zswap (1 = zswap, 0 = zram)
; Output: none
; -----------------------------------------------------------------------------
global zpool_update_pte
zpool_update_pte:
    push rbp
    mov rbp, rsp
    sub rsp, 64                     ; reserve stack space

    ; Save inputs
    mov [rbp - 8], rdi              ; slot_src
    mov [rbp - 16], rsi             ; slot_dest
    mov [rbp - 24], rdx             ; is_zswap

    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Get PML4 physical base from CR3
    mov rax, cr3
    mov rbx, 0xFFFFFFFFFFFFF000
    and rax, rbx
    mov [rbp - 32], rax             ; PML4 base

    ; Loop PML4 index (0..511)
    xor r12, r12
.pml4_loop:
    cmp r12, 512
    jge .done
    
    mov rax, [rbp - 32]
    mov rax, [rax + r12 * 8]        ; PML4 entry
    test rax, 1                     ; PAGE_PRESENT
    jz .pml4_next

    and rax, 0xFFFFFFFFFFFFF000
    mov [rbp - 40], rax             ; PDPT base

    ; Loop PDPT index (0..511)
    xor r13, r13
.pdpt_loop:
    cmp r13, 512
    jge .pml4_next

    mov rax, [rbp - 40]
    mov rax, [rax + r13 * 8]        ; PDPT entry
    test rax, 1                     ; PAGE_PRESENT
    jz .pdpt_next
    test rax, 0x80                  ; PAGE_HUGE
    jnz .pdpt_next

    and rax, 0xFFFFFFFFFFFFF000
    mov [rbp - 48], rax             ; PD base

    ; Loop PD index (0..511)
    xor r14, r14
.pd_loop:
    cmp r14, 512
    jge .pdpt_next

    mov rax, [rbp - 48]
    mov rax, [rax + r14 * 8]        ; PD entry
    test rax, 1                     ; PAGE_PRESENT
    jz .pd_next
    test rax, 0x80                  ; PAGE_HUGE
    jnz .pd_next

    and rax, 0xFFFFFFFFFFFFF000
    mov [rbp - 56], rax             ; PT base

    ; Loop PT index (0..511)
    xor r15, r15
.pt_loop:
    cmp r15, 512
    jge .pd_next

    mov rax, [rbp - 56]
    lea rdx, [rax + r15 * 8]        ; RDX = PTE pointer
    mov rax, [rdx]                  ; RAX = PTE value
    test rax, 1                     ; PAGE_PRESENT (must be non-present)
    jnz .pt_next

    ; Check PAGE_SWAPPED (bit 10)
    test rax, 0x400
    jz .pt_next

    ; Check is_zswap flag (bit 11)
    mov rcx, rax
    shr rcx, 11
    and rcx, 1                      ; RCX = is_zswap in PTE
    cmp rcx, [rbp - 24]
    jne .pt_next

    ; Extract slot index (bits 12-51)
    mov rcx, rax
    shr rcx, 12
    mov r8, 0xFFFFFFFFFF
    and rcx, r8                     ; RCX = slot index in PTE
    cmp rcx, [rbp - 8]
    jne .pt_next

    ; Match found! Update PTE with slot_dest
    mov r8, 0xFFFFFFFFFF
    shl r8, 12
    not r8
    and rax, r8                     ; clear old slot bits 12-51

    ; Clear PAGE_ZSWAPPED (bit 11) and PAGE_ZRAM (bit 8) to convert to disk swap format
    and rax, ~(0x800 | 0x100)

    mov rcx, [rbp - 16]             ; slot_dest
    shl rcx, 12
    or rax, rcx                     ; merge new slot index

    mov [rdx], rax                  ; write new PTE
    
    ; Flush TLB
    mov rcx, cr3
    mov cr3, rcx
    jmp .done                       ; slot index is unique, we are done!

.pt_next:
    inc r15
    jmp .pt_loop

.pd_next:
    inc r14
    jmp .pd_loop

.pdpt_next:
    inc r13
    jmp .pdpt_loop

.pml4_next:
    inc r12
    jmp .pml4_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; zram_compact — eliminates memory fragmentation in ZRAM pool
; -----------------------------------------------------------------------------
global zram_compact
zram_compact:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    xor r12, r12                    ; r12 = L (left index)
    mov r13, ZRAM_MAX_SLOTS
    dec r13                         ; r13 = R (right index)

.compact_loop:
    cmp r12, r13
    jge .done

    ; Find first free slot from left
    lea rcx, [zram_in_use]
    mov al, [rcx + r12]
    test al, al
    jz .found_free
    inc r12
    jmp .compact_loop

.found_free:
    ; Find first in-use slot from right
    lea rcx, [zram_in_use]
    mov al, [rcx + r13]
    test al, al
    jnz .found_in_use
    dec r13
    jmp .compact_loop

.found_in_use:
    cmp r12, r13
    jge .done

    ; Migrate slot R (r13) to L (r12)
    ; 1. Resolve source address
    mov rax, r13
    shr rax, 1                      ; F_src
    lea rcx, [zram_frames]
    mov rbx, [rcx + rax * 8]
    
    mov rdx, r13
    and rdx, 1
    shl rdx, 11                     ; O_src offset
    add rbx, rdx                    ; RBX = source pointer

    ; 2. Resolve destination address. Allocate frame if needed
    mov rax, r12
    shr rax, 1                      ; F_dest
    lea rcx, [zram_frames]
    mov rbp, [rcx + rax * 8]
    test rbp, rbp
    jnz .dest_frame_ok

    push rcx
    push rax
    call phys_alloc_page
    pop rax
    pop rcx
    test rax, rax
    jz .done                        ; abort if OOM

    mov [rcx + rax * 8], rax
    mov rbp, rax

.dest_frame_ok:
    mov rdx, r12
    and rdx, 1
    shl rdx, 11
    add rbp, rdx                    ; RBP = destination pointer

    ; 3. Copy slot contents (2048 bytes)
    mov rdi, rbp
    mov rsi, rbx
    mov rdx, ZRAM_SLOT_SIZE
    call memcpy

    ; 4. Copy metadata
    lea rcx, [zram_in_use]
    mov byte [rcx + r12], 1         ; mark L in use
    
    lea rcx, [zram_sizes]
    mov dx, [rcx + r13 * 2]         ; get size of R
    mov [rcx + r12 * 2], dx         ; set size of L

    ; 5. Update PTE mapping from R to L
    mov rdi, r13                    ; slot_src
    mov rsi, r12                    ; slot_dest
    mov rdx, 0                      ; is_zswap = 0
    call zpool_update_pte

    ; 6. Free source slot R (r13)
    lea rcx, [zram_in_use]
    mov byte [rcx + r13], 0
    lea rcx, [zram_sizes]
    mov word [rcx + r13 * 2], 0

    ; Check companion slot of R (R ^ 1)
    mov rax, r13
    xor rax, 1
    lea rcx, [zram_in_use]
    mov dl, [rcx + rax]
    test dl, dl
    jnz .skip_free_source_frame

    ; Companion is free, release physical frame
    mov rax, r13
    shr rax, 1                      ; F_src
    lea rcx, [zram_frames]
    mov rdi, [rcx + rax * 8]
    test rdi, rdi
    jz .skip_free_source_frame

    call phys_free_page
    lea rcx, [zram_frames]
    mov qword [rcx + rax * 8], 0

.skip_free_source_frame:
    inc r12
    dec r13
    jmp .compact_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zswap_compact — eliminates memory fragmentation in Zswap pool
; -----------------------------------------------------------------------------
global zswap_compact
zswap_compact:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    xor r12, r12                    ; r12 = L (left index)
    mov r13, ZSWAP_MAX_SLOTS
    dec r13                         ; r13 = R (right index)

.compact_loop:
    cmp r12, r13
    jge .done

    ; Find first free slot from left
    lea rcx, [zswap_in_use]
    mov al, [rcx + r12]
    test al, al
    jz .found_free
    inc r12
    jmp .compact_loop

.found_free:
    ; Find first in-use slot from right
    lea rcx, [zswap_in_use]
    mov al, [rcx + r13]
    test al, al
    jnz .found_in_use
    dec r13
    jmp .compact_loop

.found_in_use:
    cmp r12, r13
    jge .done

    ; Migrate slot R (r13) to L (r12)
    ; 1. Resolve source address
    mov rax, r13
    shr rax, 1                      ; F_src
    lea rcx, [zswap_frames]
    mov rbx, [rcx + rax * 8]
    
    mov rdx, r13
    and rdx, 1
    shl rdx, 11                     ; O_src offset
    add rbx, rdx                    ; RBX = source pointer

    ; 2. Resolve destination address. Allocate frame if needed
    mov rax, r12
    shr rax, 1                      ; F_dest
    lea rcx, [zswap_frames]
    mov rbp, [rcx + rax * 8]
    test rbp, rbp
    jnz .dest_frame_ok

    push rcx
    push rax
    call phys_alloc_page
    pop rax
    pop rcx
    test rax, rax
    jz .done                        ; abort if OOM

    mov [rcx + rax * 8], rax
    mov rbp, rax

.dest_frame_ok:
    mov rdx, r12
    and rdx, 1
    shl rdx, 11
    add rbp, rdx                    ; RBP = destination pointer

    ; 3. Copy slot contents (2048 bytes)
    mov rdi, rbp
    mov rsi, rbx
    mov rdx, ZSWAP_SLOT_SIZE
    call memcpy

    ; 4. Copy metadata
    lea rcx, [zswap_in_use]
    mov byte [rcx + r12], 1         ; mark L in use
    
    lea rcx, [zswap_sizes]
    mov dx, [rcx + r13 * 2]         ; get size of R
    mov [rcx + r12 * 2], dx         ; set size of L

    ; 5. Update PTE mapping from R to L
    mov rdi, r13                    ; slot_src
    mov rsi, r12                    ; slot_dest
    mov rdx, 1                      ; is_zswap = 1
    call zpool_update_pte

    ; 6. Free source slot R (r13)
    lea rcx, [zswap_in_use]
    mov byte [rcx + r13], 0
    lea rcx, [zswap_sizes]
    mov word [rcx + r13 * 2], 0

    ; Check companion slot of R (R ^ 1)
    mov rax, r13
    xor rax, 1
    lea rcx, [zswap_in_use]
    mov dl, [rcx + rax]
    test dl, dl
    jnz .skip_free_source_frame

    ; Companion is free, release physical frame
    mov rax, r13
    shr rax, 1                      ; F_src
    lea rcx, [zswap_frames]
    mov rdi, [rcx + rax * 8]
    test rdi, rdi
    jz .skip_free_source_frame

    call phys_free_page
    lea rcx, [zswap_frames]
    mov qword [rcx + rax * 8], 0

.skip_free_source_frame:
    inc r12
    dec r13
    jmp .compact_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zswap_writeback — evicts the oldest Zswap page to physical disk swap
; Output: RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global zswap_writeback
zswap_writeback:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; 1. Find the oldest in-use slot in Zswap (scan zswap_in_use from 0)
    xor r12, r12                    ; r12 = slot index
.find_loop:
    cmp r12, ZSWAP_MAX_SLOTS
    jge .failed
    lea rcx, [zswap_in_use]
    mov al, [rcx + r12]
    test al, al
    jnz .found_slot                 ; found oldest in-use slot!
    inc r12
    jmp .find_loop

.found_slot:
    ; r12 = S_old (source slot index)

    ; 2. Allocate a physical swap slot
    call ram_swap_alloc_slot        ; RAX = physical disk slot, or -1
    cmp rax, -1
    je .failed
    mov r13, rax                    ; r13 = physical disk slot

    ; 3. Allocate a temporary page frame
    call phys_alloc_page            ; RAX = temp physical page, or 0
    test rax, rax
    jz .free_disk_slot
    mov r14, rax                    ; r14 = temp physical page

    ; 4. Decompress Zswap slot r12 into temp page r14
    ; zswap_decompress_and_free(slot_index=r12, dest_phys=r14)
    mov rdi, r12
    mov rsi, r14
    call zswap_decompress_and_free  ; RAX = 1 on success, 0 on failure
    test rax, rax
    jz .free_temp_page

    ; 5. Write data from temp page to physical swap slot r13
    ; ram_swap_write_page(src_phys=r14, slot=r13)
    mov rdi, r14
    mov rsi, r13
    call ram_swap_write_page

    ; 6. Update PTE to point from Zswap slot r12 to physical disk slot r13
    ; zpool_update_pte(slot_src=r12, slot_dest=r13, is_zswap=1)
    mov rdi, r12
    mov rsi, r13
    mov rdx, 1                      ; is_zswap = 1
    call zpool_update_pte

    ; Free temporary page
    mov rdi, r14
    call phys_free_page

    mov rax, 1                      ; success!
    jmp .done

.free_temp_page:
    mov rdi, r14
    call phys_free_page
.free_disk_slot:
    mov rdi, r13
    call ram_swap_free_slot
.failed:
    xor rax, rax                    ; fail

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zram_writeback — evicts the oldest ZRAM page to physical disk swap
; Input: RDI = current slot index (to skip / avoid evicting same slot)
; Output: RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global zram_writeback
zram_writeback:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r15, rdi                    ; r15 = current slot index to skip

    ; 1. Find oldest in-use slot in ZRAM
    xor r12, r12
.find_loop:
    cmp r12, ZRAM_MAX_SLOTS
    jge .failed
    cmp r12, r15                    ; skip current slot index
    je .skip_current
    lea rcx, [zram_in_use]
    mov al, [rcx + r12]
    test al, al
    jnz .found_slot
.skip_current:
    inc r12
    jmp .find_loop

.found_slot:
    ; r12 = S_old

    ; 2. Allocate a physical swap slot
    call ram_swap_alloc_slot        ; RAX = physical disk slot
    cmp rax, -1
    je .failed
    mov r13, rax                    ; r13 = physical disk slot

    ; 3. Allocate temporary page frame
    call phys_alloc_page
    test rax, rax
    jz .free_disk_slot
    mov r14, rax                    ; r14 = temp physical page

    ; 4. Decompress ZRAM slot r12 into temp page r14
    ; zram_read_page(slot_index=r12, dest_phys=r14)
    mov rdi, r12
    mov rsi, r14
    call zram_read_page             ; RAX = 1 on success, 0 on failure
    test rax, rax
    jz .free_temp_page

    ; 5. Write to physical swap slot r13
    mov rdi, r14
    mov rsi, r13
    call ram_swap_write_page

    ; 6. Update PTE from ZRAM slot r12 to physical disk slot r13
    ; zpool_update_pte(slot_src=r12, slot_dest=r13, is_zswap=0)
    mov rdi, r12
    mov rsi, r13
    mov rdx, 0                      ; is_zswap = 0 (ZRAM)
    call zpool_update_pte

    ; Free temporary page
    mov rdi, r14
    call phys_free_page

    mov rax, 1                      ; success!
    jmp .done

.free_temp_page:
    mov rdi, r14
    call phys_free_page
.free_disk_slot:
    mov rdi, r13
    call ram_swap_free_slot
.failed:
    xor rax, rax                    ; fail

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .data

global zswap_max_slots
global zram_max_slots

align 8
zswap_max_slots: dq 256
zram_max_slots:  dq 256

%endif ; LIB_MEM_VIRT_ZPOOL_ASM
