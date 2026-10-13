; ============================================================================
; Input Subsystem — Device Dispatcher and Event Processing
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/event.inc"

section .text

; ---------------------------------------------------------------------------
; input_init
;   Initialize input subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global input_init
input_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.input_sources], 0
    mov qword [rbx + Server.seats], 0
    mov qword [rbx + Server.seat_count], 0
    mov qword [rbx + Server.arena], r12

    ; Register Tattva input callback
    mov rdi, input_tattva_callback
    xor rsi, rsi
    call tv_input_register_callback
    test rax, rax
    jnz .fail

    ; Initialize input sources
    call input_source_tv_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; input_deinit
; ---------------------------------------------------------------------------
global input_deinit
input_deinit:
    PROLOGUE
    call tv_input_unregister_callback
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; input_tattva_callback
;   Callback from Tattva for raw input events
;   IN:  rdi = InputEvent*
; ---------------------------------------------------------------------------
input_tattva_callback:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Convert Tattva InputEvent to internal Event
    ; struct InputEvent { type, code, value, time_ns, device_id }
    ; struct Event { type, time, a, b, c }

    mov eax, [rbx + 0]    ; type
    mov [rsp + 0], eax
    mov rax, [rbx + 8]    ; time_ns
    mov [rsp + 8], rax
    mov eax, [rbx + 4]    ; code
    mov [rsp + 16], eax
    mov eax, [rbx + 12]   ; value
    mov [rsp + 20], eax
    mov eax, [rbx + 16]   ; device_id
    mov [rsp + 24], eax

    ; Dispatch to input source
    mov rdi, [rsp + 0]    ; type
    mov rsi, [rsp + 8]    ; time
    mov rdx, [rsp + 16]   ; code
    mov rcx, [rsp + 20]   ; value
    mov r8, [rsp + 24]    ; device_id

    call input_dispatch_event

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; input_dispatch_event
;   Dispatch event to appropriate device/seat
; ---------------------------------------------------------------------------
input_dispatch_event:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi        ; event type
    mov r12, rsi        ; time
    mov r13, rdx        ; code
    ; rcx = value, r8 = device_id

    ; Find device by device_id
    ; TODO: Device lookup

    ; For now, broadcast to all seats
    mov rdi, [rbx + Server.seats]
    test rdi, rdi
    jz .done

.seat_loop:
    ; Deliver event to seat
    mov rsi, rdi
    mov rdi, rbx
    call seat_deliver_event

    mov rdi, [rdi + Seat.next]
    test rdi, rdi
    jnz .seat_loop

.done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global input_version
input_version: dq 0x010000
