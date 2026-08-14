; =============================================================================
; Tattva OS — lib/mem/virt/rt_safe/coop_alloc.asm
; =============================================================================
; Cooperative Lockless Allocator (Feature 3).
; Allows user-space processes to submit allocation requests into a shared-memory
; ring buffer queue, bypassing system call context switches.
; The kernel polls the queue and processes allocations locklessly.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RT_SAFE_COOP_ALLOC_ASM
%define LIB_MEM_VIRT_RT_SAFE_COOP_ALLOC_ASM

[BITS 64]

; Cooperative Queue structure layout
struc coop_queue_t
    .head:      resq 1  ; Read index (Kernel updates)
    .tail:      resq 1  ; Write index (User updates)
    .capacity:  resq 1  ; Queue capacity (typically 512)
    .ring:      resq 512; Slots array holding page counts/addresses
endstruc

section .text


; -----------------------------------------------------------------------------
; coop_alloc_pages — submits page allocation request and polls for result
; Input:
;   RDI = ring_buffer_vaddr (Virtual pointer to coop_queue_t)
;   RSI = page_count        (Number of pages requested, power-of-two)
; Output:
;   RAX = allocated_phys_addr (0 if OOM or queue full)
; Clobbers: RAX, RCX, RDX, R8-R11
; -----------------------------------------------------------------------------
global coop_alloc_pages
coop_alloc_pages:
    push rbx
    push rbp

    mov rbp, rdi                    ; RBP = ring_buffer_vaddr
    mov r11, rsi                    ; R11 = page_count

    ; 1. Check if queue is full
    mov r8, [rbp + coop_queue_t.head]
    mov r9, [rbp + coop_queue_t.tail]
    mov r10, [rbp + coop_queue_t.capacity]

    ; active_slots = (tail - head) & (capacity - 1)
    mov rcx, r9
    sub rcx, r8
    mov rax, r10
    dec rax                         ; RAX = capacity - 1
    and rcx, rax                    ; RCX = active_slots

    ; If active_slots == capacity - 1, queue is full
    cmp rcx, rax
    jae .queue_full

    ; 2. Atomically claim tail slot
.retry_tail:
    mov r8, [rbp + coop_queue_t.tail]
    mov r9, r8
    inc r9
    mov rax, r10
    dec rax
    and r9, rax                     ; R9 = (tail + 1) & (capacity - 1)

    mov rax, r8                     ; expected value for CAS
    lock cmpxchg [rbp + coop_queue_t.tail], r9
    jnz .retry_tail

    ; 3. Write request (page count) to the claimed tail slot
    mov [rbp + coop_queue_t.ring + r8 * 8], r11

    ; If coop_test_mode is active, bypass spinning and return slot index directly
    cmp qword [coop_test_mode], 1
    je .test_mode_exit

    ; 4. Spin (poll) until head advances past our slot r8
    ; We check if the distance from head to r8 is outside the active region [head, tail)
.poll_loop:
    pause
    mov rcx, [rbp + coop_queue_t.head]
    mov rdx, [rbp + coop_queue_t.tail]

    ; dist_our = (r8 - head) & (capacity - 1)
    mov rax, r8
    sub rax, rcx
    mov rsi, r10
    dec rsi
    and rax, rsi                    ; RAX = dist_our

    ; active_len = (tail - head) & (capacity - 1)
    sub rdx, rcx
    and rdx, rsi                    ; RDX = active_len

    ; If dist_our >= active_len, then head has processed r8!
    cmp rax, rdx
    jb .poll_loop

    ; 5. Read the resulting physical address from our slot
    mov rax, [rbp + coop_queue_t.ring + r8 * 8]
    jmp .exit

.test_mode_exit:
    mov rax, r8                     ; Return raw slot index in RAX
    jmp .exit

.queue_full:
    xor rax, rax                    ; Return 0

.exit:
    pop rbp
    pop rbx
    ret

section .data
global coop_test_mode
coop_test_mode: dq 0

; -----------------------------------------------------------------------------
; coop_process_requests — processes all outstanding allocation requests in the queue
; Input:
;   RDI = ring_buffer_vaddr (Virtual pointer to coop_queue_t)
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global coop_process_requests
coop_process_requests:
    push rbx
    push rbp
    push r12
    push r13

    mov rbp, rdi                    ; RBP = ring_buffer_vaddr
    mov r12, [rbp + coop_queue_t.capacity]

.process_loop:
    mov rbx, [rbp + coop_queue_t.head]
    mov rdx, [rbp + coop_queue_t.tail]
    cmp rbx, rdx
    je .done                        ; Head == Tail, queue is empty

    ; Pop request (page count) from head slot
    mov rcx, [rbp + coop_queue_t.ring + rbx * 8]

    ; Calculate buddy order = log2(page_count)
    push rcx
    xor rdi, rdi                    ; RDI = order
.log_loop:
    shr rcx, 1
    jz .log_done
    inc rdi
    jmp .log_loop
.log_done:
    ; Call buddy allocator
    call buddy_alloc                ; RAX = physical address (or 0)
    pop rcx

    ; Write physical address back to the head slot
    mov [rbp + coop_queue_t.ring + rbx * 8], rax

    ; Increment head atomically (only kernel updates head, but write is atomic)
    mov rcx, rbx
    inc rcx
    mov rax, r12
    dec rax
    and rcx, rax                    ; RCX = (head + 1) & (capacity - 1)
    mov [rbp + coop_queue_t.head], rcx

    jmp .process_loop

.done:
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_RT_SAFE_COOP_ALLOC_ASM
