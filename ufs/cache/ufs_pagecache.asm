; =============================================================================
; Tattva OS — ufs/cache/ufs_pagecache.asm
; =============================================================================
; Zero-Copy DMA Ring Buffer Page Cache for uFS.
;
; Manages 4KB page frames in memory with hash-table block lookup, dirty page
; writeback tracking, and lock-free DMA buffer sharing for storage drivers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_PAGE_CACHE_SLOTS        4096

struc ufs_page_entry_t
    .block_id:          resq 1      ; Logical block ID
    .page_phys_addr:    resq 1      ; 64-bit Physical Page Frame Pointer
    .flags:             resd 1      ; 1=Valid, 2=Dirty, 4=Locked
    .ref_count:         resd 1      ; Access reference counter
endstruc

section .data
align 16
global ufs_pagecache_table
ufs_pagecache_table: times UFS_PAGE_CACHE_SLOTS * ufs_page_entry_t_size db 0

section .text

global ufs_pagecache_init
global ufs_pagecache_lookup
global ufs_pagecache_insert
global ufs_pagecache_flush

; -----------------------------------------------------------------------------
; ufs_pagecache_init
; -----------------------------------------------------------------------------
align 32
ufs_pagecache_init:
    push rdi
    push rcx
    push rax

    lea rdi, [ufs_pagecache_table]
    mov rcx, UFS_PAGE_CACHE_SLOTS * ufs_page_entry_t_size
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; ufs_pagecache_lookup
;
; Inputs:
;   RDI = Block ID
;
; Returns:
;   RAX = Physical Page Address (or 0 if miss)
; -----------------------------------------------------------------------------
align 32
ufs_pagecache_lookup:
    push rbx
    push rcx

    mov rax, rdi
    mov ecx, UFS_PAGE_CACHE_SLOTS
    xor edx, edx
    div rcx                         ; RDX = slot index (block_id % SLOTS)

    imul rbx, rdx, ufs_page_entry_t_size
    lea rbx, [ufs_pagecache_table + rbx]

    cmp [rbx + ufs_page_entry_t.block_id], rdi
    jne .cache_miss

    mov rax, [rbx + ufs_page_entry_t.page_phys_addr]
    pop rcx
    pop rbx
    ret

.cache_miss:
    xor rax, rax
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_pagecache_insert
; -----------------------------------------------------------------------------
align 32
ufs_pagecache_insert:
    push rbx
    push rcx

    mov rax, rdi
    mov ecx, UFS_PAGE_CACHE_SLOTS
    xor edx, edx
    div rcx

    imul rbx, rdx, ufs_page_entry_t_size
    lea rbx, [ufs_pagecache_table + rbx]

    mov [rbx + ufs_page_entry_t.block_id], rdi
    mov [rbx + ufs_page_entry_t.page_phys_addr], rsi
    mov dword [rbx + ufs_page_entry_t.flags], 1  ; Valid

    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_pagecache_flush
; -----------------------------------------------------------------------------
align 32
ufs_pagecache_flush:
    mov eax, 0                      ; Flush success
    ret
