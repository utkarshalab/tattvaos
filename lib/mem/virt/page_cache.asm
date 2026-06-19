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
    .size       resq 1      ; Folio size in bytes
endstruc

section .text

; External helper functions
extern phys_alloc_page
extern phys_alloc_pages
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

    ; Check offset range (Folio Support)
    ; entry.offset <= offset < entry.offset + entry.size
    mov rax, [rbx + page_cache_entry_t.offset]
    cmp rsi, rax
    jb .next
    add rax, [rbx + page_cache_entry_t.size]
    cmp rsi, rax
    jae .next

    ; Found! Return physical address corresponding to offset inside folio
    mov rax, [rbx + page_cache_entry_t.phys_page]
    sub rsi, [rbx + page_cache_entry_t.offset]
    add rax, rsi
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
    mov rax, [sys_folio_size]
    mov [rbx + page_cache_entry_t.size], rax

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
    push r14
    push r15

    mov r12, rdi                    ; R12 = file_ptr
    mov r13, rsi                    ; R13 = original offset

    ; 1. Try to find in cache
    mov rdi, r12
    mov rsi, r13
    call virt_page_cache_find
    test rax, rax
    jnz .done_get                   ; found, return physical page in RAX

    ; 2. Cache miss! Align offset to sys_folio_size boundary
    mov r8, [sys_folio_size]
    mov rax, r8
    dec rax
    not rax
    mov r14, r13
    and r14, rax                    ; R14 = aligned offset

    ; 3. Allocate contiguous physical pages
    mov rdi, r8
    add rdi, 4095
    shr rdi, 12                     ; RDI = page count
    call phys_alloc_pages
    test rax, rax
    jz .done_get                    ; OOM, return 0
    mov rbx, rax                    ; RBX = physical page base

    ; 4. Zero the entire folio
    mov rdi, rbx
    mov rsi, [sys_folio_size]
    call memzero

    ; 5. Read data from storage into folio pages
    mov r8, [sys_folio_size]
    add r8, 4095
    shr r8, 12                     ; R8 = page count
    xor r15, r15                    ; R15 = loop index j = 0

.read_loop:
    cmp r15, r8
    jae .read_done

    mov rsi, r15
    shl rsi, 12
    add rsi, r14                    ; rsi = file offset

    mov rdx, r15
    shl rdx, 12
    add rdx, rbx                    ; rdx = dest physical address

    mov rdi, r12                    ; file_ptr
    push r8
    push r15
    call storage_read_file_page
    pop r15
    pop r8

    inc r15
    jmp .read_loop

.read_done:
    ; 6. Add to cache
    mov rdi, r12
    mov rsi, r14
    mov rdx, rbx
    call virt_page_cache_add
    test rax, rax
    jz .cache_full_cleanup          ; if full, free pages and return 0

    ; Trigger sequential readahead prefetching
    mov rdi, r12
    mov rsi, r14
    mov rdx, [sys_readahead_window_size]
    call virt_readahead_trigger

    ; Return physical address corresponding to original offset: rbx + (r13 - r14)
    mov rax, r13
    sub rax, r14
    add rax, rbx
    jmp .done_get

.cache_full_cleanup:
    mov r8, [sys_folio_size]
    add r8, 4095
    shr r8, 12                     ; page count
    xor r15, r15
.free_loop:
    cmp r15, r8
    jae .free_done
    mov rdi, r15
    shl rdi, 12
    add rdi, rbx
    call phys_free_page
    inc r15
    jmp .free_loop
.free_done:
    xor rax, rax

.done_get:
    pop r15
    pop r14
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

    ; Get or create physical page in page cache
    mov rdi, r12
    mov rsi, r13
    call virt_page_cache_get_or_create
    test rax, rax
    jz .done                        ; OOM/Error, stop reading

    ; Calculate how many bytes we can read from this folio
    ; Get folio start from R13
    mov rbx, r13
    and rbx, -4096 ; Fallback to 4k for now, logic simplified
    
    ; Copy from page cache (RAX) to dest_buf (R14)
    push rcx
    push rsi
    push rdi

    mov rdi, r14                    ; dest = dest_buf
    mov rsi, rax
    mov rcx, 4096
    call memcpy

    pop rdi
    pop rsi
    pop rcx

    ; Update pointers/counters
    add rbp, 4096                    ; total read += copied
    add r13, 4096                    ; file offset += copied
    add r14, 4096                    ; dest_buf += copied
    sub r15, 4096                    ; count -= copied
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

    ; Get or create physical page in page cache
    mov rdi, r12
    mov rsi, r13
    call virt_page_cache_get_or_create
    test rax, rax
    jz .done                        ; OOM/Error, stop writing

    ; Mark cache entry dirty
    push rax
    mov rdi, r12
    mov rsi, r13

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

    ; Check if offset falls within this folio's range (Folio Support)
    mov r11, [r9 + page_cache_entry_t.offset]
    cmp rsi, r11
    jb .find_next
    add r11, [r9 + page_cache_entry_t.size]
    cmp rsi, r11
    jae .find_next

    ; Found slot! Set dirty bit (bit 1)
    or qword [r9 + page_cache_entry_t.flags], 2
    jmp .find_done
.find_next:
    inc r8
    jmp .find_loop
.find_done:
    pop rax

    ; Copy from src_buf (R14) to page cache (RAX)
    push rcx
    push rsi
    push rdi

    mov rdi, rax
    mov rsi, r14                    ; source = src_buf
    mov rcx, 4096
    call memcpy

    pop rdi
    pop rsi
    pop rcx

    ; Update pointers/counters
    add rbp, 4096                    ; total written += copied
    add r13, 4096                    ; file offset += copied
    add r14, 4096                    ; src_buf += copied
    sub r15, 4096                    ; count -= copied
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
    push rbp
    push r12
    push r13
    push r14
    push r15

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

    ; Write dirty folio back to mock storage page by page
    mov r12, [rbx + page_cache_entry_t.file_ptr]
    mov r13, [rbx + page_cache_entry_t.offset]
    mov r14, [rbx + page_cache_entry_t.phys_page]
    mov r15, [rbx + page_cache_entry_t.size]
    add r15, 4095
    shr r15, 12                     ; page count
    xor rbp, rbp                    ; loop index

.sync_loop:
    cmp rbp, r15
    jae .sync_done

    mov rsi, rbp
    shl rsi, 12
    add rsi, r13                    ; file offset

    mov rdx, rbp
    shl rdx, 12
    add rdx, r14                    ; physical address

    mov rdi, r12
    push r15
    push rbp
    call storage_write_file_page
    pop rbp
    pop r15

    inc rbp
    jmp .sync_loop

.sync_done:
    ; Clear dirty flag
    and qword [rbx + page_cache_entry_t.flags], ~2

.next:
    inc rcx
    jmp .loop

.done:
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
sys_folio_size:        dq 4096



section .bss

align 8
global sys_page_cache

sys_page_cache: resb page_cache_entry_t_size * PAGE_CACHE_MAX_ENTRIES

%endif ; LIB_MEM_VIRT_PAGE_CACHE_ASM
