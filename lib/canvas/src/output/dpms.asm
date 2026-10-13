; ============================================================================
; DPMS — Display Power Management Signaling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define DPMS_ON       0
%define DPMS_STANDBY  1
%define DPMS_SUSPEND  2
%define DPMS_OFF      3
%define Output_dpms_state   81
%define Output.dpms_state 81
%define Server_dpms_state        0x90
%define Server.dpms_state 0x90
%define Server_dpms_timeout      0x94
%define Server.dpms_timeout 0x94
%define Server_dpms_suspend_timeout 0x98
%define Server.dpms_suspend_timeout 0x98
%define Server_dpms_off_timeout  0x9C
%define Server.dpms_off_timeout 0x9C

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
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp rdx, 3
    ja .invalid

    ; Call backend DPMS
    mov rdi, [rbx + Server.backend]
    mov rsi, r12
    call backend_dpms
    test rax, rax
    jnz .fail

    mov byte [r12 + Output.dpms_state], dl
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
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
    PROLOGUE
    ; TODO: Register timer with tv_timer_register
    leave
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
    call dpms_start_idle_timer

    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data



global dpms_version
dpms_version: dq 0x010000
