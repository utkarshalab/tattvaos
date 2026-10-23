; ============================================================================
; Fence — Binary Sync Primitive (CPU/GPU Waitable)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_table_init

; struct offsets (hoisted above use)
%define Fence_handle       0
%define Fence.handle 0
%define Fence_generation   4
%define Fence.generation 4
%define Fence_type         8
%define Fence.type 8
%define Fence_signaled     12
%define Fence.signaled 12
%define Fence_waiters      16
%define Fence.waiters 16
%define Fence_client_id    24
%define Fence.client_id 24
%define Fence_size         32
%define FENCE_CPU     0
%define FENCE_GPU     1
%define FENCE_TIMELINE 2

section .text

; ---------------------------------------------------------------------------
; fence_init
;   Initialize fence subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global fence_init
fence_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.arena], r12
    mov rdi, r12
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .init_oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    mov rdx, 1024
    call handle_table_init
    test rax, rax
    js .init_done
    mov [rbx + Server.fence_table], r13
.init_done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.init_oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
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
    mov r14, rax

    mov dword [r14 + Fence.handle], 0
    mov dword [r14 + Fence.generation], 0
    mov dword [r14 + Fence.type], r13d
    mov byte [r14 + Fence.signaled], 0
    mov qword [r14 + Fence.waiters], 0
    mov rax, [r12 + Client.id]
    mov qword [r14 + Fence.client_id], rax

    ; Create handle
    mov rdi, [rbx + Server.fence_table]
    mov rsi, r14
    call handle_create
    test rax, rax
    jz .oom
    mov [r14 + Fence.handle], eax

    mov eax, [r14 + Fence.handle]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; fence_destroy
;   Destroy fence
; ---------------------------------------------------------------------------
global fence_destroy
fence_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.fence_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov r13, rax
    mov byte [r13 + Fence.signaled], 1

    ; Destroy handle
    mov rdi, [rbx + Server.fence_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

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
    mov byte [rax + Fence.signaled], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fence_wait
;   Wait on fence
;   IN:  rdi = server*, rsi = fence_handle, rdx = timeout_ns
;   OUT: rax = 0 signaled, ETIMEDOUT, EINTR
; ---------------------------------------------------------------------------
global fence_wait
fence_wait:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.fence_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov [rsp], rax

    ; Check if already signaled
    cmp byte [rax + Fence.signaled], 1
    je .signaled

    cmp r13, -1
    je .wait
    call ut_time_now_ns
    add rax, r13
    jc .timed_out
    mov [rsp + 8], rax
.wait:
    call ut_wait_yield
    mov rax, [rsp]
    cmp byte [rax + Fence.signaled], 1
    je .signaled
    cmp r13, -1
    je .wait
    call ut_time_now_ns
    cmp rax, [rsp + 8]
    jb .wait
.timed_out:
    mov rax, -(ETIMEDOUT)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.signaled:
    xor rax, rax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_found:
    mov rax, -(ENOENT)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13
    ret

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
    EPILOGUE_RESTORE rbx
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx
    ret

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

    mov rdi, [rdi + Server.fence_table]
    call handle_resolve
    test rax, rax
    jz .not_found

    movzx rax, byte [rax + Fence.signaled]
    leave
    ret

.not_found:
    mov rax, -(ENOENT)
    leave
    ret

section .data



global fence_version
fence_version: dq 0x010000
