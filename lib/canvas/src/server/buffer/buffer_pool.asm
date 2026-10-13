; ============================================================================
; Buffer Pool — Reusable Buffer Management for Clients
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

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

    ; Search for compatible buffer in pool
    ; TODO: Implement pool search

    ; For now, return 0 (not found)
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
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Add to pool
    ; TODO: Implement pool insert
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data


global buffer_pool_version
buffer_pool_version: dq 0x010000
