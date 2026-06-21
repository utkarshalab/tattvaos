; =============================================================================
; Tattva OS — lib/mem/virt/rt_reserve.asm
; =============================================================================
; Physical Memory Reservation — Subfeature 37.5.
;
; Reserves N megabytes of physical RAM at boot time. Excludes these physical
; frames from the general-purpose allocator lists to guarantee their availability
; for critical inference workloads and prevent starvation under general system load.
;
; Keeps track of up to 4096 reserved physical pages (16MB capacity).
;
; API:
;   rt_reserve_boot_memory(size_mb)     — Exclude size_mb from PMM at boot.
;   rt_reserve_alloc(pages)             — Slices physical frames from reserve.
;   rt_reserve_free(addr, pages)        — Release pages back to reserve.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RT_RESERVE_ASM
%define LIB_MEM_VIRT_RT_RESERVE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
RT_RESERVE_MAX_PAGES    equ 4096    ; Max 16MB reservation pool

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; rt_reserve_boot_memory — Reserve size_mb of physical pages at boot time
; Input:  RDI = size in Megabytes (1 to 16)
; Output: RAX = successfully reserved bytes, 0 on failure
; Clobbers: RAX, RCX, RDX, RDI, RSI, R8
; ---------------------------------------------------------------------------
global rt_reserve_boot_memory
rt_reserve_boot_memory:
    test rdi, rdi
    jz   .fail
    
    ; Convert MB to pages count: Pages = MB * 256
    mov  rax, rdi
    shl  rax, 8                     ; RAX = pages (MB * 256)
    cmp  rax, RT_RESERVE_MAX_PAGES
    ja   .fail                      ; exceeds capacity limit

    mov  r8, rax                    ; R8 = page count
    xor  rcx, rcx                   ; RCX = index loop
    extern phys_alloc_page

.alloc_loop:
    push rcx
    push r8
    call phys_alloc_page            ; RAX = physical address
    pop  r8
    pop  rcx
    test rax, rax
    jz   .oom

    mov  [sys_rt_reserved_phys_frames + rcx * 8], rax
    inc  rcx
    cmp  rcx, r8
    jb   .alloc_loop

    ; Successful reservation!
    mov  [sys_rt_reserved_page_count], r8
    
    ; Calculate total reserved bytes = pages * 4096
    mov  rax, r8
    shl  rax, 12
    mov  [sys_rt_reserved_total_bytes], rax
    mov  qword [sys_rt_reserved_used_bytes], 0

    ret

.oom:
    ; Clean up partial allocation
    test rcx, rcx
    jz   .fail
    mov  r8, rcx
    xor  rcx, rcx
    extern phys_free_page
.cleanup_loop:
    mov  rdi, [sys_rt_reserved_phys_frames + rcx * 8]
    call phys_free_page
    inc  rcx
    cmp  rcx, r8
    jb   .cleanup_loop

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; rt_reserve_alloc — Slices pages from the reserved pool
; Input:  RDI = page count to allocate
; Output: RAX = Physical address of first allocated frame, 0 if OOM
; Clobbers: RAX, RCX, RDX, R8, R9
; ---------------------------------------------------------------------------
global rt_reserve_alloc
rt_reserve_alloc:
    test rdi, rdi
    jz   .fail

    mov  r8, rdi                    ; R8 = requested page count
    mov  r9, [sys_rt_reserved_page_count]
    
    ; We search the sys_rt_reserved_phys_frames array for R8 contiguous pages
    ; that are not yet marked as allocated (we can store 0 when allocated, and restore on free)
    xor  rax, rax                   ; RAX = start index loop
.search_loop:
    mov  rbx, rax
    add  rbx, r8
    cmp  rbx, r9
    ja   .fail                      ; not enough room in reserve pool

    ; Check if all elements from RAX to RAX+R8-1 are non-zero (available)
    xor  rcx, rcx
.check_frames:
    mov  rdx, rax
    add  rdx, rcx
    mov  r10, [sys_rt_reserved_phys_frames + rdx * 8]
    test r10, r10
    jz   .search_failed             ; 0 means allocated

    inc  rcx
    cmp  rcx, r8
    jb   .check_frames

    ; Found contiguous free frames base at RAX!
    ; Save the starting physical frame pointer to return
    mov  r11, [sys_rt_reserved_phys_frames + rax * 8]

    ; Mark them as allocated by setting to 0 in array
    xor  rcx, rcx
.mark_allocated:
    mov  rdx, rax
    add  rdx, rcx
    mov  qword [sys_rt_reserved_phys_frames + rdx * 8], 0
    inc  rcx
    cmp  rcx, r8
    jb   .mark_allocated

    ; Update used bytes count: used += pages * 4096
    mov  rax, r8
    shl  rax, 12
    add  [sys_rt_reserved_used_bytes], rax

    ; Return the physical base pointer (naturally contiguous since allocated contiguous at boot)
    mov  rax, r11
    ret

.search_failed:
    add  rax, rcx
    inc  rax
    jmp  .search_loop

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; rt_reserve_free — Release physical frames back to reservation pool
; Input:
;   RDI = Physical address base (must be page aligned)
;   RSI = page count
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, R8, R9
; ---------------------------------------------------------------------------
global rt_reserve_free
rt_reserve_free:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    mov  r8, rdi                    ; R8 = physical address base
    mov  r9, rsi                    ; R9 = page count

    ; Find where this address range should fit back in the reservation array.
    ; Since we mapped them contiguous at boot time, we can calculate its index:
    ; We look up the base address of boot reservation (sys_rt_reserved_phys_frames index 0 might be overwritten,
    ; but we can keep a backup of the original physical frames in another BSS array or recalculate index).
    ; Better: we find the first empty (0) slot in array and place it back.
    ; Since we allocated contiguous physical frames at boot:
    ; let's scan the BSS backup table of physical ranges to locate its boot index!
    ; Let's search sys_rt_reserved_phys_backup for R8 base address.
    xor  rax, rax                   ; RAX = index
    mov  rcx, [sys_rt_reserved_page_count]
.find_index:
    cmp  rax, rcx
    jae  .fail
    cmp  [sys_rt_reserved_phys_backup + rax * 8], r8
    je   .index_found
    inc  rax
    jmp  .find_index

.index_found:
    ; RAX is the boot index where R8 physical address was.
    ; Restore it in the active tracking array:
    xor  rcx, rcx
.restore_loop:
    mov  rdx, rax
    add  rdx, rcx
    
    ; Restore from backup array
    mov  r10, [sys_rt_reserved_phys_backup + rdx * 8]
    mov  [sys_rt_reserved_phys_frames + rdx * 8], r10
    
    inc  rcx
    cmp  rcx, r9
    jb   .restore_loop

    ; Subtract used bytes
    mov  rax, r9
    shl  rax, 12
    sub  [sys_rt_reserved_used_bytes], rax

    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; rt_reserve_backup — Helper to back up the boot reservation array (internal use)
; Output: RAX = 1
; Clobbers: RAX, RCX, RSI, RDI
; ---------------------------------------------------------------------------
global rt_reserve_backup
rt_reserve_backup:
    push rsi
    push rdi
    push rcx

    lea  rsi, [sys_rt_reserved_phys_frames]
    lea  rdi, [sys_rt_reserved_phys_backup]
    mov  rcx, RT_RESERVE_MAX_PAGES
    rep  movsq

    mov  rax, 1
    pop  rcx
    pop  rdi
    pop  rsi
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
sys_rt_reserved_page_count:     dq 0

align 8
global sys_rt_reserved_total_bytes
sys_rt_reserved_total_bytes:    dq 0

align 8
global sys_rt_reserved_used_bytes
sys_rt_reserved_used_bytes:     dq 0

; ---------------------------------------------------------------------------
; BSS — reserve physical page tracking list (up to 4096 pages)
; ---------------------------------------------------------------------------
section .bss

align 64
sys_rt_reserved_phys_frames:    resq RT_RESERVE_MAX_PAGES

align 64
sys_rt_reserved_phys_backup:    resq RT_RESERVE_MAX_PAGES

section .text

%endif ; LIB_MEM_VIRT_RT_RESERVE_ASM
