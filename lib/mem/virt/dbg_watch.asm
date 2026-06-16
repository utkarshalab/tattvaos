; =============================================================================
; Tattva OS — lib/mem/virt/dbg_watch.asm
; =============================================================================
; Emulated Page-Granular Dirty Bit Tracing & Watchpoints (Subfeature 29.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_DBG_WATCH_ASM
%define LIB_MEM_VIRT_DBG_WATCH_ASM

[BITS 64]

; Table limits
DBG_MAX_TRACED_PAGES equ 128

section .text

; External page table walk function
extern virt_walk_table

; -----------------------------------------------------------------------------
; dbg_dirty_trace_init — initializes the dirty tracing subsystem metadata
; -----------------------------------------------------------------------------
global dbg_dirty_trace_init
dbg_dirty_trace_init:
    push rdi
    push rcx
    push rax

    lea rdi, [dbg_trace_table]
    mov rcx, DBG_MAX_TRACED_PAGES
    xor rax, rax
    cld
    rep stosq

    lea rdi, [dbg_trace_flags]
    mov rcx, DBG_MAX_TRACED_PAGES
    rep stosq

    lea rdi, [dbg_trace_dirty]
    mov rcx, DBG_MAX_TRACED_PAGES
    rep stosq

    lea rdi, [dbg_trace_rip]
    mov rcx, DBG_MAX_TRACED_PAGES
    rep stosq

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; dbg_dirty_trace_register — write-protects page and registers it for tracing
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global dbg_dirty_trace_register
dbg_dirty_trace_register:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi                    ; rbx = virtual address
    and rbx, -4096                  ; align to 4KB page boundary

    ; 1. Walk page table to check if page is mapped and present
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE virtual pointer
    test rax, rax
    jz .fail
    mov rcx, [rax]
    test rcx, 1                     ; PAGE_PRESENT (bit 0)
    jz .fail
    test rcx, 2                     ; PAGE_WRITABLE (bit 1)
    jz .fail                        ; only trace pages that are meant to be writable

    ; 2. Check if address is already registered in the table
    lea rdi, [dbg_trace_table]
    xor rcx, rcx
.dup_check:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .find_free
    cmp qword [dbg_trace_flags + rcx * 8], 1
    jne .dup_next
    cmp qword [rdi + rcx * 8], rbx
    je .success                     ; already tracked, return success
.dup_next:
    inc rcx
    jmp .dup_check

.find_free:
    ; 3. Find a free slot in the table
    xor rcx, rcx
.find_loop:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .fail                       ; table is full!
    cmp qword [dbg_trace_flags + rcx * 8], 0
    jz .found_free
    inc rcx
    jmp .find_loop

.found_free:
    ; Save the virtual address & initialize metadata
    mov [rdi + rcx * 8], rbx
    mov qword [dbg_trace_flags + rcx * 8], 1
    mov qword [dbg_trace_dirty + rcx * 8], 0
    mov qword [dbg_trace_rip + rcx * 8], 0

    ; 4. Clear PAGE_WRITABLE in the page's PTE to write-protect it
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .fail
    and qword [rax], ~2             ; clear PAGE_WRITABLE (bit 1)

    ; 5. Invalidate TLB for the page
    invlpg [rbx]

.success:
    mov rax, 1                      ; return 1 (success)
    jmp .exit

.fail:
    xor rax, rax                    ; return 0 (failure)

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_dirty_trace_handle_fault — checks if fault is on tracked page, logs and makes writable
; Input:
;   RDI = faulting virtual address
;   RSI = exception RIP (instruction causing write fault)
; Output:
;   RAX = 1 if fault handled (and page updated), 0 if not tracked
; -----------------------------------------------------------------------------
global dbg_dirty_trace_handle_fault
dbg_dirty_trace_handle_fault:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi                    ; rbx = faulting virtual address
    and rbx, -4096                  ; align to page boundary
    mov r8, rsi                     ; r8 = return RIP of write instruction

    ; Search for aligned address in tracking table
    lea rdi, [dbg_trace_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .not_found
    cmp qword [dbg_trace_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    ; Mark page as dirty (modified) and record the instruction RIP
    mov qword [dbg_trace_dirty + rcx * 8], 1
    mov [dbg_trace_rip + rcx * 8], r8

    ; Restore writable flag in the page table so execution can resume and write can occur
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .error_restore
    or qword [rax], 2               ; set PAGE_WRITABLE (bit 1)

    ; Invalidate TLB for this virtual address
    invlpg [rbx]

    mov rax, 1                      ; return handled (1)
    jmp .exit

.not_found:
.error_restore:
    xor rax, rax                    ; return unhandled (0)

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_dirty_trace_is_dirty — queries if page has been written to since tracing started
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 if dirty, 0 if clean/not tracked
; -----------------------------------------------------------------------------
global dbg_dirty_trace_is_dirty
dbg_dirty_trace_is_dirty:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_trace_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .not_found
    cmp qword [dbg_trace_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    mov rax, [dbg_trace_dirty + rcx * 8]
    jmp .exit

.not_found:
    xor rax, rax

.exit:
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_dirty_trace_get_rip — gets RIP of the instruction that dirtied the page
; Input:
;   RDI = virtual address
; Output:
;   RAX = RIP of instruction, or 0 if clean/not tracked
; -----------------------------------------------------------------------------
global dbg_dirty_trace_get_rip
dbg_dirty_trace_get_rip:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_trace_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .not_found
    cmp qword [dbg_trace_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    mov rax, [dbg_trace_rip + rcx * 8]
    jmp .exit

.not_found:
    xor rax, rax

.exit:
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_dirty_trace_clear_dirty — clears dirty status and write-protects page again
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global dbg_dirty_trace_clear_dirty
dbg_dirty_trace_clear_dirty:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_trace_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .not_found
    cmp qword [dbg_trace_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    ; Reset dirty state and saved RIP
    mov qword [dbg_trace_dirty + rcx * 8], 0
    mov qword [dbg_trace_rip + rcx * 8], 0

    ; Write-protect the page again
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .fail
    and qword [rax], ~2             ; clear PAGE_WRITABLE (bit 1)

    ; Invalidate TLB
    invlpg [rbx]

    mov rax, 1                      ; return 1 (success)
    jmp .exit

.not_found:
.fail:
    xor rax, rax                    ; return 0 (failure)

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_dirty_trace_deregister — stops tracking and restores write permissions
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global dbg_dirty_trace_deregister
dbg_dirty_trace_deregister:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_trace_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_TRACED_PAGES
    jge .not_found
    cmp qword [dbg_trace_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    ; Restore writable flag just in case it is currently write-protected
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .clear_slot
    or qword [rax], 2               ; set PAGE_WRITABLE (bit 1)
    invlpg [rbx]

.clear_slot:
    mov qword [dbg_trace_flags + rcx * 8], 0
    mov qword [dbg_trace_table + rcx * 8], 0
    mov qword [dbg_trace_dirty + rcx * 8], 0
    mov qword [dbg_trace_rip + rcx * 8], 0
    mov rax, 1
    jmp .exit

.not_found:
    xor rax, rax

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

section .bss

align 8
dbg_trace_table: resq DBG_MAX_TRACED_PAGES
dbg_trace_flags: resq DBG_MAX_TRACED_PAGES
dbg_trace_dirty: resq DBG_MAX_TRACED_PAGES
dbg_trace_rip:   resq DBG_MAX_TRACED_PAGES

%endif ; LIB_MEM_VIRT_DBG_WATCH_ASM
