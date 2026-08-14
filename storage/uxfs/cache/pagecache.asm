; =============================================================================
; Tattva OS — storage/uxfs/cache/pagecache.asm
; =============================================================================
; 4KB Page Cache — Descriptor Table, Reference Counting & Writeback Tracking.
;
; Implements:
;   - Open-addressed LBA to page-descriptor index (`uxfs_pagecache_lookup`)
;   - Reference-counted acquire and release (`uxfs_pagecache_get/put_page`)
;   - Dirty tracking and writeback enumeration (`uxfs_pagecache_mark_dirty`,
;     `uxfs_pagecache_next_dirty`)
;   - Safe invalidation that refuses to drop pinned or dirty pages
;     (`uxfs_pagecache_invalidate`)
;
; The previous implementation forwarded straight to the ARC, which made the
; cache unusable for writes: with no reference count a page could be evicted
; while a caller still held a pointer into it, and with no dirty bit there was
; no way to know which pages still owed a write to disk.
;
; Descriptors are kept separate from page data so eviction policy (ARC) and
; residency bookkeeping stay independent — ARC decides WHAT to evict, the
; reference count decides whether it MAY be evicted right now.
;
; Indexing is open addressing with linear probing. Chaining would need an
; allocator on the lookup path; probing keeps a hit to a handful of contiguous
; cache lines and the table is sized so load factor stays well under half.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_PC_SLOTS                4096        ; Power of two: mask indexing
%define UXFS_PC_SLOT_MASK            (UXFS_PC_SLOTS - 1)
%define UXFS_PC_EMPTY                0xFFFFFFFFFFFFFFFF  ; Never a valid LBA

; Page descriptor state bits.
%define UXFS_PC_FLAG_VALID           (1 << 0)    ; Slot occupied
%define UXFS_PC_FLAG_UPTODATE        (1 << 1)    ; Contents match backing store
%define UXFS_PC_FLAG_DIRTY           (1 << 2)    ; Owes a write to disk
%define UXFS_PC_FLAG_WRITEBACK       (1 << 3)    ; Write currently in flight

; -----------------------------------------------------------------------------
; One cached 4KB page.
; -----------------------------------------------------------------------------
struc uxfs_page_desc_t
    .lba:               resq 1      ; Backing block address, or UXFS_PC_EMPTY
    .buffer:            resq 1      ; Pointer to the 4KB page frame
    .flags:             resd 1      ; UXFS_PC_FLAG_* bitmask
    .refcount:          resd 1      ; Non-zero pins the page against eviction
endstruc

section .data
align 64

global uxfs_pagecache_table
uxfs_pagecache_table:
    times UXFS_PC_SLOTS * uxfs_page_desc_t_size db 0

uxfs_pc_initialised:    dq 0
uxfs_pc_resident:       dq 0        ; Occupied slots
uxfs_pc_dirty:          dq 0        ; Slots awaiting writeback
uxfs_pc_hits:           dq 0
uxfs_pc_misses:         dq 0

section .text

global uxfs_pagecache_init
global uxfs_pagecache_lookup
global uxfs_pagecache_get_page
global uxfs_pagecache_put_page
global uxfs_pagecache_insert
global uxfs_pagecache_mark_dirty
global uxfs_pagecache_next_dirty
global uxfs_pagecache_end_writeback
global uxfs_pagecache_invalidate
global uxfs_pagecache_stats

; -----------------------------------------------------------------------------
; uxfs_pc_hash
;
; Fibonacci hashing: multiply by 2^64/phi and take the high bits. Sequential
; LBAs — the overwhelmingly common access pattern — would collide badly under
; a plain mask, since the low bits barely change.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   RAX = Slot index in 0..UXFS_PC_SLOTS-1
; -----------------------------------------------------------------------------
align 32
uxfs_pc_hash:
    mov rax, rdi
    mov rcx, 0x9E3779B97F4A7C15     ; imul needs a register: imm64 is unencodable
    imul rax, rcx
    shr rax, 52                     ; Fold the high bits down
    and rax, UXFS_PC_SLOT_MASK
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_init
;
; Marks every slot empty and resets counters. An all-zero table would otherwise
; read as LBA 0 resident in every slot.
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_init:
    push rbx
    push r12

    lea rbx, [uxfs_pagecache_table]
    mov r12, UXFS_PC_SLOTS

.pi_loop:
    mov qword [rbx + uxfs_page_desc_t.lba], UXFS_PC_EMPTY
    mov qword [rbx + uxfs_page_desc_t.buffer], 0
    mov dword [rbx + uxfs_page_desc_t.flags], 0
    mov dword [rbx + uxfs_page_desc_t.refcount], 0
    add rbx, uxfs_page_desc_t_size
    dec r12
    jnz .pi_loop

    mov qword [uxfs_pc_resident], 0
    mov qword [uxfs_pc_dirty], 0
    mov qword [uxfs_pc_hits], 0
    mov qword [uxfs_pc_misses], 0
    mov qword [uxfs_pc_initialised], 1

    call uxfs_arc_init              ; Eviction policy shares this cache

    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_lookup
;
; Finds the descriptor for an LBA without changing its reference count.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   RAX = Descriptor pointer, or 0 when not resident
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_lookup:
    push rbx
    push r12
    push r13

    mov r13, rdi                    ; Wanted LBA

    call uxfs_pc_hash
    mov r12, rax                    ; Probe position

    mov rbx, UXFS_PC_SLOTS          ; Probe budget: bounds the walk

.pl_probe:
    mov rax, r12
    imul rax, rax, uxfs_page_desc_t_size
    lea rax, [uxfs_pagecache_table + rax]

    ; An empty slot ends the probe: a match would have been placed here.
    cmp qword [rax + uxfs_page_desc_t.lba], UXFS_PC_EMPTY
    je .pl_missing

    test dword [rax + uxfs_page_desc_t.flags], UXFS_PC_FLAG_VALID
    jz .pl_next

    cmp qword [rax + uxfs_page_desc_t.lba], r13
    je .pl_found

.pl_next:
    inc r12
    and r12, UXFS_PC_SLOT_MASK
    dec rbx
    jnz .pl_probe

.pl_missing:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.pl_found:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_insert
;
; Installs a page frame for an LBA and returns it pinned.
;
; Inputs:
;   RDI = Block LBA
;   RSI = Pointer to the 4KB page frame
;
; Returns:
;   RAX = Descriptor pointer, or 0 when the table is full
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_insert:
    push rbx
    push r12
    push r13
    push r14

    mov r13, rdi                    ; LBA
    mov r14, rsi                    ; Page frame

    ; Re-inserting an existing LBA just re-pins it.
    call uxfs_pagecache_lookup
    test rax, rax
    jnz .pn_existing

    mov rdi, r13
    call uxfs_pc_hash
    mov r12, rax

    mov rbx, UXFS_PC_SLOTS

.pn_probe:
    mov rax, r12
    imul rax, rax, uxfs_page_desc_t_size
    lea rax, [uxfs_pagecache_table + rax]

    test dword [rax + uxfs_page_desc_t.flags], UXFS_PC_FLAG_VALID
    jz .pn_claim

    inc r12
    and r12, UXFS_PC_SLOT_MASK
    dec rbx
    jnz .pn_probe

    xor eax, eax                    ; Full: caller must evict first
    jmp .pn_return

.pn_claim:
    mov [rax + uxfs_page_desc_t.lba], r13
    mov [rax + uxfs_page_desc_t.buffer], r14
    mov dword [rax + uxfs_page_desc_t.flags], UXFS_PC_FLAG_VALID | UXFS_PC_FLAG_UPTODATE
    mov dword [rax + uxfs_page_desc_t.refcount], 1

    inc qword [uxfs_pc_resident]

    ; Tell ARC about the residency so its policy sees the same working set.
    push rax
    mov rdi, r13
    mov rsi, r14
    call uxfs_arc_insert
    pop rax
    jmp .pn_return

.pn_existing:
    inc dword [rax + uxfs_page_desc_t.refcount]

.pn_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_get_page
;
; Acquires a page, pinning it. The pin is what makes the returned pointer safe
; to dereference: an unpinned page may be evicted underneath the caller.
;
; Every successful get MUST be balanced by a put, or the page leaks and can
; never be evicted.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   RAX = Pointer to the 4KB page buffer, or 0 on miss
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_get_page:
    push rbx

    call uxfs_pagecache_lookup
    test rax, rax
    jz .pg_miss

    mov rbx, rax
    inc dword [rbx + uxfs_page_desc_t.refcount]
    inc qword [uxfs_pc_hits]

    mov rax, [rbx + uxfs_page_desc_t.buffer]
    pop rbx
    ret

.pg_miss:
    inc qword [uxfs_pc_misses]
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_put_page
;
; Drops a reference acquired by get_page or insert.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   EAX = Remaining reference count, or POSIX_ENOENT when not resident
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_put_page:
    push rbx

    call uxfs_pagecache_lookup
    test rax, rax
    jz .pp_missing

    mov rbx, rax
    cmp dword [rbx + uxfs_page_desc_t.refcount], 0
    je .pp_unbalanced

    dec dword [rbx + uxfs_page_desc_t.refcount]
    mov eax, dword [rbx + uxfs_page_desc_t.refcount]
    pop rbx
    ret

.pp_unbalanced:
    ; More puts than gets: a caller bug that would underflow to ~4 billion and
    ; pin the page permanently. Report it rather than wrap.
    mov eax, POSIX_EINVAL
    pop rbx
    ret

.pp_missing:
    mov eax, POSIX_ENOENT
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_mark_dirty
;
; Marks a resident page as owing a write to disk.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   EAX = 0 on success, POSIX_ENOENT when not resident
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_mark_dirty:
    push rbx

    call uxfs_pagecache_lookup
    test rax, rax
    jz .md_missing

    mov rbx, rax
    test dword [rbx + uxfs_page_desc_t.flags], UXFS_PC_FLAG_DIRTY
    jnz .md_already                 ; Do not double-count the dirty tally

    or dword [rbx + uxfs_page_desc_t.flags], UXFS_PC_FLAG_DIRTY
    inc qword [uxfs_pc_dirty]

.md_already:
    xor eax, eax
    pop rbx
    ret

.md_missing:
    mov eax, POSIX_ENOENT
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_next_dirty
;
; Enumerates dirty pages for writeback, marking each as in-flight so a
; concurrent sweep does not submit it twice.
;
; Inputs:
;   RDI = Slot index to resume from (0 to start)
;
; Returns:
;   RAX = Descriptor pointer, or 0 when no more dirty pages remain
;   RDX = Slot index to pass to the next call
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_next_dirty:
    push rbx
    push r12

    mov r12, rdi                    ; Cursor

.nd_scan:
    cmp r12, UXFS_PC_SLOTS
    jae .nd_done

    mov rax, r12
    imul rax, rax, uxfs_page_desc_t_size
    lea rbx, [uxfs_pagecache_table + rax]

    mov ecx, dword [rbx + uxfs_page_desc_t.flags]
    test ecx, UXFS_PC_FLAG_DIRTY
    jz .nd_next
    test ecx, UXFS_PC_FLAG_WRITEBACK
    jnz .nd_next                    ; Already being written

    or dword [rbx + uxfs_page_desc_t.flags], UXFS_PC_FLAG_WRITEBACK

    inc r12
    mov rdx, r12
    mov rax, rbx
    pop r12
    pop rbx
    ret

.nd_next:
    inc r12
    jmp .nd_scan

.nd_done:
    xor eax, eax
    mov rdx, r12
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_end_writeback
;
; Clears dirty and in-flight state once a write has actually reached disk.
;
; Only call this after the device reports completion. Clearing dirty on
; submission rather than completion is a classic durability bug: a crash
; mid-write leaves a page the cache believes is clean but disk never received.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   EAX = 0 on success, POSIX_ENOENT when not resident
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_end_writeback:
    push rbx

    call uxfs_pagecache_lookup
    test rax, rax
    jz .ew_missing

    mov rbx, rax
    test dword [rbx + uxfs_page_desc_t.flags], UXFS_PC_FLAG_DIRTY
    jz .ew_clean

    and dword [rbx + uxfs_page_desc_t.flags], ~(UXFS_PC_FLAG_DIRTY | UXFS_PC_FLAG_WRITEBACK)
    dec qword [uxfs_pc_dirty]

    xor eax, eax
    pop rbx
    ret

.ew_clean:
    and dword [rbx + uxfs_page_desc_t.flags], ~UXFS_PC_FLAG_WRITEBACK
    xor eax, eax
    pop rbx
    ret

.ew_missing:
    mov eax, POSIX_ENOENT
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_invalidate
;
; Drops a page from the cache.
;
; Refuses when the page is pinned or dirty: evicting a pinned page invalidates
; a pointer a caller still holds, and evicting a dirty page discards a write
; that disk never received. Both are silent corruption, so both fail loudly.
;
; Inputs:
;   RDI = Block LBA
;
; Returns:
;   EAX = 0 on success
;         POSIX_EBUSY  when the page is pinned or under writeback
;         POSIX_EINVAL when the page is dirty
;         POSIX_ENOENT when not resident
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_invalidate:
    push rbx

    call uxfs_pagecache_lookup
    test rax, rax
    jz .iv_missing

    mov rbx, rax

    cmp dword [rbx + uxfs_page_desc_t.refcount], 0
    jne .iv_busy
    test dword [rbx + uxfs_page_desc_t.flags], UXFS_PC_FLAG_WRITEBACK
    jnz .iv_busy
    test dword [rbx + uxfs_page_desc_t.flags], UXFS_PC_FLAG_DIRTY
    jnz .iv_dirty

    ; Tombstone rather than empty: an empty slot would truncate the probe
    ; sequence and hide entries placed beyond this point.
    mov qword [rbx + uxfs_page_desc_t.lba], 0
    mov qword [rbx + uxfs_page_desc_t.buffer], 0
    mov dword [rbx + uxfs_page_desc_t.flags], 0
    mov dword [rbx + uxfs_page_desc_t.refcount], 0

    dec qword [uxfs_pc_resident]

    xor eax, eax
    pop rbx
    ret

.iv_busy:
    mov eax, POSIX_EBUSY
    pop rbx
    ret

.iv_dirty:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

.iv_missing:
    mov eax, POSIX_ENOENT
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pagecache_stats
;
; Inputs:
;   RDI = Pointer to five qwords: resident, dirty, hits, misses, slot count
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_pagecache_stats:
    mov rax, [uxfs_pc_resident]
    mov [rdi], rax
    mov rax, [uxfs_pc_dirty]
    mov [rdi + 8], rax
    mov rax, [uxfs_pc_hits]
    mov [rdi + 16], rax
    mov rax, [uxfs_pc_misses]
    mov [rdi + 24], rax
    mov qword [rdi + 32], UXFS_PC_SLOTS
    xor eax, eax
    ret
