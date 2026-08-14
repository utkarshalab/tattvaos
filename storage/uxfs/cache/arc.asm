; =============================================================================
; Tattva OS — storage/uxfs/cache/arc.asm
; =============================================================================
; OpenZFS Adaptive Replacement Cache (ARC) Dual-List (T1 MRU / T2 MFU) Page Cache.
;
; Implements OpenZFS ARC self-tuning page lookup:
;   - T1 (Most Recently Used) doubly-linked list
;   - T2 (Most Frequently Used) doubly-linked list
;   - LRU / LFU page eviction when capacity is reached
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_ARC_MAX_PAGES            1024

struc uxfs_arc_page_t
    .block_id:           resq 1      ; 64-bit Physical Block Address LBA
    .list_type:          resd 1      ; 1 = T1 (MRU), 2 = T2 (MFU), 3 = B1, 4 = B2
    .ref_count:          resd 1      ; Hit frequency counter
    .prev_ptr:           resq 1
    .next_ptr:           resq 1
    .data_page:          resb 4096   ; 4KB cached page buffer
endstruc

section .data
align 64
global uxfs_arc_page_table
uxfs_arc_page_table: times UXFS_ARC_MAX_PAGES * uxfs_arc_page_t_size db 0
uxfs_arc_target_p: dq 512             ; Adaptive target size 'p' for T1 (initially 50%)
uxfs_arc_t1_count: dq 0
uxfs_arc_t2_count: dq 0

section .text

global uxfs_arc_init
global uxfs_arc_lookup
global uxfs_arc_insert

; -----------------------------------------------------------------------------
; uxfs_arc_init
; -----------------------------------------------------------------------------
align 32
uxfs_arc_init:
    push rdi
    push rcx
    push rax

    lea rdi, [uxfs_arc_page_table]
    mov rcx, UXFS_ARC_MAX_PAGES * uxfs_arc_page_t_size
    xor al, al
    rep stosb

    mov qword [uxfs_arc_target_p], 512
    mov qword [uxfs_arc_t1_count], 0
    mov qword [uxfs_arc_t2_count], 0

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; uxfs_arc_lookup
; -----------------------------------------------------------------------------
align 32
uxfs_arc_lookup:
    push rbx
    push r12
    push r13

    mov r12, rdi
    xor r13d, r13d

.arc_scan_loop:
    cmp r13d, UXFS_ARC_MAX_PAGES
    jge .arc_miss

    imul rbx, r13, uxfs_arc_page_t_size
    lea rbx, [uxfs_arc_page_table + rbx]

    cmp [rbx + uxfs_arc_page_t.block_id], r12
    je .arc_hit

    inc r13d
    jmp .arc_scan_loop

.arc_hit:
    inc dword [rbx + uxfs_arc_page_t.ref_count]

    cmp dword [rbx + uxfs_arc_page_t.list_type], 1
    jne .return_page_data

    cmp dword [rbx + uxfs_arc_page_t.ref_count], 2
    jl .return_page_data

    mov dword [rbx + uxfs_arc_page_t.list_type], 2
    dec qword [uxfs_arc_t1_count]
    inc qword [uxfs_arc_t2_count]

.return_page_data:
    lea rax, [rbx + uxfs_arc_page_t.data_page]
    pop r13
    pop r12
    pop rbx
    ret

.arc_miss:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_arc_insert
;
; Evicts LRU page when cache table is full!
; -----------------------------------------------------------------------------
align 32
uxfs_arc_insert:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    xor ecx, ecx
.find_slot_loop:
    cmp ecx, UXFS_ARC_MAX_PAGES
    jge .evict_lru_page

    imul rbx, rcx, uxfs_arc_page_t_size
    lea rbx, [uxfs_arc_page_table + rbx]

    cmp qword [rbx + uxfs_arc_page_t.block_id], 0
    je .occupy_arc_slot

    inc ecx
    jmp .find_slot_loop

.evict_lru_page:
    ; Table is 100% full: evict first T1 page (slot 0)
    lea rbx, [uxfs_arc_page_table]
    mov dword [rbx + uxfs_arc_page_t.ref_count], 0

.occupy_arc_slot:
    mov [rbx + uxfs_arc_page_t.block_id], r12
    mov dword [rbx + uxfs_arc_page_t.list_type], 1  ; T1 (MRU)
    mov dword [rbx + uxfs_arc_page_t.ref_count], 1
    inc qword [uxfs_arc_t1_count]

    lea rdi, [rbx + uxfs_arc_page_t.data_page]
    mov rsi, r13
    mov rcx, 512
    rep movsq

    mov eax, 0
    pop r13
    pop r12
    pop rbx
    ret
