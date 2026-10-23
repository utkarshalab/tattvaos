; ============================================================================
; DPMS — Display Power Management Signaling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern canvas_timer_create
extern canvas_timer_set_callback
extern canvas_timer_arm
extern backend_dpms

; struct offsets (hoisted above use)
%define DPMS_ON       0
%define DPMS_STANDBY  1
%define DPMS_SUSPEND  2
%define DPMS_OFF      3
%define DPMS_STATE_ON         0
%define DPMS_STATE_STANDBY    1
%define DPMS_STATE_SUSPEND    2
%define DPMS_STATE_OFF        3

section .text


; ---------------------------------------------------------------------------
; dpms_init
; ---------------------------------------------------------------------------
global dpms_init
dpms_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; dpms_set
;   Set DPMS state for output
;   IN:  rdi = server*, rsi = output*, rdx = dpms_state
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global dpms_set
dpms_set:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp rdx, 3
    ja .invalid

    ; Call backend DPMS
    mov rdi, [rbx + Server.backend]
    mov rsi, r12
    mov rdx, r13
    call backend_dpms
    test rax, rax
    jnz .fail

    mov byte [r12 + Output.dpms_state], r13b
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; dpms_get
;   Get current DPMS state
; ---------------------------------------------------------------------------
global dpms_get
dpms_get:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + Output.dpms_state]
    leave
    ret

; ---------------------------------------------------------------------------
; dpms_timeout
;   Set DPMS timeout (for idle detection)
; ---------------------------------------------------------------------------
global dpms_timeout
dpms_timeout:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + Server.dpms_timeout], r12d
    mov [rbx + Server.dpms_suspend_timeout], rdx
    mov [rbx + Server.dpms_off_timeout], rcx

    ; Start idle timer
    call dpms_start_idle_timer

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; dpms_start_idle_timer
; ---------------------------------------------------------------------------
dpms_start_idle_timer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, [rel dpms_idle_timer]
    test rdi, rdi
    jnz .arm
    mov rdi, [rbx + Server.arena]
    mov esi, [rbx + Server.dpms_timeout]
    imul rsi, 1000000000
    mov rdx, 1
    call canvas_timer_create
    test rax, rax
    jz .failed
    mov [rel dpms_idle_timer], rax
    mov rdi, rax
    lea rsi, [rel dpms_idle_handler]
    mov rdx, rbx
    call canvas_timer_set_callback
.arm:
    mov rdi, [rel dpms_idle_timer]
    call canvas_timer_arm
    EPILOGUE_RESTORE rbx
    ret
.failed:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; dpms_idle_handler
;   Called when idle timeout expires
; ---------------------------------------------------------------------------
dpms_idle_handler:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Progress through DPMS states
    mov al, [rbx + Server.dpms_state]
    inc al
    cmp al, 3
    jg .max
    mov [rbx + Server.dpms_state], al

    ; Apply to all outputs
    mov r12, [rbx + Server.outputs]
.output_loop:
    test r12, r12
    jz .done

    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rbx + Server.dpms_state]
    call dpms_set

    mov r12, [r12 + Output.next]
    jmp .output_loop

.max:
    mov byte [rbx + Server.dpms_state], 3

.done:
    ; Restart timer for next state
    mov rdi, rbx
    call dpms_start_idle_timer

    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
dpms_idle_timer: dq 0


global dpms_version
dpms_version: dq 0x010000
