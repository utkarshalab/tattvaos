; ============================================================================
; Touch — Multi-Touch Input Handling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define TouchSlot_size    32
%define Touch_size    48
%define TOOL_TYPE_FINGER    0
%define TOOL_TYPE_PEN       1
%define TOOL_TYPE_ERASER    2
%define TOOL_TYPE_MOUSE     3
%define TOUCH_DOWN    1
%define TOUCH_UP      2
%define TOUCH_MOTION  3
%define TOUCH_CANCEL  4

section .text

struc TouchSlot
    .tracking_id:   resd 1
    .x:             resd 1
    .y:             resd 1
    .pressure:      resd 1
    .major:         resd 1
    .minor:         resd 1
    .orientation:   resd 1
    .tool_type:     resb 1
    .active:        resb 1
endstruc

struc Touch
    .seat:          resq 1
    .slots:         resq 1
    .num_slots:     resd 1
    .max_slots:     resd 1
    .active_slots:  resd 1
    .surface:       resq 1
endstruc



; ---------------------------------------------------------------------------
; touch_create
; ---------------------------------------------------------------------------
global touch_create
touch_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, Touch_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Touch.seat], r12
    mov qword [rbx + Touch.slots], 0
    mov dword [rbx + Touch.num_slots], 0
    mov dword [rbx + Touch.max_slots], 10
    mov dword [rbx + Touch.active_slots], 0
    mov qword [rbx + Touch.surface], 0

    ; Allocate slots
    mov rdi, [rbx + Server.arena]
    mov rsi, 10
    imul rsi, TouchSlot_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Touch.slots], rax

    mov dword [rbx + Touch.num_slots], 10
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; touch_process
;   Process touch event
; ---------------------------------------------------------------------------
global touch_process
touch_process:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi      ; slot
    mov r13d, edx      ; type
    mov r14d, ecx      ; x
    mov r15d, r8d      ; y
    ASSERT_PTR rbx

    ; Get slot
    mov rax, [rbx + Touch.slots]
    add rax, r12
    imul rax, TouchSlot_size
    mov r12, rax

    cmp r13d, TOUCH_DOWN
    je .down
    cmp r13d, TOUCH_UP
    je .up
    cmp r13d, TOUCH_MOTION
    je .motion
    cmp r13d, TOUCH_CANCEL
    je .cancel
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.down:
    mov dword [r12 + TouchSlot.tracking_id], r15d
    mov dword [r12 + TouchSlot.x], r14d
    mov dword [r12 + TouchSlot.y], r15d
    mov byte [r12 + TouchSlot.active], 1
    inc dword [rbx + Touch.active_slots]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.up:
    mov byte [r12 + TouchSlot.active], 0
    dec dword [rbx + Touch.active_slots]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.motion:
    cmp byte [r12 + TouchSlot.active], 0
    je .ret
    mov dword [r12 + TouchSlot.x], r14d
    mov dword [r12 + TouchSlot.y], r15d
.ret:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.cancel:
    mov byte [r12 + TouchSlot.active], 0
    dec dword [rbx + Touch.active_slots]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; touch_get_slot
; ---------------------------------------------------------------------------
global touch_get_slot
touch_get_slot:
    PROLOGUE
    ASSERT_PTR rdi
    movzx eax, byte [rdi + TouchSlot.active]
    leave
    ret

section .data
global touch_version
touch_version: dq 0x010000
