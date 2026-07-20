; =============================================================================
; Tattva OS — lib/mem/virt/readahead.asm
; =============================================================================
; Sequential File Readahead Prefetching Engine.
; Prefetches subsequent sequential blocks of a file into the Unified Page Cache
; to accelerate sequential read operations.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_READAHEAD_ASM
%define LIB_MEM_VIRT_READAHEAD_ASM

[BITS 64]

; Mock file structure definition (matching mmap.asm)
struc mock_file_t
    .size       resq 1
    .blocks     resq 32
endstruc

section .text



; -----------------------------------------------------------------------------
; virt_readahead_trigger — triggers prefetching of next sequential blocks
; Input:
;   RDI = file pointer (mock_file_t*)
;   RSI = current file offset (in bytes, page-aligned)
;   RDX = window size (pages to prefetch)
; Output: none
; -----------------------------------------------------------------------------
global virt_readahead_trigger
virt_readahead_trigger:
    test rdi, rdi
    jz .done
    test rdx, rdx
    jz .done

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

    mov r12, rdi                    ; R12 = file_ptr
    mov r13, rsi                    ; R13 = offset
    mov r14, rdx                    ; R14 = window size
    xor r15, r15                    ; R15 = loop index i = 0

.loop:
    cmp r15, r14
    jae .loop_done

    inc r15
    
    ; Compute prefetch offset: offset + i * 4096
    mov rbx, r15
    shl rbx, 12                     ; rbx = i * 4096
    add rbx, r13                    ; rbx = prefetch_offset
    
    ; Check if prefetch_offset >= file_size
    mov rax, [r12 + mock_file_t.size]
    cmp rbx, rax
    jae .loop_done                  ; past file end, stop prefetch

    ; Check if page is already in Unified Page Cache
    mov rdi, r12
    mov rsi, rbx
    call virt_page_cache_find
    test rax, rax
    jnz .loop                       ; already cached, skip

    ; Cache miss! Allocate physical page frame for prefetch
    call phys_alloc_page
    test rax, rax
    jz .loop_done                   ; OOM, stop prefetch
    mov rbp, rax                    ; RBP = physical page address

    ; Zero page
    mov rdi, rbp
    mov rsi, 4096
    call memzero

    ; Read page from storage into physical page
    mov rdi, r12                    ; file_ptr
    mov rsi, rbx                    ; prefetch_offset
    mov rdx, rbp                    ; dest_phys
    call storage_read_file_page

    ; Add to page cache
    mov rdi, r12
    mov rsi, rbx
    mov rdx, rbp
    call virt_page_cache_add
    test rax, rax
    jz .cache_full_cleanup

    ; Increment prefetch counter
    inc qword [sys_readahead_prefetched_pages]
    jmp .loop

.cache_full_cleanup:
    mov rdi, rbp
    call phys_free_page
    jmp .loop_done

.loop_done:
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
.done:
    ret

section .data

align 8
global sys_readahead_window_size
global sys_readahead_prefetched_pages

sys_readahead_window_size:       dq 2
sys_readahead_prefetched_pages:  dq 0

%endif ; LIB_MEM_VIRT_READAHEAD_ASM
