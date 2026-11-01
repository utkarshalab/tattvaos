; ============================================================================
; Time Operations — Utkarsha Time Syscall Wrappers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

extern arena_alloc

section .text

; ---------------------------------------------------------------------------
; ut_time_ns_to_ms
;   Convert nanoseconds to milliseconds
;   IN:  rdi = nanoseconds
;   OUT: rax = milliseconds
; ---------------------------------------------------------------------------
global ut_time_ns_to_ms
ut_time_ns_to_ms:
    PROLOGUE
    mov rax, rdi
    mov rcx, 1000000
    xor rdx, rdx
    div rcx
    leave
    ret

; ---------------------------------------------------------------------------
; ut_time_ms_to_ns
;   Convert milliseconds to nanoseconds
;   IN:  rdi = milliseconds
;   OUT: rax = nanoseconds
; ---------------------------------------------------------------------------
global ut_time_ms_to_ns
ut_time_ms_to_ns:
    PROLOGUE
    mov rax, rdi
    mov rcx, 1000000
    mul rcx
    leave
    ret

; ---------------------------------------------------------------------------
; ut_time_add_ns
;   Add nanoseconds to timestamp
;   IN:  rdi = base_ns, rsi = add_ns
;   OUT: rax = result_ns (saturated at the largest time on overflow)
; ---------------------------------------------------------------------------
global ut_time_add_ns
ut_time_add_ns:
    mov rax, rdi
    add rax, rsi
    jnc .ok
    mov rax, -1
.ok:
    ret

; ---------------------------------------------------------------------------
; ut_time_sub_ns
;   Subtract nanoseconds
;   IN:  rdi = base_ns, rsi = sub_ns
;   OUT: rax = result_ns (0 if underflow)
; ---------------------------------------------------------------------------
global ut_time_sub_ns
ut_time_sub_ns:
    xor eax, eax
    cmp rdi, rsi
    jb .underflow
    mov rax, rdi
    sub rax, rsi
.underflow:
    ret

; ---------------------------------------------------------------------------
; canvas_timer_create
;   Create a timer
;   IN:  rdi = arena*, rsi = interval_ns, rdx = flags
;   OUT: rax = timer*, 0 on error
; ---------------------------------------------------------------------------
global canvas_timer_create
canvas_timer_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    test r12, r12
    jz .fail
    
    mov rdi, rbx
    mov rsi, 40
    call arena_alloc
    test rax, rax
    jz .oom
    
    mov qword [rax + 0], r12       ; interval_ns
    mov qword [rax + 8], 0         ; next_fire
    mov qword [rax + 16], 0        ; callback
    mov dword [rax + 24], r13d     ; flags
    mov qword [rax + 32], 0        ; user_data
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; canvas_timer_destroy
; ---------------------------------------------------------------------------
global canvas_timer_destroy
canvas_timer_destroy:
    PROLOGUE
    ASSERT_PTR rdi
    ; In a full impl, would free via arena
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; canvas_timer_arm
; ---------------------------------------------------------------------------
global canvas_timer_arm
canvas_timer_arm:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    
    sub rsp, 8                      ; 16-byte aligned at the call
    call ut_time_now_ns
    add rsp, 8
    add rax, [rbx + 0]  ; interval
    mov [rbx + 8], rax  ; next_fire
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; canvas_timer_cancel
; ---------------------------------------------------------------------------
global canvas_timer_cancel
canvas_timer_cancel:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + 8], 0
    leave
    ret

; ---------------------------------------------------------------------------
; canvas_timer_set_callback
; ---------------------------------------------------------------------------
global canvas_timer_set_callback
canvas_timer_set_callback:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov [rdi + 16], rsi
    mov [rdi + 32], rdx
    xor rax, rax
    leave
    ret

section .data
global time_version
time_version: dq 0x010000
