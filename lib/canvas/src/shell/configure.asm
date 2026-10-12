; ============================================================================
; Configure — Configure/Ack Transactions for Surface State
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Configure {
    .serial:            resq 1
    .surface:           resq 1
    .width:             resd 1
    .height:            resd 1
    .states:            resd 1
    .callback:          resq 1
    .user_data:         resq 1
    .ack_callback:      resq 1
}
%define Configure_size    48

%define CONFIGURE_STATE_NONE      0
%define CONFIGURE_STATE_SENT      1
%define CONFIGURE_STATE_ACKED     2
%define CONFIGURE_STATE_CANCELLED 3

; ---------------------------------------------------------------------------
; configure_init
; ---------------------------------------------------------------------------
global configure_init
configure_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.configure_serial], 0
    mov qword [rbx + Server.configure_list], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; configure_send
;   Send configure event to client
; ---------------------------------------------------------------------------
global configure_send
configure_send:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate configure object
    mov rdi, [rbx + Server.arena]
    mov rsi, Configure_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Fill configure
    mov rax, [rdi + Server.configure_serial]
    inc rax
    mov [rdi + Server.configure_serial], rax
    mov [rbx + Configure.serial], rax
    mov qword [rbx + Configure.surface], rsi
    mov dword [rbx + Configure.width], edx
    mov dword [rbx + Configure.height], r8d
    mov dword [rbx + Configure.states], r9d
    mov qword [rbx + Configure.callback], 0
    mov qword [rbx + Configure.user_data], 0
    mov qword [rbx + Configure.ack_callback], 0

    ; Add to pending list
    mov rax, [rdi + Server.configure_list]
    mov [rbx + Configure.next], rax
    mov [rdi + Server.configure_list], rbx

    ; Send cw_toplevel.configure or cw_surface.configure
    ; TODO: Encode and send via channel

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; configure_ack
;   Handle client ack
; ---------------------------------------------------------------------------
global configure_ack
configure_ack:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Find configure by serial
    mov rax, [rbx + Server.configure_list]
    test rax, rax
    jz .not_found

.find_loop:
    cmp qword [rax + Configure.serial], r12
    je .found
    mov rax, [rax + Configure.next]
    test rax, rax
    jnz .find_loop

.not_found:
    RETURN_ERROR ENOENT

.found:
    ; Call ack callback
    mov rax, [rax + Configure.ack_callback]
    test rax, rax
    jz .no_callback
    mov rdi, [rax + Configure.user_data]
    mov rsi, [rax + Configure.surface]
    call rax

.no_callback:
    ; Remove from list
    ; TODO: List removal

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; configure_cancel
;   Cancel pending configure
; ---------------------------------------------------------------------------
global configure_cancel
configure_cancel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find and remove
    mov rax, [rbx + Server.configure_list]
    test rax, rax
    jz .not_found
    cmp qword [rax + Configure.surface], r12
    je .remove_head

    mov rbx, rax
.find_loop:
    mov rax, [rax + Configure.next]
    test rax, rax
    jz .not_found
    cmp qword [rax + Configure.surface], r12
    je .remove_middle
    mov rbx, rax
    jmp .find_loop

.remove_head:
    mov rax, [rdi + Server.configure_list]
    mov rsi, [rax + Configure.next]
    mov [rbx + Server.configure_list], rsi
    jmp .done

.remove_middle:
    mov rax, [rax + Configure.next]
    mov [rbx + Configure.next], rax

.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; configure_get_pending
; ---------------------------------------------------------------------------
global configure_get_pending
configure_get_pending:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.configure_list]
    ret

section .data

%define Configure_serial    0
%define Configure_surface   8
%define Configure_width     16
%define Configure_height    20
%define Configure_states    24
%define Configure_callback  28
%define Configure_user_data 36
%define Configure_ack_callback 44
%define Configure_next      52
%define Configure_size      56

global configure_version
configure_version: dq 0x010000