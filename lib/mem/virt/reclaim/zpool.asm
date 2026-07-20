; =============================================================================
; Tattva OS — lib/mem/virt/zpool.asm
; =============================================================================
; Balancing, Compaction, Writeback, and Parallel Batch Decompression (Section 28).
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

; LAPIC offsets
ZPOOL_LAPIC_BASE     equ 0xFEE00000
ZPOOL_LAPIC_ICR_LOW  equ 0x300
ZPOOL_LAPIC_EOI      equ 0x0B0
ZPOOL_DECOMP_VEC     equ 0xFA

; Batch request structure
struc zpool_decomp_req_t
    .src_addr     resq 1      ; Source address of compressed block
    .dest_addr    resq 1      ; Destination physical address of 4KB page
    .comp_size    resq 1      ; Compressed size in bytes
    .pool_type    resq 1      ; 0 = ZRAM (LZ4), 1 = Zswap (RLE)
    .status       resq 1      ; 0 = pending, 1 = success, 2 = failed
endstruc

zpool_decomp_req_t_size equ 40

section .text

; External helper functions


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
; -----------------------------------------------------------------------------
global zswap_writeback
zswap_writeback:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; 1. Find the oldest in-use slot in Zswap
    xor r12, r12
.find_loop:
    cmp r12, ZSWAP_MAX_SLOTS
    jge .failed
    lea rcx, [zswap_in_use]
    mov al, [rcx + r12]
    test al, al
    jnz .found_slot
    inc r12
    jmp .find_loop

.found_slot:
    ; r12 = S_old

    ; 2. Allocate physical swap slot
    call ram_swap_alloc_slot
    cmp rax, -1
    je .failed
    mov r13, rax                    ; r13 = physical disk slot

    ; 3. Allocate temporary page frame
    call phys_alloc_page
    test rax, rax
    jz .free_disk_slot
    mov r14, rax                    ; r14 = temp physical page

    ; 4. Decompress Zswap slot r12 into temp page r14
    mov rdi, r12
    mov rsi, r14
    call zswap_decompress_and_free
    test rax, rax
    jz .free_temp_page

    ; 5. Write data from temp page to physical swap slot r13
    mov rdi, r14
    mov rsi, r13
    call ram_swap_write_page

    ; 6. Update PTE to point from Zswap slot r12 to physical disk slot r13
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
    call ram_swap_alloc_slot
    cmp rax, -1
    je .failed
    mov r13, rax                    ; r13 = physical disk slot

    ; 3. Allocate temporary page frame
    call phys_alloc_page
    test rax, rax
    jz .free_disk_slot
    mov r14, rax                    ; r14 = temp physical page

    ; 4. Decompress ZRAM slot r12 into temp page r14
    mov rdi, r12
    mov rsi, r14
    call zram_read_page
    test rax, rax
    jz .free_temp_page

    ; 5. Write to physical swap slot r13
    mov rdi, r14
    mov rsi, r13
    call ram_swap_write_page

    ; 6. Update PTE from ZRAM slot r12 to physical disk slot r13
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

; -----------------------------------------------------------------------------
; zpool_decomp_worker_loop — processes pending decompression requests in the ring
; -----------------------------------------------------------------------------
zpool_decomp_worker_loop:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8

.get_work:
    mov rax, [zpool_decomp_head]
    mov rbx, [zpool_decomp_tail]
    cmp rax, rbx
    jge .no_more_work               ; head >= tail, all work done!
    
    ; Try to claim the request at RAX by atomically incrementing head
    mov rcx, rax
    inc rcx
    lock cmpxchg [zpool_decomp_head], rcx
    jnz .get_work                   ; if CAS failed, retry
    
    ; CAS succeeded! RAX contains the index of the request we claimed.
    ; offset = rax % 16
    and rax, 15                     ; RAX = ring index (0..15)
    imul rax, zpool_decomp_req_t_size
    lea r8, [zpool_decomp_ring + rax]
    
    ; Extract fields
    mov rdi, [r8 + zpool_decomp_req_t.src_addr]
    mov rsi, [r8 + zpool_decomp_req_t.dest_addr]
    mov rdx, [r8 + zpool_decomp_req_t.comp_size]
    mov rcx, [r8 + zpool_decomp_req_t.pool_type]
    
    ; Decompress
    cmp rcx, 1                      ; 1 = Zswap
    je .do_zswap
    
    ; ZRAM (LZ4)
    call lz4_decompress
    test rax, rax
    jz .decomp_fail
    mov qword [r8 + zpool_decomp_req_t.status], 1
    jmp .get_work
    
.do_zswap:
    call rle_decompress
    test rax, rax
    jz .decomp_fail
    mov qword [r8 + zpool_decomp_req_t.status], 1
    jmp .get_work
    
.decomp_fail:
    mov qword [r8 + zpool_decomp_req_t.status], 2 ; failed
    jmp .get_work
    
.no_more_work:
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zpool_batch_decompress_submit — submits batch of requests and triggers IPI
; Input:
;   RDI = array of pointers to zpool_decomp_req_t structures
;   RSI = count of requests (max 16)
; Output: RAX = number of successfully decompressed pages
; -----------------------------------------------------------------------------
global zpool_batch_decompress_submit
zpool_batch_decompress_submit:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov r12, rdi                    ; r12 = array pointer
    mov r13, rsi                    ; r13 = count

    ; Limit check count (max 16)
    cmp r13, 16
    jg .err
    test r13, r13
    jz .err

    ; Reset cursors
    mov qword [zpool_decomp_head], 0
    mov qword [zpool_decomp_tail], r13

    ; Copy requests to the ring
    xor rcx, rcx                    ; rcx = index (0..count-1)
.copy_loop:
    cmp rcx, r13
    jge .copy_done
    
    mov rdi, [r12 + rcx * 8]        ; RDI = source request pointer
    
    mov rax, rcx
    and rax, 15                     ; wrap index
    imul rax, zpool_decomp_req_t_size
    lea rsi, [zpool_decomp_ring + rax] ; RSI = target ring entry
    
    ; Copy fields (5 quadwords = 40 bytes)
    mov rdx, [rdi + zpool_decomp_req_t.src_addr]
    mov [rsi + zpool_decomp_req_t.src_addr], rdx
    
    mov rdx, [rdi + zpool_decomp_req_t.dest_addr]
    mov [rsi + zpool_decomp_req_t.dest_addr], rdx
    
    mov rdx, [rdi + zpool_decomp_req_t.comp_size]
    mov [rsi + zpool_decomp_req_t.comp_size], rdx
    
    mov rdx, [rdi + zpool_decomp_req_t.pool_type]
    mov [rsi + zpool_decomp_req_t.pool_type], rdx
    
    ; Mark status as pending
    mov qword [rsi + zpool_decomp_req_t.status], 0
    
    inc rcx
    jmp .copy_loop

.copy_done:
    ; Memory fence to make sure ring contents are visible before starting execution
    mfence

    ; If smp_active_cores > 1, send decompression IPI to all excluding self
    mov eax, [smp_active_cores]
    cmp eax, 1
    jle .local_only

    ; Send fixed vector IPI 0xFA to all excluding self
    mov eax, 0x000C4000 | ZPOOL_DECOMP_VEC
    mov r11, ZPOOL_LAPIC_BASE
    mov dword [r11 + ZPOOL_LAPIC_ICR_LOW], eax

.local_only:
    ; BSP also participates in processing work
    call zpool_decomp_worker_loop

    ; Spin-wait until all requests are completed (status != 0)
    xor rcx, rcx                    ; rcx = index
.wait_loop:
    cmp rcx, r13
    jge .wait_done
    
    mov rax, rcx
    and rax, 15
    imul rax, zpool_decomp_req_t_size
    lea rsi, [zpool_decomp_ring + rax]
    
    mov rax, [rsi + zpool_decomp_req_t.status]
    test rax, rax
    jz .wait_loop                   ; spin-wait if still pending
    
    inc rcx
    jmp .wait_loop

.wait_done:
    ; Count successful requests (status == 1)
    xor r14, r14                    ; success count
    xor rcx, rcx
.count_loop:
    cmp rcx, r13
    jge .count_done
    
    mov rax, rcx
    and rax, 15
    imul rax, zpool_decomp_req_t_size
    lea rsi, [zpool_decomp_ring + rax]
    
    mov rax, [rsi + zpool_decomp_req_t.status]
    cmp rax, 1
    jne .count_next
    inc r14
.count_next:
    inc rcx
    jmp .count_loop

.count_done:
    mov rax, r14                    ; return success count
    jmp .exit

.err:
    xor rax, rax

.exit:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zpool_decomp_isr — ISR handler for decompression vector 0xFA on APs
; -----------------------------------------------------------------------------
global zpool_decomp_isr
zpool_decomp_isr:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    ; Participate in work processing
    call zpool_decomp_worker_loop

    ; Send EOI to LAPIC
    mov r11, ZPOOL_LAPIC_BASE
    mov dword [r11 + ZPOOL_LAPIC_EOI], 0

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    iretq

section .data

global zswap_max_slots
global zram_max_slots

align 8
zswap_max_slots: dq 256
zram_max_slots:  dq 256

section .bss
align 8
zpool_decomp_head: resq 1
zpool_decomp_tail: resq 1
align 16
zpool_decomp_ring: resb (16 * zpool_decomp_req_t_size)

%endif ; LIB_MEM_VIRT_ZPOOL_ASM
