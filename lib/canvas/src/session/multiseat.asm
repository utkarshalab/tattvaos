; ============================================================================
; Multiseat — Multiple Independent Seats Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Multiseat_size    32

section .text

struc Multiseat
    .server:        resq 1
    .seats:         resq 1
    .seat_count:    resd 1
    .default_seat:  resq 1
endstruc

; ---------------------------------------------------------------------------
; multiseat_init
; ---------------------------------------------------------------------------
global multiseat_init
multiseat_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.multiseat], 0
    mov qword [rbx + Server.arena], r12

    ; Parse seats config
    call multiseat_parse_config

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; multiseat_parse_config
; ---------------------------------------------------------------------------
multiseat_parse_config:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Read seats.conf
    ; TODO: Parse config file

    ; For now, create default seat
    call multiseat_create_seat

    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; multiseat_create_seat
; ---------------------------------------------------------------------------
global multiseat_create_seat
multiseat_create_seat:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate multiseat
    mov rdi, [rbx + Server.arena]
    mov rsi, Multiseat_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Multiseat.server], r12
    mov qword [rbx + Multiseat.seats], 0
    mov dword [rbx + Multiseat.seat_count], 0
    mov qword [rbx + Multiseat.default_seat], 0

    ; Create first seat
    call multiseat_add_seat

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; multiseat_add_seat
; ---------------------------------------------------------------------------
global multiseat_add_seat
multiseat_add_seat:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate seat
    mov rdi, [rbx + Server.arena]
    mov rsi, Seat_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    ; Initialize seat
    mov qword [r12 + Seat.id], [rbx + Multiseat.seat_count]
    mov qword [r12 + Seat.name], r13
    mov qword [r12 + Seat.pointer], 0
    mov qword [r12 + Seat.keyboard], 0
    mov qword [r12 + Seat.touch], 0
    mov qword [r12 + Seat.tablet], 0
    mov qword [r12 + Seat.focus], 0
    mov qword [r12 + Seat.grab], 0
    mov qword [r12 + Seat.keymap], 0
    mov qword [r12 + Seat.repeat], 0
    mov qword [r12 + Seat.pointer_accel], 0
    mov qword [r12 + Seat.constraints], 0
    mov qword [r12 + Seat.cursor], 0
    mov qword [r12 + Seat.devices], 0
    mov qword [r12 + Seat.next], 0

    ; Create session for this seat
    mov rdi, [rdi + Server.arena]
    mov rsi, SeatSession_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [r12 + Seat.session], rax

    ; Initialize session
    mov rbx, rax
    mov qword [rbx + SeatSession.seat], r12
    mov qword [rbx + SeatSession.user_id], 0
    mov byte [rbx + SeatSession.active], 0
    mov byte [rbx + SeatSession.locked], 0
    mov qword [rbx + SeatSession.lock_surface], 0
    mov qword [rbx + SeatSession.idle_timer], 0
    mov qword [rbx + SeatSession.idle_timeout], 300000000000
    mov dword [rbx + SeatSession.inhibit_count], 0
    mov qword [rbx + SeatSession.power_inhibit], 0

    ; Add to multiseat
    mov rax, [rdi + Multiseat.seats]
    mov [r12 + Seat.next], rax
    mov [rdi + Multiseat.seats], r12
    inc dword [rdi + Multiseat.seat_count]

    ; Set as default if first
    mov eax, [rdi + Multiseat.seat_count]
    cmp eax, 1
    jne .done
    mov [rdi + Multiseat.default_seat], r12

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; multiseat_remove_seat
; ---------------------------------------------------------------------------
global multiseat_remove_seat
multiseat_remove_seat:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Remove seat from list
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; multiseat_get_seat
; ---------------------------------------------------------------------------
global multiseat_get_seat
multiseat_get_seat:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    mov rax, [rbx + Multiseat.seats]
.find_loop:
    test rax, rax
    jz .not_found
    cmp dword [rax + Seat.id], r12d
    je .found
    mov rax, [rax + Seat.next]
    jmp .find_loop

.find_loop:
    mov rax, [rax + Seat.next]
    test rax, rax
    jnz .find_loop

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.found:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; multiseat_get_default
; ---------------------------------------------------------------------------
global multiseat_get_default
multiseat_get_default:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Multiseat.default_seat]
    leave
    ret

section .data
global multiseat_version
multiseat_version: dq 0x010000
