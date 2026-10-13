; ============================================================================
; Ring Buffer — Single Producer Single Consumer (SPSC)
; Lock-free, power-of-2 capacity, cache-line aligned
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define Ring_buffer      0
%define Ring.buffer 0
%define Ring_capacity    8
%define Ring.capacity 8
%define Ring_mask        16
%define Ring.mask 16
%define Ring_head        24
%define Ring.head 24
%define Ring_tail        32
%define Ring.tail 32
%define Ring_element_size 40
%define Ring.element_size 40
%define Ring_arena       48
%define Ring.arena 48
%define Ring_size        56

section .text

; ---------------------------------------------------------------------------
; ring_init
;   Initialize ring buffer
;   IN:  rdi = ring pointer (Ring*)
;        rsi = arena
;        rdx = capacity (power of 2, min 4)
;        rcx = element_size (bytes)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ring_init
ring_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi        ; ring
    mov r12, rsi        ; arena
    mov r13, rdx        ; capacity
    mov r14, rcx        ; element_size
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r14, r14
    jnz .ok
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.ok:
    test r13, r13
    jnz .check_pow2
    mov r13, 4
.check_pow2:
    mov rax, r13
    dec rax
    test rax, r13
    jz .pow2_ok
    bsr rax, r13
    inc rax
    mov r13, 1
    shl r13, cl
.pow2_ok:

    ; Allocate buffer
    mov rdi, r12
    mov rsi, r14
    imul rsi, r13
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rbx + Ring.buffer], rax
    mov qword [rbx + Ring.capacity], r13
    mov qword [rbx + Ring.mask], r13
    dec qword [rbx + Ring.mask]
    mov qword [rbx + Ring.head], 0
    mov qword [rbx + Ring.tail], 0
    mov qword [rbx + Ring.element_size], r14
    mov qword [rbx + Ring.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; ring_push
;   Push element (producer only)
;   IN:  rdi = ring, rsi = element_ptr
;   OUT: rax = 0 OK, ENOSPC if full
; ---------------------------------------------------------------------------
global ring_push
ring_push:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Ring.head]
    mov rcx, [rbx + Ring.tail]
    mov rdx, [rbx + Ring.mask]

    ; Check full: (head + 1) & mask == tail
    lea r13, [rax + 1]
    and r13, rdx
    cmp r13, rcx
    je .full

    ; Copy element
    mov rdi, [rbx + Ring.buffer]
    mov rsi, r12
    mov rdx, [rbx + Ring.element_size]
    imul rax, rdx
    add rdi, rax
    call memcopy

    ; Update head
    mov rax, [rbx + Ring.head]
    inc rax
    and rax, [rbx + Ring.mask]
    mov [rbx + Ring.head], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; ring_pop
;   Pop element (consumer only)
;   IN:  rdi = ring, rsi = out_ptr
;   OUT: rax = 0 OK, EAGAIN if empty
; ---------------------------------------------------------------------------
global ring_pop
ring_pop:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Ring.head]
    mov rcx, [rbx + Ring.tail]
    cmp rax, rcx
    je .empty

    ; Copy element
    mov rdi, r12
    mov rsi, [rbx + Ring.buffer]
    mov rdx, [rbx + Ring.element_size]
    imul rcx, rdx
    add rsi, rcx
    call memcopy

    ; Update tail
    mov rcx, [rbx + Ring.tail]
    inc rcx
    and rcx, [rbx + Ring.mask]
    mov [rbx + Ring.tail], rcx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.empty:
    mov rax, -(EAGAIN)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; ring_peek
;   Peek at next element without popping
;   IN:  rdi = ring, rsi = out_ptr
;   OUT: rax = 0 OK, EAGAIN if empty
; ---------------------------------------------------------------------------
global ring_peek
ring_peek:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Ring.head]
    mov rcx, [rbx + Ring.tail]
    cmp rax, rcx
    je .empty

    mov rdi, r12
    mov rsi, [rbx + Ring.buffer]
    mov rdx, [rbx + Ring.element_size]
    imul rcx, rdx
    add rsi, rcx
    call memcopy
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.empty:
    mov rax, -(EAGAIN)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; ring_available
;   Get number of elements available to pop
;   IN:  rdi = ring
;   OUT: rax = count
; ---------------------------------------------------------------------------
global ring_available
ring_available:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Ring.head]
    mov rcx, [rdi + Ring.tail]
    sub rax, rcx
    and rax, [rdi + Ring.mask]
    leave
    ret

; ---------------------------------------------------------------------------
; ring_free
;   Get number of free slots
;   IN:  rdi = ring
;   OUT: rax = count
; ---------------------------------------------------------------------------
global ring_free
ring_free:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Ring.capacity]
    mov rcx, [rdi + Ring.head]
    mov rdx, [rdi + Ring.tail]
    sub rcx, rdx
    and rcx, [rdi + Ring.mask]
    sub rax, rcx
    dec rax
    leave
    ret

; ---------------------------------------------------------------------------
; ring_clear
;   Reset ring (producer and consumer must be synced)
;   IN:  rdi = ring
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global ring_clear
ring_clear:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + Ring.head], 0
    mov qword [rdi + Ring.tail], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; memcopy (internal)
; ---------------------------------------------------------------------------
memcopy:
    PROLOGUE_SAVE rbx, rcx
    mov rbx, rdi
    mov rcx, rdx
    test rcx, rcx
    jz .done
    rep movsb
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

section .data


global ring_version
ring_version: dq 0x010000
