; =============================================================================
; lib/io/async/submit.asm
; Lockless Single-Producer Single-Consumer (SPSC) queue submission path.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ASYNC_SUBMIT_ASM
%define IO_ASYNC_SUBMIT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; =============================================================================
; spsc_ring_push — Push a 64-bit pointer onto an SPSC ring buffer
; In : RDI = -> spsc_ring_t descriptor block
;      RSI = 64-bit entry value to push (e.g., io_request_t * or io_completion_t *)
; Out: RAX = 0 on success, or a negative error code (IO_ERR_QFULL) if full
; RSO: RDI, RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC spsc_ring_push
    guard_null rdi
    guard_null rsi

    push    rbx
    push    rcx
    push    rdx

    ; 1. Load indices
    mov     rax, [rdi + spsc_ring_t.prod_idx] ; RAX = producer index
    mov     rcx, [rdi + spsc_ring_t.cons_idx] ; RCX = consumer index

    ; 2. Check if the queue is full (prod_idx - cons_idx >= capacity)
    mov     rdx, rax
    sub     rdx, rcx                ; RDX = current queue depth
    mov     rbx, [rdi + spsc_ring_t.capacity]
    cmp     rdx, rbx
    jae     .err_full               ; Depth >= capacity, queue is full

    ; 3. Write entry to slot offset
    mov     rdx, [rdi + spsc_ring_t.mask]
    and     rdx, rax                ; RDX = masked slot index

    mov     rcx, [rdi + spsc_ring_t.entry_size]
    imul    rdx, rcx                ; RDX = offset in bytes
    add     rdx, [rdi + spsc_ring_t.buffer] ; RDX = address of target slot in buffer

    mov     [rdx], rsi              ; Write entry pointer to buffer slot

    ; 4. Memory store barrier to ensure slot write completes before index bump
    sfence

    ; 5. Increment producer index to make entry visible to consumer
    inc     rax
    mov     [rdi + spsc_ring_t.prod_idx], rax

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_full:
    mov     rax, IO_ERR_QFULL       ; Return queue full error

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC spsc_ring_push

%endif ; IO_ASYNC_SUBMIT_ASM
