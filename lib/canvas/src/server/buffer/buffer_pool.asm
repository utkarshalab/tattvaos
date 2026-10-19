; ============================================================================
; Buffer Pool — Reusable Buffer Management for Clients
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define BufferPool_buffers  0
%define BufferPool.buffers 0
%define BufferPool_count    8
%define BufferPool.count 8
%define BufferPool_capacity 16
%define BufferPool.capacity 16
%define BufferPool_arena    24
%define BufferPool.arena 24
%define BufferPool_size     32
%define Buffer_width         8
%define Buffer_height       12
%define Buffer_format       20
%define Buffer_state        84
%define Buffer_FREE          0
%define Buffer_ALLOCATED     1
%define Buffer_ATTACHED      2
%define Buffer_SCANOUT       3

section .text

; ---------------------------------------------------------------------------
; buffer_pool_init
;   Initialize buffer pool
;   IN:  rdi = pool*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global buffer_pool_init
buffer_pool_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + BufferPool.buffers], 0
    mov qword [rbx + BufferPool.count], 0
    mov qword [rbx + BufferPool.capacity], 0
    mov qword [rbx + BufferPool.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; buffer_pool_acquire
;   Acquire buffer from pool (or create new)
;   IN:  rdi = pool*, rsi = width, rdx = height, rcx = format
;   OUT: rax = buffer*, 0 if failed
; ---------------------------------------------------------------------------
global buffer_pool_acquire
buffer_pool_acquire:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    mov rdi, [rbx + BufferPool.buffers]
    mov rcx, [rbx + BufferPool.count]
    xor rdx, rdx
.search:
    cmp rdx, rcx
    jae .not_found
    mov rax, [rdi + rdx * 8]
    cmp byte [rax + Buffer_state], Buffer_FREE
    jne .next
    cmp dword [rax + Buffer_width], r12d
    jne .next
    cmp dword [rax + Buffer_height], r13d
    jne .next
    cmp dword [rax + Buffer_format], r14d
    jne .next
    mov byte [rax + Buffer_state], Buffer_ALLOCATED
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.next:
    inc rdx
    jmp .search
.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; buffer_pool_release
;   Return buffer to pool
;   IN:  rdi = pool*, rsi = buffer*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global buffer_pool_release
buffer_pool_release:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp byte [r12 + Buffer_state], Buffer_ATTACHED
    je .busy
    cmp byte [r12 + Buffer_state], Buffer_SCANOUT
    je .busy

    mov rdi, [rbx + BufferPool.buffers]
    mov rcx, [rbx + BufferPool.count]
    xor rdx, rdx
.dedupe:
    cmp rdx, rcx
    jae .ensure_capacity
    cmp [rdi + rdx * 8], r12
    je .already_pooled
    inc rdx
    jmp .dedupe

.ensure_capacity:
    cmp rcx, [rbx + BufferPool.capacity]
    jb .insert
    mov r13, [rbx + BufferPool.capacity]
    test r13, r13
    jnz .double
    mov r13, 16
    jmp .allocate
.double:
    shl r13, 1
    jc .oom
.allocate:
    mov rdi, [rbx + BufferPool.arena]
    mov rsi, r13
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov rdx, [rbx + BufferPool.count]
    shl rdx, 3
    test rdx, rdx
    jz .install
    mov rdi, r14
    mov rsi, [rbx + BufferPool.buffers]
    call memcopy
.install:
    mov [rbx + BufferPool.buffers], r14
    mov [rbx + BufferPool.capacity], r13
.insert:
    mov rdi, [rbx + BufferPool.buffers]
    mov rcx, [rbx + BufferPool.count]
    mov [rdi + rcx * 8], r12
    inc qword [rbx + BufferPool.count]
    mov byte [r12 + Buffer_state], Buffer_FREE
.already_pooled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.busy:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data


global buffer_pool_version
buffer_pool_version: dq 0x010000
