; ============================================================================
; Time Operations — Tattva Time Syscall Wrappers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

extern arena_alloc

section .text

; ---------------------------------------------------------------------------
; tv_time_ns_to_ms
;   Convert nanoseconds to milliseconds
;   IN:  rdi = nanoseconds
;   OUT: rax = milliseconds
; ---------------------------------------------------------------------------
global tv_time_ns_to_ms
tv_time_ns_to_ms:
    PROLOGUE
    mov rax, rdi
    mov rcx, 1000000
    xor rdx, rdx
    div rcx
    leave
    ret

; ---------------------------------------------------------------------------
; tv_time_ms_to_ns
;   Convert milliseconds to nanoseconds
;   IN:  rdi = milliseconds
;   OUT: rax = nanoseconds
; ---------------------------------------------------------------------------
global tv_time_ms_to_ns
tv_time_ms_to_ns:
    PROLOGUE
    mov rax, rdi
    mov rcx, 1000000
    mul rcx
    leave
    ret

; ---------------------------------------------------------------------------
; tv_time_add_ns
;   Add nanoseconds to timestamp
;   IN:  rdi = base_ns, rsi = add_ns
;   OUT: rax = result_ns
; ---------------------------------------------------------------------------
global tv_time_add_ns
tv_time_add_ns:
    PROLOGUE
    add rax, rsi
    leave
    ret

; ---------------------------------------------------------------------------
; tv_time_sub_ns
;   Subtract nanoseconds
;   IN:  rdi = base_ns, rsi = sub_ns
;   OUT: rax = result_ns (0 if underflow)
; ---------------------------------------------------------------------------
global tv_time_sub_ns
tv_time_sub_ns:
    PROLOGUE
    cmp rdi, rsi
    jb .underflow
    sub rax, rsi
    leave
    ret
.underflow:
    xor rax, rax
    leave
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
    
    leave
    ret
.fail:
    mov rax, -(EINVAL)
    leave
    ret
.oom:
    xor rax, rax
    leave
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
    
    call tv_time_now_ns
    add rax, [rbx + 0]  ; interval
    mov [rbx + 8], rax  ; next_fire
    xor rax, rax
    leave
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
