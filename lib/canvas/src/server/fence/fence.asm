; ============================================================================
; Fence — Binary Sync Primitive (CPU/GPU Waitable)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; fence_init
;   Initialize fence subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global fence_init
fence_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.fence_table], 0
    mov qword [rbx + Server.arena], r12
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; fence_create
;   Create binary fence
;   IN:  rdi = server*, rsi = client*, rdx = type (CPU=0, GPU=1, TIMELINE=2)
;   OUT: rax = fence_handle, negative error
; ---------------------------------------------------------------------------
global fence_create
fence_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate fence object
    ; struct Fence { handle, generation, type, signaled, waiters }
    mov rdi, [rbx + Server.arena]
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Fence.handle], 0
    mov qword [rbx + Fence.generation], 0
    mov dword [rbx + Fence.type], r13d
    mov byte [rbx + Fence.signaled], 0
    mov qword [rbx + Fence.waiters], 0
    mov qword [rbx + Fence.client_id], [r12 + Client.id]

    ; Create handle
    mov rdi, [rdi + Server.fence_table]
    mov rsi, rbx
    call handle_create
    test rax, rax
    jz .oom
    mov [rbx + Fence.handle], eax

    mov rax, [rbx + Fence.handle]
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; fence_destroy
;   Destroy fence
; ---------------------------------------------------------------------------
global fence_destroy
fence_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.fence_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; Wake any waiters
    ; TODO: Signal waiters

    ; Destroy handle
    mov rdi, [rdi + Server.fence_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; fence_signal
;   Signal fence
;   IN:  rdi = server*, rsi = fence_handle
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global fence_signal
fence_signal:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.fence_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov rbx, rax

    mov byte [rbx + Fence.signaled], 1

    ; Wake waiters
    ; TODO: Implement waiter wakeup

    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; fence_wait
;   Wait on fence
;   IN:  rdi = server*, rsi = fence_handle, rdx = timeout_ns
;   OUT: rax = 0 signaled, ETIMEDOUT, EINTR
; ---------------------------------------------------------------------------
global fence_wait
fence_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.fence_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; Check if already signaled
    cmp byte [rbx + Fence.signaled], 1
    je .signaled

    ; Wait on waitset
    ; TODO: Add to waitset and wait

.signaled:
    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; fence_reset
;   Reset fence to unsignaled
; ---------------------------------------------------------------------------
global fence_reset
fence_reset:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.fence_table]
    mov rsi, rsi
    call handle_resolve
    test rax, rax
    jz .not_found

    mov byte [rax + Fence.signaled], 0
    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; fence_get_status
;   Get fence status
;   IN:  rdi = server*, rsi = fence_handle
;   OUT: rax = 1 if signaled, 0 if not, negative error
; ---------------------------------------------------------------------------
global fence_get_status
fence_get_status:
    PROLOGUE
    ASSERT_PTR rdi

    mov rax, [rdi + Server.fence_table]
    call handle_resolve
    test rax, rax
    jz .not_found

    movzx rax, byte [rax + Fence.signaled]
    ret

.not_found:
    RETURN_ERROR ENOENT

section .data

%define Fence_handle       0
%define Fence_generation   4
%define Fence_type         8
%define Fence_signaled     12
%define Fence_waiters      16
%define Fence_client_id    24
%define Fence_size         32

%define FENCE_CPU     0
%define FENCE_GPU     1
%define FENCE_TIMELINE 2

global fence_version
fence_version: dq 0x010000