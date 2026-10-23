; ============================================================================
; Fence Operations — Synchronization Primitives
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

%define FENCE_STATE_UNSIGNALED  0
%define FENCE_STATE_SIGNALED    1
%define FENCE_STATE_ERROR       2

%define FENCE_FLAG_TIMELINE     (1 << 0)

; Fence structure:
;   state:       u32 (0=unsignaled, 1=signaled, 2=error)
;   timeline:    u64 (for timeline fences)
;   value:       u64 (for timeline fences)
;   waiters:     pointer to wait queue
;   lock:        spinlock

; The canonical handle-based fence lifecycle is implemented by fence.asm.
; Keep this legacy direct-object lifecycle out of the link while retaining the
; timeline extensions below.
%if 0

; ---------------------------------------------------------------------------
; fence_init
; ---------------------------------------------------------------------------
global fence_init
fence_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov dword [rbx + Fence.state], FENCE_STATE_UNSIGNALED
    mov qword [rbx + Fence.timeline], 0
    mov qword [rbx + Fence.value], 0
    mov qword [rbx + Fence.waiters], 0
    mov qword [rbx + Fence.lock], 0
    mov qword [rbx + Fence.arena], r12
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; fence_signal
; ---------------------------------------------------------------------------
global fence_signal
fence_signal:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    
    mov dword [rbx + Fence.state], FENCE_STATE_SIGNALED
    
    ; Wake all waiters
    mov r12, [rbx + Fence.waiters]
    test r12, r12
    jz .done
    
.wake_loop:
    test r12, r12
    jz .done
    mov r13, [r12 + WaitQueue.next]
    ; Wake thread (syscall)
    mov rdi, [r12 + WaitQueue.thread]
    mov rsi, 0
    SYSCALL SYS_THREAD_WAKE
    mov r12, r13
    jmp .wake_loop
    
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fence_wait
; ---------------------------------------------------------------------------
global fence_wait
fence_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    
    ; Fast path: already signaled
    cmp dword [rbx + Fence.state], FENCE_STATE_SIGNALED
    je .signaled
    cmp dword [rbx + Fence.state], FENCE_STATE_ERROR
    je .error
    
    test rsi, rsi
    jz .block
    
    ; Timeout wait
    call ut_time_now_ns
    add rax, rsi
    mov r12, rax
    
.wait_loop:
    cmp dword [rbx + Fence.state], FENCE_STATE_SIGNALED
    je .signaled
    cmp dword [rbx + Fence.state], FENCE_STATE_ERROR
    je .error
    call ut_time_now_ns
    cmp rax, r12
    jae .timeout
    pause
    jmp .wait_loop
    
.block:
    ; Add to wait queue
    ; (simplified - would need proper wait queue management)
    SYSCALL SYS_THREAD_SLEEP
    jmp .check_state
    
.check_state:
    cmp dword [rbx + Fence.state], FENCE_STATE_SIGNALED
    je .signaled
    cmp dword [rbx + Fence.state], FENCE_STATE_ERROR
    je .error
    jmp .block
    
.signaled:
    xor rax, rax
    leave
    ret
.error:
    mov rax, -(EIO)
    leave
    ret
.timeout:
    mov rax, -(ETIMEDOUT)
    leave
    ret

; ---------------------------------------------------------------------------
; fence_reset
; ---------------------------------------------------------------------------
global fence_reset
fence_reset:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Fence.state], FENCE_STATE_UNSIGNALED
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fence_destroy
; ---------------------------------------------------------------------------
global fence_destroy
fence_destroy:
    PROLOGUE
    ASSERT_PTR rdi
    ; Wake any waiters with error
    mov dword [rdi + Fence.state], FENCE_STATE_ERROR
    xor rax, rax
    leave
    ret

%endif

; ---------------------------------------------------------------------------
; fence_timeline_init
; ---------------------------------------------------------------------------
global fence_timeline_init
fence_timeline_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov dword [rbx + Fence.state], FENCE_STATE_UNSIGNALED
    mov qword [rbx + Fence.timeline], 1
    mov qword [rbx + Fence.value], 0
    mov qword [rbx + Fence.waiters], 0
    mov qword [rbx + Fence.lock], 0
    mov qword [rbx + Fence.arena], r12
    
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fence_timeline_signal
; ---------------------------------------------------------------------------
global fence_timeline_signal
fence_timeline_signal:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    
    cmp qword [rbx + Fence.timeline], 0
    je .not_timeline
    
    mov [rbx + Fence.value], r12
    
    ; Wake waiters with value <= r12
    mov r13, [rbx + Fence.waiters]
    test r13, r13
    jz .done
.wake_loop:
    test r13, r13
    jz .done
    mov r14, [r13 + WaitQueue.next]
    mov rdi, [r13 + WaitQueue.thread]
    mov rsi, [r13 + WaitQueue.value]
    cmp rsi, r12
    jg .next
    mov rsi, 0
    SYSCALL SYS_THREAD_WAKE
.next:
    mov r13, r14
    jmp .wake_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
.not_timeline:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; fence_timeline_wait
; ---------------------------------------------------------------------------
global fence_timeline_wait
fence_timeline_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    
    cmp qword [rbx + Fence.timeline], 0
    je .not_timeline
    
    cmp qword [rbx + Fence.value], r12
    jae .signaled
    
    test rdx, rdx
    jz .block
    
    mov r13, rdx
    call ut_time_now_ns
    add r13, rax
    
.wait_loop:
    cmp qword [rbx + Fence.value], r12
    jae .signaled
    call ut_time_now_ns
    cmp rax, r13
    jae .timeout
    pause
    jmp .wait_loop
    
.block:
    SYSCALL SYS_THREAD_SLEEP
    jmp .check
.check:
    cmp qword [rbx + Fence.value], r12
    jae .signaled
    jmp .block
    
.signaled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
.not_timeline:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
.timeout:
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13

section .data
global fence_timeline_version
fence_timeline_version: dq 0x010000
