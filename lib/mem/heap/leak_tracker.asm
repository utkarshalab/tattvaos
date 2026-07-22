; =============================================================================
; Tattva OS — lib/mem/heap/leak_tracker.asm
; =============================================================================
; Memory Leak Tracker utility (Subfeature 19.1).
; Maps heap allocations, sizes, and return addresses to detect memory leaks.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_HEAP_LEAK_TRACKER_ASM
%define LIB_MEM_HEAP_LEAK_TRACKER_ASM

[BITS 64]

; Leak entry descriptor structure
struc leak_entry_t
    .ptr        resq 1          ; Allocated pointer
    .size       resq 1          ; Size of allocation in bytes
    .caller     resq 1          ; Return address of caller (IP)
endstruc

LEAK_MAX_ENTRIES equ 512

section .text



; -----------------------------------------------------------------------------
; leak_tracker_init — resets the tracking table
; Output: none
; -----------------------------------------------------------------------------
global leak_tracker_init
leak_tracker_init:
    push rdi
    push rcx
    push rax

    lea rdi, [leak_table]
    mov rcx, LEAK_MAX_ENTRIES * leak_entry_t_size / 8
    xor rax, rax
    cld
    rep stosq

    mov qword [leak_count], 0

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; leak_track_alloc — registers a new allocation
; Input:
;   RDI = allocated pointer
;   RSI = size in bytes
;   RDX = caller return address
; Output: none
; -----------------------------------------------------------------------------
global leak_track_alloc
leak_track_alloc:
    test rdi, rdi
    jz .done

    push rbx
    push rcx
    push rsi

    lea rbx, [leak_table]
    xor rcx, rcx
.loop:
    cmp rcx, LEAK_MAX_ENTRIES
    jge .done_pop

    mov rax, rcx
    imul rax, leak_entry_t_size
    mov rdx, [rbx + rax + leak_entry_t.ptr]
    test rdx, rdx
    jz .found

    inc rcx
    jmp .loop

.found:
    mov r8, rsi                     ; preserve size parameter
    mov rax, rcx
    imul rax, leak_entry_t_size
    mov [rbx + rax + leak_entry_t.ptr], rdi
    mov [rbx + rax + leak_entry_t.size], r8
    mov [rbx + rax + leak_entry_t.caller], r9 ; note: r9 holds caller return addr, wait let's look at rdx
    ; wait, caller was in RDX, size was in RSI, ptr was in RDI. 
    ; Let's check: RDI = pointer, RSI = size, RDX = caller.
    mov [rbx + rax + leak_entry_t.caller], rdx
    inc qword [leak_count]

.done_pop:
    pop rsi
    pop rcx
    pop rbx
.done:
    ret

; -----------------------------------------------------------------------------
; leak_track_free — unregisters a freed allocation
; Input:
;   RDI = freed pointer
; Output: none
; -----------------------------------------------------------------------------
global leak_track_free
leak_track_free:
    test rdi, rdi
    jz .done

    push rbx
    push rcx

    lea rbx, [leak_table]
    xor rcx, rcx
.loop:
    cmp rcx, LEAK_MAX_ENTRIES
    jge .done_pop

    mov rax, rcx
    imul rax, leak_entry_t_size
    mov rdx, [rbx + rax + leak_entry_t.ptr]
    cmp rdx, rdi
    je .found

    inc rcx
    jmp .loop

.found:
    mov rax, rcx
    imul rax, leak_entry_t_size
    mov qword [rbx + rax + leak_entry_t.ptr], 0
    mov qword [rbx + rax + leak_entry_t.size], 0
    mov qword [rbx + rax + leak_entry_t.caller], 0
    dec qword [leak_count]

.done_pop:
    pop rcx
    pop rbx
.done:
    ret

; -----------------------------------------------------------------------------
; leak_track_update_size — updates the size of a tracked block (for realloc)
; Input:
;   RDI = pointer
;   RSI = new size
; Output: none
; -----------------------------------------------------------------------------
global leak_track_update_size
leak_track_update_size:
    test rdi, rdi
    jz .done

    push rbx
    push rcx

    lea rbx, [leak_table]
    xor rcx, rcx
.loop:
    cmp rcx, LEAK_MAX_ENTRIES
    jge .done_pop

    mov rax, rcx
    imul rax, leak_entry_t_size
    mov rdx, [rbx + rax + leak_entry_t.ptr]
    cmp rdx, rdi
    je .found

    inc rcx
    jmp .loop

.found:
    mov rax, rcx
    imul rax, leak_entry_t_size
    mov [rbx + rax + leak_entry_t.size], rsi

.done_pop:
    pop rcx
    pop rbx
.done:
    ret

; -----------------------------------------------------------------------------
; heap_leak_report — prints details of all current leaks
; Output:
;   RAX = count of active leaks
; -----------------------------------------------------------------------------
global heap_leak_report
heap_leak_report:
    push rbx
    push r12
    push r13

    mov r12, [leak_count]           ; return value: leak count
    test r12, r12
    jz .no_leaks

    ; Print headers
    mov rsi, msg_leak_header
    call uart_print_str

    lea rbx, [leak_table]
    xor r13, r13                    ; index
.loop:
    cmp r13, LEAK_MAX_ENTRIES
    jge .done

    mov rax, r13
    imul rax, leak_entry_t_size
    mov rdx, [rbx + rax + leak_entry_t.ptr]
    test rdx, rdx
    jz .next

    ; Print Leak entry
    mov rsi, msg_leak_entry_prefix
    call uart_print_str

    ; Print pointer
    mov rax, r13
    imul rax, leak_entry_t_size
    mov rax, [rbx + rax + leak_entry_t.ptr]
    call uart_print_hex64

    mov rsi, msg_leak_entry_size
    call uart_print_str

    ; Print size
    mov rax, r13
    imul rax, leak_entry_t_size
    mov rax, [rbx + rax + leak_entry_t.size]
    call uart_print_hex64

    mov rsi, msg_leak_entry_caller
    call uart_print_str

    ; Print caller
    mov rax, r13
    imul rax, leak_entry_t_size
    mov rax, [rbx + rax + leak_entry_t.caller]
    call uart_print_hex64

    mov rsi, msg_crlf
    call uart_print_str

.next:
    inc r13
    jmp .loop
    jmp .done

.no_leaks:
    mov rsi, msg_no_leaks
    call uart_print_str

.done:
    mov rax, r12                    ; return leak count
    pop r13
    pop r12
    pop rbx
    ret

section .data

msg_leak_header:        db "==================== MEMORY LEAK REPORT ====================", 0x0D, 0x0A, 0
msg_leak_entry_prefix:  db "  [LEAK] Address: 0x", 0
msg_leak_entry_size:    db ", Size: 0x", 0
msg_leak_entry_caller:  db ", Caller: 0x", 0
msg_no_leaks:           db "No memory leaks detected.", 0x0D, 0x0A, 0

section .bss

align 8
global leak_table
leak_table: resb LEAK_MAX_ENTRIES * leak_entry_t_size
global leak_count
leak_count: resq 1

%endif ; LIB_MEM_HEAP_LEAK_TRACKER_ASM
