; =============================================================================
; Tattva OS — ufs/cache/pagecache.asm
; =============================================================================
; Zero-Copy DMA Ring Buffer Page Cache.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_PAGE_CACHE_SLOTS        4096

struc ufs_page_entry_t
    .block_id:          resq 1
    .page_phys_addr:    resq 1
    .flags:             resd 1
    .ref_count:         resd 1
endstruc

section .data
align 16
global pagecache_table
pagecache_table: times UFS_PAGE_CACHE_SLOTS * ufs_page_entry_t_size db 0

section .text

global pagecache_init
global pagecache_lookup
global pagecache_insert
global pagecache_flush

align 32
pagecache_init:
    push rdi
    push rcx
    push rax

    lea rdi, [pagecache_table]
    mov rcx, UFS_PAGE_CACHE_SLOTS * ufs_page_entry_t_size
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

align 32
pagecache_lookup:
    push rbx
    push rcx

    mov rax, rdi
    mov ecx, UFS_PAGE_CACHE_SLOTS
    xor edx, edx
    div rcx

    imul rbx, rdx, ufs_page_entry_t_size
    lea rbx, [pagecache_table + rbx]

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

align 32
pagecache_insert:
    push rbx
    push rcx

    mov rax, rdi
    mov ecx, UFS_PAGE_CACHE_SLOTS
    xor edx, edx
    div rcx

    imul rbx, rdx, ufs_page_entry_t_size
    lea rbx, [pagecache_table + rbx]

    mov [rbx + ufs_page_entry_t.block_id], rdi
    mov [rbx + ufs_page_entry_t.page_phys_addr], rsi
    mov dword [rbx + ufs_page_entry_t.flags], 1

    pop rcx
    pop rbx
    ret

align 32
pagecache_flush:
    mov eax, 0
    ret
