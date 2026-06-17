; =============================================================================
; Tattva OS — lib/mem/virt/dbg_watch.asm
; =============================================================================
; Emulated Page-Granular Dirty Bit Tracing & Watchpoints.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_DBG_WATCH_ASM
%define LIB_MEM_VIRT_DBG_WATCH_ASM

[BITS 64]

; Table limits
DBG_MAX_TRACED_PAGES equ 128
DBG_MAX_WATCHPOINTS  equ 128

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


; =============================================================================
; Page Watchpoint APIs
; =============================================================================

; -----------------------------------------------------------------------------
; dbg_watchpoint_init — initializes the watchpoints subsystem metadata
; -----------------------------------------------------------------------------
global dbg_watchpoint_init
dbg_watchpoint_init:
    push rdi
    push rcx
    push rax

    lea rdi, [dbg_wp_table]
    mov rcx, DBG_MAX_WATCHPOINTS
    xor rax, rax
    cld
    rep stosq

    lea rdi, [dbg_wp_flags]
    mov rcx, DBG_MAX_WATCHPOINTS
    rep stosq

    lea rdi, [dbg_wp_orig_pte]
    mov rcx, DBG_MAX_WATCHPOINTS
    rep stosq

    lea rdi, [dbg_wp_hit_count]
    mov rcx, DBG_MAX_WATCHPOINTS
    rep stosq

    lea rdi, [dbg_wp_last_rip]
    mov rcx, DBG_MAX_WATCHPOINTS
    rep stosq

    lea rdi, [dbg_wp_last_type]
    mov rcx, DBG_MAX_WATCHPOINTS
    rep stosq

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_register — registers page watchpoint and clears PRESENT in PTE
; Input:
;   RDI = virtual address to watch
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global dbg_watchpoint_register
dbg_watchpoint_register:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi                    ; rbx = virtual address
    and rbx, -4096                  ; align to page boundary

    ; 1. Walk page table to check if page is mapped and present
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .fail
    mov rcx, [rax]
    test rcx, 1                     ; PAGE_PRESENT
    jz .fail

    ; 2. Check if already registered
    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.dup_check:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .find_free
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .dup_next
    cmp qword [rdi + rcx * 8], rbx
    je .success
.dup_next:
    inc rcx
    jmp .dup_check

.find_free:
    ; 3. Find free slot
    xor rcx, rcx
.find_loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .fail
    cmp qword [dbg_wp_flags + rcx * 8], 0
    jz .found_free
    inc rcx
    jmp .find_loop

.found_free:
    ; Store metadata
    mov [rdi + rcx * 8], rbx
    mov qword [dbg_wp_flags + rcx * 8], 1
    
    ; Walk page table again to read current PTE state, and store it
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table
    mov rdx, [rax]                  ; RDX = original PTE value
    mov [dbg_wp_orig_pte + rcx * 8], rdx

    mov qword [dbg_wp_hit_count + rcx * 8], 0
    mov qword [dbg_wp_last_rip + rcx * 8], 0
    mov qword [dbg_wp_last_type + rcx * 8], 0

    ; 4. Clear PAGE_PRESENT to revoke all permissions (read & write)
    and qword [rax], ~1             ; clear PAGE_PRESENT (bit 0)

    ; 5. Invalidate TLB
    invlpg [rbx]

.success:
    mov rax, 1
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_handle_fault — checks if fault is on watchpoint, logs and makes present
; Input:
;   RDI = faulting virtual address
;   RSI = exception error code (bit 1 is write/read)
;   RDX = exception RIP
; Output:
;   RAX = 1 if fault handled (logged & restored), 0 if not tracked
; -----------------------------------------------------------------------------
global dbg_watchpoint_handle_fault
dbg_watchpoint_handle_fault:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi                    ; rbx = aligned address
    and rbx, -4096
    mov r8, rsi                     ; r8 = error code
    mov r9, rdx                     ; r9 = RIP of access instruction

    ; Search for address in watchpoints table
    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .not_found
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    ; Increment hit count
    inc qword [dbg_wp_hit_count + rcx * 8]
    mov [dbg_wp_last_rip + rcx * 8], r9

    ; Parse access type: write (1) if bit 1 of error code is set, else read (0)
    xor rdx, rdx
    test r8, 2                      ; bit 1 is Write
    jz .is_read
    mov rdx, 1                      ; 1 = write
.is_read:
    mov [dbg_wp_last_type + rcx * 8], rdx

    ; Restore original PTE (making it present again so the transaction completes)
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .error_restore
    mov r8, [dbg_wp_orig_pte + rcx * 8]
    mov [rax], r8                   ; write original present PTE back

    ; Invalidate TLB
    invlpg [rbx]

    mov rax, 1                      ; return 1 (handled)
    jmp .exit

.not_found:
.error_restore:
    xor rax, rax                    ; return 0 (not handled)

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_is_hit — returns the number of times this watchpoint has hit
; Input:
;   RDI = virtual address
; Output:
;   RAX = hit count, or 0 if not tracked
; -----------------------------------------------------------------------------
global dbg_watchpoint_is_hit
dbg_watchpoint_is_hit:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .not_found
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    mov rax, [dbg_wp_hit_count + rcx * 8]
    jmp .exit

.not_found:
    xor rax, rax

.exit:
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_get_last_rip — gets RIP of the instruction that hit the watchpoint
; Input:
;   RDI = virtual address
; Output:
;   RAX = RIP, or 0 if not hit/not tracked
; -----------------------------------------------------------------------------
global dbg_watchpoint_get_last_rip
dbg_watchpoint_get_last_rip:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .not_found
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    mov rax, [dbg_wp_last_rip + rcx * 8]
    jmp .exit

.not_found:
    xor rax, rax

.exit:
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_get_last_type — gets memory transaction type (0=read, 1=write)
; Input:
;   RDI = virtual address
; Output:
;   RAX = 0 (read) or 1 (write), or -1 if not tracked
; -----------------------------------------------------------------------------
global dbg_watchpoint_get_last_type
dbg_watchpoint_get_last_type:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .not_found
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    mov rax, [dbg_wp_last_type + rcx * 8]
    jmp .exit

.not_found:
    mov rax, -1

.exit:
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_rearm — write-protects/revokes present flag again for watchpoint
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global dbg_watchpoint_rearm
dbg_watchpoint_rearm:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .not_found
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    ; Read the current PTE, update saved original value (in case permissions changed)
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .fail
    mov r8, [rax]
    test r8, 1                      ; check if currently present
    jz .already_armed               ; if already non-present, it's already armed
    mov [dbg_wp_orig_pte + rcx * 8], r8

.already_armed:
    ; Revoke permissions (clear PRESENT bit)
    and qword [rax], ~1

    ; Invalidate TLB
    invlpg [rbx]

    mov rax, 1
    jmp .exit

.not_found:
.fail:
    xor rax, rax

.exit:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dbg_watchpoint_deregister — restores present flag and unregisters watchpoint
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global dbg_watchpoint_deregister
dbg_watchpoint_deregister:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi
    and rbx, -4096

    lea rdi, [dbg_wp_table]
    xor rcx, rcx
.loop:
    cmp rcx, DBG_MAX_WATCHPOINTS
    jge .not_found
    cmp qword [dbg_wp_flags + rcx * 8], 1
    jne .next
    cmp qword [rdi + rcx * 8], rbx
    je .found
.next:
    inc rcx
    jmp .loop

.found:
    ; Restore original present PTE value
    mov rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .clear_slot
    mov r8, [dbg_wp_orig_pte + rcx * 8]
    mov [rax], r8
    invlpg [rbx]

.clear_slot:
    mov qword [dbg_wp_flags + rcx * 8], 0
    mov qword [dbg_wp_table + rcx * 8], 0
    mov qword [dbg_wp_orig_pte + rcx * 8], 0
    mov qword [dbg_wp_hit_count + rcx * 8], 0
    mov qword [dbg_wp_last_rip + rcx * 8], 0
    mov qword [dbg_wp_last_type + rcx * 8], 0
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

align 8
dbg_wp_table:      resq DBG_MAX_WATCHPOINTS
dbg_wp_flags:      resq DBG_MAX_WATCHPOINTS
dbg_wp_orig_pte:   resq DBG_MAX_WATCHPOINTS
dbg_wp_hit_count:  resq DBG_MAX_WATCHPOINTS
dbg_wp_last_rip:   resq DBG_MAX_WATCHPOINTS
dbg_wp_last_type:  resq DBG_MAX_WATCHPOINTS

%endif ; LIB_MEM_VIRT_DBG_WATCH_ASM
