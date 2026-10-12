; ============================================================================
; Seat — Input Device Grouping (Keyboard, Pointer, Touch per Seat)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Seat {
    .id:            resd 1
    .name:          resq 1
    .pointer:       resq 1
    .keyboard:      resq 1
    .touch:         resq 1
    .tablet:        resq 1
    .focus:         resq 1
    .grab:          resq 1
    .keymap:        resq 1
    .repeat:        resq 1
    .pointer_accel: resq 1
    .constraints:   resq 1
    .cursor:        resq 1
    .devices:       resq 1
    .next:          resq 1
}
%define Seat_size    128

; ---------------------------------------------------------------------------
; seat_init
;   Initialize seat subsystem
; ---------------------------------------------------------------------------
global seat_init
seat_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.seats], 0
    mov qword [rbx + Server.seat_count], 0
    mov qword [rbx + Server.arena], r12

    ; Create default seat
    call seat_create_default

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_create_default
; ---------------------------------------------------------------------------
seat_create_default:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, [rbx + Server.arena]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate seat
    mov rdi, r12
    mov rsi, Seat_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    ; Fill seat
    mov dword [r13 + Seat.id], 0
    mov qword [r13 + Seat.name], default_seat_name
    mov qword [r13 + Seat.pointer], 0
    mov qword [r13 + Seat.keyboard], 0
    mov qword [r13 + Seat.touch], 0
    mov qword [r13 + Seat.tablet], 0
    mov qword [r13 + Seat.focus], 0
    mov qword [r13 + Seat.grab], 0
    mov qword [r13 + Seat.keymap], 0
    mov qword [r13 + Seat.repeat], 0
    mov qword [r13 + Seat.pointer_accel], 0
    mov qword [r13 + Seat.constraints], 0
    mov qword [r13 + Seat.cursor], 0
    mov qword [r13 + Seat.devices], 0
    mov qword [r13 + Seat.next], 0

    ; Create default keymap
    mov rdi, rbx
    mov rsi, r12
    call keymap_create_default
    test rax, rax
    jz .keymap_fail
    mov [r13 + Seat.keymap], rax

    ; Create repeat state
    mov rdi, r12
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r13 + Seat.repeat], rax

    ; Create pointer accel
    mov rdi, r12
    mov rsi, 64
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r13 + Seat.pointer_accel], rax

    ; Create cursor
    call cursor_create_default
    test rax, rax
    jz .oom
    mov [r13 + Seat.cursor], rax

    ; Add to seat list
    mov rax, [rbx + Server.seats]
    mov [r13 + Seat.next], rax
    mov [rbx + Server.seats], r13
    inc qword [rbx + Server.seat_count]

    mov qword [rbx + Server.default_seat], r13
    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM
.keymap_fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; seat_create
;   Create new seat with specific devices
; ---------------------------------------------------------------------------
global seat_create
seat_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi    ; name
    mov r13, rdx    ; device_list
    mov r14, rcx    ; device_count
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Create seat with specific devices
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_destroy
; ---------------------------------------------------------------------------
global seat_destroy
seat_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Remove from list, free resources
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_get_default
; ---------------------------------------------------------------------------
global seat_get_default
seat_get_default:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.default_seat]
    ret

; ---------------------------------------------------------------------------
; seat_deliver_event
;   Deliver event to seat
; ---------------------------------------------------------------------------
seat_deliver_event:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi    ; event type
    mov r12, rsi    ; seat
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Dispatch based on event type
    cmp rbx, INPUT_EVENT_KEY
    je .keyboard
    cmp rbx, INPUT_EVENT_REL
    je .pointer
    cmp rbx, INPUT_EVENT_ABS
    je .touch
    cmp rbx, INPUT_EVENT_SYN
    je .syn
    ret

.keyboard:
    ; Deliver to keyboard
    mov rdi, [r12 + Seat.keyboard]
    test rdi, rdi
    jz .done
    ; TODO: keyboard_process_key
    ret

.pointer:
    ; Deliver to pointer
    mov rdi, [r12 + Seat.pointer]
    test rdi, rdi
    jz .done
    ; TODO: pointer_process_motion
    ret

.touch:
    ; Deliver to touch
    mov rdi, [r12 + Seat.touch]
    test rdi, rdi
    jz .done
    ; TODO: touch_process
    ret

.syn:
    ; Sync event - commit frame
    ret

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .rodata
default_seat_name: db "seat0", 0

section .data
global seat_version
seat_version: dq 0x010000