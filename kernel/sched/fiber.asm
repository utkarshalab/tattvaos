; =============================================================================
; Tattva OS — kernel/sched/fiber.asm
; =============================================================================
; Ring-0 Cooperative Fiber Creation, Context Switching, and Yield Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "sched/fiber.inc"

section .text

; -----------------------------------------------------------------------------
; fiber_system_init — Initialize global fiber pool
; Input:  none
; Output: RAX = 1 (success)
; -----------------------------------------------------------------------------
fiber_system_init:
    push rbx
    push rcx
    push rdi

    ; Zero out the global FCB array (FIBER_MAX_COUNT * fcb_t_size)
    mov rdi, fiber_pool
    mov rcx, (FIBER_MAX_COUNT * fcb_t_size) / 8
    xor rax, rax
    rep stosq

    mov qword [next_fiber_id], 1
    mov rax, 1

    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_create — Allocate and initialize a new Ring-0 fiber
; Input:  RDI = entry_point function pointer
;         RSI = argument (64-bit value passed in RDI to entry_point)
; Output: RAX = Pointer to new FCB (or 0 if out of memory/slots)
; -----------------------------------------------------------------------------
fiber_create:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = entry_point
    mov r13, rsi                    ; R13 = arg

    ; 1. Find a free FCB slot in fiber_pool
    mov rbx, fiber_pool
    mov ecx, FIBER_MAX_COUNT
.search_slot:
    cmp dword [rbx + fcb_t.state], FIBER_STATE_FREE
    je .slot_found
    add rbx, fcb_t_size
    loop .search_slot

    ; No free slots available
    xor rax, rax
    jmp .done

.slot_found:
    ; 2. Allocate 4 pages (16KB) for fiber stack
    mov rdi, 4
    call phys_alloc_pages
    test rax, rax
    jz .alloc_failed
    
    mov [rbx + fcb_t.stack_bottom], rax
    add rax, FIBER_STACK_SIZE
    mov [rbx + fcb_t.stack_top], rax

    ; 3. Setup FCB fields
    mov rax, [next_fiber_id]
    inc qword [next_fiber_id]
    mov [rbx + fcb_t.id], rax

    mov dword [rbx + fcb_t.state], FIBER_STATE_READY
    mov [rbx + fcb_t.entry_point], r12
    mov [rbx + fcb_t.arg], r13
    mov qword [rbx + fcb_t.time_slice], 0

    ; 4. Format the stack for initial fiber_switch return
    ; Stack grows down from stack_top.
    ; Layout for initial RSP:
    ;   [stack_top - 0x08] = fiber_entry_wrapper RIP
    ;   [stack_top - 0x10] = initial RBP (0)
    ;   [stack_top - 0x18] = initial RBX (0)
    ;   [stack_top - 0x20] = initial R12 (0)
    ;   [stack_top - 0x28] = initial R13 (0)
    ;   [stack_top - 0x30] = initial R14 (0)
    ;   [stack_top - 0x38] = initial R15 (0)
    mov rdx, [rbx + fcb_t.stack_top]
    
    sub rdx, 8
    mov qword [rdx], fiber_entry_wrapper

    sub rdx, 8
    mov qword [rdx], 0              ; RBP

    sub rdx, 8
    mov qword [rdx], 0              ; RBX

    sub rdx, 8
    mov qword [rdx], 0              ; R12

    sub rdx, 8
    mov qword [rdx], 0              ; R13

    sub rdx, 8
    mov qword [rdx], 0              ; R14

    sub rdx, 8
    mov qword [rdx], 0              ; R15

    ; Set initial RSP
    mov [rbx + fcb_t.rsp], rdx

    ; 5. Push new FCB to current core's ready queue
    mov rdi, rbx
    call sched_push_fiber

    mov rax, rbx                    ; Return FCB pointer
    jmp .done

.alloc_failed:
    xor rax, rax

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_yield — Yield current fiber and context switch to next ready fiber
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
fiber_yield:
    push rbx
    push rsi
    push rdi

    ; Get currently running FCB from CPU GS Base (+64)
    mov rdi, [gs:64]
    test rdi, rdi
    jz .yield_done

    ; If current fiber is RUNNING, set state back to READY and push to tail
    cmp dword [rdi + fcb_t.state], FIBER_STATE_RUNNING
    jne .select_next
    mov dword [rdi + fcb_t.state], FIBER_STATE_READY
    call sched_push_fiber

.select_next:
    ; Pop next ready FCB from queue
    call sched_pop_next_fiber
    test rax, rax
    jnz .switch_to_next

    ; If no fibers ready, fallback to idle event fiber
    mov rsi, [gs:72]                ; GS:72 = idle_fiber
    test rsi, rsi
    jz .yield_done
    jmp .do_switch

.switch_to_next:
    mov rsi, rax

.do_switch:
    cmp rdi, rsi
    je .yield_done                  ; Same fiber, no switch needed

    ; Update GS:64 to point to new fiber FCB
    mov [gs:64], rsi
    mov dword [rsi + fcb_t.state], FIBER_STATE_RUNNING

    ; Perform assembly context switch
    call fiber_switch

.yield_done:
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_exit — Called when a fiber finishes execution
; Input:  none
; Output: never returns (yields to next fiber)
; -----------------------------------------------------------------------------
fiber_exit:
    mov rdi, [gs:64]
    test rdi, rdi
    jz .halt

    ; Mark FCB as DEAD
    mov dword [rdi + fcb_t.state], FIBER_STATE_DEAD
    call fiber_yield

.halt:
    cli
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; fiber_entry_wrapper — Trampoline entry point for newly created fibers
; -----------------------------------------------------------------------------
fiber_entry_wrapper:
    mov rbx, [gs:64]                ; RBX = current FCB
    test rbx, rbx
    jz .exit

    mov rax, [rbx + fcb_t.entry_point]
    mov rdi, [rbx + fcb_t.arg]
    
    ; Execute fiber function
    call rax

.exit:
    call fiber_exit
    ret

; -----------------------------------------------------------------------------
; fiber_switch — Assembly low-level context switcher
; Input:  RDI = Old FCB pointer, RSI = New FCB pointer
; -----------------------------------------------------------------------------
fiber_switch:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov [rdi + fcb_t.rsp], rsp
    mov rsp, [rsi + fcb_t.rsp]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp

    ret

; -----------------------------------------------------------------------------
; Global Data
; -----------------------------------------------------------------------------
section .data

align 16
global fiber_pool
fiber_pool:     times (FIBER_MAX_COUNT * fcb_t_size) db 0

align 8
next_fiber_id:  dq 1
