; ============================================================================
; Multiseat — Multiple Independent Seats Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

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

    mov [rbx + Server.arena],r12
    mov rdi,r12
    mov rsi,Multiseat_SIZE
    call arena_alloc
    test rax,rax
    jz .oom
    mov [rax + Multiseat.server],rbx
    mov qword [rax + Multiseat.seats],0
    mov dword [rax + Multiseat.seat_count],0
    mov qword [rax + Multiseat.default_seat],0
    mov [rbx + Server.multiseat],rax
    mov rdi,rax
    lea rsi,[rel default_seat_name]
    xor edx,edx
    xor ecx,ecx
    call multiseat_add_seat
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx,r12
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

    ; Configuration is supplied by the native session service. Ensure a
    ; deterministic default when it provides no seat records.
    cmp dword [rbx + Multiseat.seat_count],0
    jne .done
    mov rdi,rbx
    lea rsi,[rel default_seat_name]
    xor edx,edx
    xor ecx,ecx
    call multiseat_add_seat
.done:
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
    mov rdi,rbx
    mov rsi,r12
    call multiseat_init
    test rax,rax
    jnz .out
    mov rax,[rbx + Server.multiseat]
.out:
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
    mov rax,[rbx + Multiseat.server]
    mov rdi,[rax + Server.arena]
    mov rsi, Seat_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12,rax

    ; Initialize seat
    mov eax, [rbx + Multiseat.seat_count]
    mov dword [r12 + Seat.id], eax
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
    mov rax,[rbx + Multiseat.server]
    mov rdi,[rax + Server.arena]
    mov rsi, SeatSession_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [r12 + Seat.session], rax

    ; Initialize session
    mov qword [rax + SeatSession.seat],r12
    mov qword [rax + SeatSession.user_id],0
    mov byte [rax + SeatSession.active],0
    mov byte [rax + SeatSession.locked],0
    mov qword [rax + SeatSession.lock_surface],0
    mov qword [rax + SeatSession.idle_timer],0
    mov qword [rax + SeatSession.idle_timeout],300000000000
    mov dword [rax + SeatSession.inhibit_count],0
    mov qword [rax + SeatSession.power_inhibit],0

    ; Add to multiseat
    mov rax,[rbx + Multiseat.seats]
    mov [r12 + Seat.next], rax
    mov [rbx + Multiseat.seats],r12
    inc dword [rbx + Multiseat.seat_count]

    ; Set as default if first
    mov eax,[rbx + Multiseat.seat_count]
    cmp eax, 1
    jne .done
    mov [rbx + Multiseat.default_seat],r12

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
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    xor r13d,r13d
    mov rax,[rbx + Multiseat.seats]
.find:
    test rax,rax
    jz .missing
    cmp rax,r12
    je .unlink
    mov r13,rax
    mov rax,[rax + Seat.next]
    jmp .find
.unlink:
    mov rdx,[r12 + Seat.next]
    test r13,r13
    jz .head
    mov [r13 + Seat.next],rdx
    jmp .unlinked
.head:
    mov [rbx + Multiseat.seats],rdx
.unlinked:
    cmp [rbx + Multiseat.default_seat],r12
    jne .count
    mov [rbx + Multiseat.default_seat],rdx
.count:
    cmp dword [rbx + Multiseat.seat_count],0
    je .invalid
    dec dword [rbx + Multiseat.seat_count]
    mov rax,[r12 + Seat.session]
    test rax,rax
    jz .ok
    mov rdx,[rax + SeatSession.idle_timer]
    test rdx,rdx
    jz .ok
    mov rdi,rdx
    call tv_timer_cancel
.ok:
    xor eax,eax
    jmp .out
.missing:
    mov rax,-ENOENT
    jmp .out
.invalid:
    mov rax,-EINVAL
.out:
    EPILOGUE_RESTORE rbx, r12, r13
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

.find_done:
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
default_seat_name: db 'seat0',0
