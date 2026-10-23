; ============================================================================
; IME Bridge — Input Method Editor Bridge
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define IME_CAP_PREEDIT       (1 << 0)
%define IME_CAP_COMMIT        (1 << 1)
%define IME_CAP_SURROUNDING   (1 << 2)
%define IME_CAP_PREDICTION    (1 << 3)
%define IME_CAP_HANDWRITING   (1 << 4)

section .text

; ---------------------------------------------------------------------------
; ime_bridge_init
;   Initialize IME bridge
;   IN:  rdi = seat*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global ime_bridge_init
ime_bridge_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Seat.ime_bridge], 0
    mov qword [rbx + Seat.ime_arena], r12

    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; ime_bridge_create
;   Create IME bridge for seat
;   IN:  rdi = seat*, rsi = arena
;   OUT: rax = IMEBridge*, negative error
; ---------------------------------------------------------------------------
global ime_bridge_create
ime_bridge_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Seat.ime_arena]
    mov rsi, IMEBridge_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    mov qword [rax + IMEBridge.seat], rbx
    mov qword [rax + IMEBridge.active_ime], 0
    mov qword [rax + IMEBridge.available_imes], 0
    mov dword [rax + IMEBridge.ime_count], 0
    mov qword [rax + IMEBridge.focused_text_input], 0

    mov qword [rbx + Seat.ime_bridge], rax

    mov rax, r12
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; ime_bridge_add_ime
;   Add IME to available list
; ---------------------------------------------------------------------------
global ime_bridge_add_ime
ime_bridge_add_ime:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; IME record uses its first qword as the native next link.
    mov rax, [rbx + IMEBridge.available_imes]
    mov [r12], rax
    mov [rbx + IMEBridge.available_imes], r12
    inc dword [rbx + IMEBridge.ime_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; ime_bridge_set_active
;   Set active IME
; ---------------------------------------------------------------------------
global ime_bridge_set_active
ime_bridge_set_active:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + IMEBridge.active_ime], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global ime_bridge_version
ime_bridge_version: dq 0x010000
