; =============================================================================
; lib/io/async/complete.asm
; Lockless SPSC queue pop path and request completion logic.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ASYNC_COMPLETE_ASM
%define IO_ASYNC_COMPLETE_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; Declared in kernel scheduler
extern sched_wakeup

; =============================================================================
; spsc_ring_pop — Pop a 64-bit pointer from an SPSC ring buffer
; In : RDI = -> spsc_ring_t descriptor block
;      RSI = -> output variable pointer (to store popped entry value)
; Out: RAX = 0 on success, or 1 if the queue is empty
; RSO: RDI, RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC spsc_ring_pop
    guard_null rdi
    guard_null rsi

    push    rbx
    push    rcx
    push    rdx

    ; 1. Load indices
    mov     rax, [rdi + spsc_ring_t.cons_idx] ; RAX = consumer index
    mov     rcx, [rdi + spsc_ring_t.prod_idx] ; RCX = producer index

    ; 2. Check if empty (cons_idx == prod_idx)
    cmp     rax, rcx
    je      .empty                  ; Queue is empty

    ; 3. Read entry from slot offset
    mov     rdx, [rdi + spsc_ring_t.mask]
    and     rdx, rax                ; RDX = masked slot index

    mov     rcx, [rdi + spsc_ring_t.entry_size]
    imul    rdx, rcx                ; RDX = offset in bytes
    add     rdx, [rdi + spsc_ring_t.buffer] ; RDX = address of target slot in buffer

    mov     rbx, [rdx]              ; RBX = entry value
    mov     [rsi], rbx              ; Store popped value in output pointer

    ; 4. Memory read barrier to ensure slot read completes before index bump
    lfence

    ; 5. Increment consumer index to release slot
    inc     rax
    mov     [rdi + spsc_ring_t.cons_idx], rax

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.empty:
    mov     rax, 1                  ; Return 1 (Empty indicator)

.done:
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC spsc_ring_pop

; =============================================================================
; io_complete_request — Finalize an asynchronous request and wake up waiters
; In : RDI = -> io_request_t structure
;      RSI = Status code (0 on success, negative on error)
;      RDX = Result code (e.g. transfer bytes count)
; Out: RAX = 0 on success
; =============================================================================
IO_FUNC io_complete_request
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rbx, rdi                ; RBX = -> io_request_t
    mov     rcx, rsi                ; RCX = status code
    mov     r8, rdx                 ; R8  = result code

    ; 1. Update completion timestamp (rdtsc)
    rdtsc                           ; Loads TSC to EDX:EAX
    shl     rdx, 32
    or      rax, rdx                ; RAX = 64-bit TSC
    mov     [rbx + io_request_t.complete_tsc], rax

    ; 2. Determine state transition based on status code
    cmp     rcx, 0
    jl      .set_error              ; Negative status implies error

    ; Success completion
    mov     qword [rbx + io_request_t.state], IO_REQ_COMPLETE
    mov     qword [rbx + io_request_t.status], 0
    jmp     .set_result

.set_error:
    mov     qword [rbx + io_request_t.state], IO_REQ_ERROR
    mov     [rbx + io_request_t.status], rcx

.set_result:
    mov     [rbx + io_request_t.result], r8

    ; 3. Wake up scheduler waiter task if registered
    mov     rdi, [rbx + io_request_t.waiter]
    test    rdi, rdi
    jz      .done                   ; No waiter registered, complete

    ; Wake up the blocked thread task
    call    sched_wakeup

.done:
    xor     rax, rax                ; Return 0
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC io_complete_request

%endif ; IO_ASYNC_COMPLETE_ASM
