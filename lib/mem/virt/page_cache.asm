; =============================================================================
; Tattva OS — lib/mem/virt/page_cache.asm
; =============================================================================
; Unified Page Cache.
; Caches file blocks (pages) in RAM to accelerate file reads and writes.
; Avoids repeated disk I/O by sharing page cache frames across mappings.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGE_CACHE_ASM
%define LIB_MEM_VIRT_PAGE_CACHE_ASM

[BITS 64]

; Maximum entries in the Unified Page Cache
PAGE_CACHE_MAX_ENTRIES equ 256

; Page Cache Entry Structure
struc page_cache_entry_t
    .file_ptr   resq 1      ; Pointer to mock_file_t
    .offset     resq 1      ; File offset (in bytes, page-aligned)
    .phys_page  resq 1      ; Backing RAM page physical address
    .flags      resq 1      ; Flags: bit 0 = active, bit 1 = dirty
endstruc

section .text

; External helper functions
extern phys_alloc_page
extern phys_free_page
extern memzero
extern memcpy
extern storage_read_file_page
extern storage_write_file_page
extern virt_readahead_trigger
extern sys_readahead_window_size
extern virt_writeback_throttle_check
extern virt_translate

; -----------------------------------------------------------------------------
; virt_page_cache_init — initializes the page cache and resets counters
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global virt_page_cache_init
virt_page_cache_init:
    push rdi
    push rsi
    push rdx

    mov rdi, sys_page_cache
    mov rsi, page_cache_entry_t_size * PAGE_CACHE_MAX_ENTRIES
    call memzero

    mov qword [sys_page_cache_hits], 0
    mov qword [sys_page_cache_misses], 0
    mov qword [sys_page_cache_count], 0

    pop rdx
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; virt_page_cache_find — searches for a cached page frame for a file and offset
; Input:
;   RDI = file pointer (mock_file_t*)
;   RSI = file offset (in bytes)
; Output:
;   RAX = physical page address if found, or 0 if cache miss
; -----------------------------------------------------------------------------
global virt_page_cache_find
virt_page_cache_find:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    xor rax, rax                    ; RAX = default (0 = not found)
    xor rcx, rcx                    ; RCX = index loop

.loop:
    cmp rcx, PAGE_CACHE_MAX_ENTRIES
    jae .miss

    mov rbx, rcx
    imul rbx, page_cache_entry_t_size
    lea rbx, [sys_page_cache + rbx]

    ; Check if active
    mov rdx, [rbx + page_cache_entry_t.flags]
    test rdx, 1
    jz .next

    ; Check file_ptr
    cmp [rbx + page_cache_entry_t.file_ptr], rdi
    jne .next

    ; Check offset
    cmp [rbx + page_cache_entry_t.offset], rsi
    jne .next

    ; Found!
    mov rax, [rbx + page_cache_entry_t.phys_page]
    inc qword [sys_page_cache_hits]
    jmp .done

.next:
    inc rcx
    jmp .loop

.miss:
    inc qword [sys_page_cache_misses]
    xor rax, rax

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_page_cache_add — inserts a new page frame into the page cache
; Input:
;   RDI = file pointer (mock_file_t*)
;   RSI = file offset (in bytes)
;   RDX = physical page address
; Output:
;   RAX = 1 on success, 0 on failure (cache full)
; -----------------------------------------------------------------------------
global virt_page_cache_add
virt_page_cache_add:
    push rbx
    push rcx

    xor rcx, rcx                    ; loop index
.loop:
    cmp rcx, PAGE_CACHE_MAX_ENTRIES
    jae .full

    mov rbx, rcx
    imul rbx, page_cache_entry_t_size
    lea rbx, [sys_page_cache + rbx]

    mov rax, [rbx + page_cache_entry_t.flags]
    test rax, 1                     ; active?
    jnz .next

    ; Found empty slot! Store
    mov [rbx + page_cache_entry_t.file_ptr], rdi
    mov [rbx + page_cache_entry_t.offset], rsi
    mov [rbx + page_cache_entry_t.phys_page], rdx
    mov qword [rbx + page_cache_entry_t.flags], 1   ; active = 1, dirty = 0

    inc qword [sys_page_cache_count]
    mov rax, 1
    jmp .done

.next:
    inc rcx
    jmp .loop

.full:
    xor rax, rax                    ; return 0 (full)

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_page_cache_get_or_create — gets page from cache or reads from disk on miss
; Input:
;   RDI = file pointer (mock_file_t*)
;   RSI = file offset (in bytes, page-aligned)
; Output:
;   RAX = physical page address, or 0 on error (OOM/Full)
; -----------------------------------------------------------------------------
global virt_page_cache_get_or_create
virt_page_cache_get_or_create:
    push rbx
    push r12
    push r13

    mov r12, rdi                    ; R12 = file_ptr
    mov r13, rsi                    ; R13 = offset

    ; 1. Try to find in cache
    mov rdi, r12
    mov rsi, r13
    call virt_page_cache_find
    test rax, rax
    jnz .done                       ; found, return physical page in RAX

    ; 2. Cache miss! Allocate physical page
    call phys_alloc_page
    test rax, rax
    jz .done                        ; OOM, return 0
    mov rbx, rax                    ; RBX = physical page

    ; 3. Zero page
    push rbx
    mov rdi, rbx
    mov rsi, 4096
    call memzero
    pop rbx

    ; 4. Read from disk
    mov rdi, r12                    ; file_ptr
    mov rsi, r13                    ; offset
    mov rdx, rbx                    ; dest_phys
    call storage_read_file_page

    ; 5. Add to cache
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call virt_page_cache_add
    test rax, rax
    jz .cache_full_cleanup          ; if full, free page and return 0

    ; Trigger sequential readahead prefetching
    mov rdi, r12
    mov rsi, r13
    mov rdx, [sys_readahead_window_size]
    call virt_readahead_trigger

    mov rax, rbx                    ; return physical page
    jmp .done

.cache_full_cleanup:
    mov rdi, rbx
    call phys_free_page
    xor rax, rax

.done:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_file_read — reads sequential data using the unified page cache
; Input:
;   RDI = file pointer (mock_file_t*)
;   RSI = starting file offset (in bytes)
;   RDX = destination virtual address buffer
;   RCX = number of bytes to read
; Output:
;   RAX = actual bytes read
; -----------------------------------------------------------------------------
global virt_file_read
virt_file_read:
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
    mov r13, rsi                    ; R13 = file offset
    mov r14, rdx                    ; R14 = dest_buf pointer
    mov r15, rcx                    ; R15 = count of bytes to read
    xor rbp, rbp                    ; RBP = total bytes read

    ; Check if O_DIRECT cache bypass is active
    cmp qword [sys_o_direct], 0
    jz .loop                        ; if 0, use standard cached path

    ; Check alignment: offset (R13), dest_buf (R14), and count (R15) must be 4KB page aligned
    mov rax, r13
    or rax, r14
    or rax, r15
    test rax, 4095
    jnz .loop                       ; if any is not page-aligned, fallback to cached path

.direct_loop:
    test r15, r15
    jz .done

    ; Translate destination virtual address R14 to physical page address
    mov rdi, r14
    call virt_translate
    test rax, rax
    jz .done                        ; translation error, exit

    ; Read directly from storage into destination physical page
    mov rdi, r12                    ; file_ptr
    mov rsi, r13                    ; file offset
    mov rdx, rax                    ; physical page address
    call storage_read_file_page

    ; Update pointers/counters
    add rbp, 4096
    add r13, 4096
    add r14, 4096
    sub r15, 4096
    jmp .direct_loop

.loop:
    test r15, r15
    jz .done

    ; Get page start offset
    mov rax, r13
    and rax, -4096                  ; RAX = page-aligned file offset

    ; Get offset within page
    mov rbx, r13
    and rbx, 4095                   ; RBX = offset within page

    ; Get bytes to copy from this page: min(4096 - RBX, R15)
    mov rcx, 4096
    sub rcx, rbx                    ; RCX = remaining bytes in page
    cmp rcx, r15
    jbe .do_copy
    mov rcx, r15
.do_copy:

    ; Get or create physical page in page cache
    mov rdi, r12
    mov rsi, rax
    push rcx
    call virt_page_cache_get_or_create
    pop rcx
    test rax, rax
    jz .done                        ; OOM/Error, stop reading

    ; Copy from page cache (RAX + RBX) to dest_buf (R14)
    push rcx
    push rsi
    push rdi

    mov rdi, r14                    ; dest = dest_buf
    mov rsi, rax
    add rsi, rbx                    ; source = phys_page + offset_within_page
    mov rdx, rcx                    ; length
    call memcpy

    pop rdi
    pop rsi
    pop rcx

    ; Update pointers/counters
    add rbp, rcx                    ; total read += copied
    add r13, rcx                    ; file offset += copied
    add r14, rcx                    ; dest_buf += copied
    sub r15, rcx                    ; count -= copied
    jmp .loop

.done:
    mov rax, rbp
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
    ret

; -----------------------------------------------------------------------------
; virt_file_write — writes sequential data, caching it and marking dirty
; Input:
;   RDI = file pointer (mock_file_t*)
;   RSI = starting file offset (in bytes)
;   RDX = source virtual address buffer
;   RCX = number of bytes to write
; Output:
;   RAX = actual bytes written
; -----------------------------------------------------------------------------
global virt_file_write
virt_file_write:
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
    mov r13, rsi                    ; R13 = file offset
    mov r14, rdx                    ; R14 = src_buf pointer
    mov r15, rcx                    ; R15 = count of bytes to write
    xor rbp, rbp                    ; RBP = total bytes written

.loop:
    test r15, r15
    jz .done

    ; Get page start offset
    mov rax, r13
    and rax, -4096                  ; RAX = page-aligned file offset

    ; Get offset within page
    mov rbx, r13
    and rbx, 4095                   ; RBX = offset within page

    ; Get bytes to copy to this page: min(4096 - RBX, R15)
    mov rcx, 4096
    sub rcx, rbx
    cmp rcx, r15
    jbe .do_copy
    mov rcx, r15
.do_copy:

    ; Get or create physical page in page cache
    mov rdi, r12
    mov rsi, rax
    push rcx
    call virt_page_cache_get_or_create
    pop rcx
    test rax, rax
    jz .done                        ; OOM/Error, stop writing

    ; Mark cache entry dirty
    push rax
    mov rdi, r12
    mov rsi, r13
    and rsi, -4096
    
    ; Find entry and set dirty flag
    xor r8, r8
.find_loop:
    cmp r8, PAGE_CACHE_MAX_ENTRIES
    jae .find_done
    mov r9, r8
    imul r9, page_cache_entry_t_size
    lea r9, [sys_page_cache + r9]
    mov r10, [r9 + page_cache_entry_t.flags]
    test r10, 1
    jz .find_next
    cmp [r9 + page_cache_entry_t.file_ptr], rdi
    jne .find_next
    cmp [r9 + page_cache_entry_t.offset], rsi
    jne .find_next
    ; Found slot! Set dirty bit (bit 1)
    or qword [r9 + page_cache_entry_t.flags], 2
    jmp .find_done
.find_next:
    inc r8
    jmp .find_loop
.find_done:
    pop rax

    ; Copy from src_buf (R14) to page cache (RAX + RBX)
    push rcx
    push rsi
    push rdi

    mov rdi, rax
    add rdi, rbx                    ; dest = phys_page + offset_within_page
    mov rsi, r14                    ; source = src_buf
    mov rdx, rcx                    ; length
    call memcpy

    pop rdi
    pop rsi
    pop rcx

    ; Update pointers/counters
    add rbp, rcx                    ; total written += copied
    add r13, rcx                    ; file offset += copied
    add r14, rcx                    ; src_buf += copied
    sub r15, rcx                    ; count -= copied
    jmp .loop

.done:
    mov rax, rbp
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
    ret

; -----------------------------------------------------------------------------
; virt_page_cache_sync — synchronizes all dirty pages back to mock storage
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global virt_page_cache_sync
virt_page_cache_sync:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    xor rcx, rcx
.loop:
    cmp rcx, PAGE_CACHE_MAX_ENTRIES
    jae .done

    mov rbx, rcx
    imul rbx, page_cache_entry_t_size
    lea rbx, [sys_page_cache + rbx]

    mov rax, [rbx + page_cache_entry_t.flags]
    test rax, 1                     ; active?
    jz .next
    test rax, 2                     ; dirty?
    jz .next

    ; Apply writeback throttling check (forces delay if dirty pages exceed limit)
    push rbx
    push rcx
    call virt_writeback_throttle_check
    pop rcx
    pop rbx

    ; Write dirty page back to mock disk
    mov rdi, [rbx + page_cache_entry_t.file_ptr]
    mov rsi, [rbx + page_cache_entry_t.offset]
    mov rdx, [rbx + page_cache_entry_t.phys_page]
    call storage_write_file_page

    ; Clear dirty flag
    and qword [rbx + page_cache_entry_t.flags], ~2

.next:
    inc rcx
    jmp .loop

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

section .data

align 8
global sys_page_cache_hits
global sys_page_cache_misses
global sys_page_cache_count
global sys_o_direct

sys_page_cache_hits:   dq 0
sys_page_cache_misses: dq 0
sys_page_cache_count:  dq 0
sys_o_direct:          dq 0


section .bss

align 8
global sys_page_cache

sys_page_cache: resb page_cache_entry_t_size * PAGE_CACHE_MAX_ENTRIES

%endif ; LIB_MEM_VIRT_PAGE_CACHE_ASM
