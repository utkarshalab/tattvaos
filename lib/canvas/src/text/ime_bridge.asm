; ============================================================================
; IME Bridge — Input Method Editor Bridge
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc IMEBridge {
    .seat:              resq 1
    .active_ime:        resq 1
    .available_imes:    resq 1
    .ime_count:         resd 1
    .focused_text_input: resq 1
}
%define IMEBridge_size    48

struc IMEInfo {
    .name:          resq 1
    .id:            resq 1
    .capabilities:  resd 1
    .languages:     resq 1
    .next:          resq 1
}
%define IMEInfo_size    40

%define IME_CAP_PREEDIT       (1 << 0)
%define IME_CAP_COMMIT        (1 << 1)
%define IME_CAP_SURROUNDING   (1 << 2)
%define IME_CAP_PREDICTION    (1 << 3)
%define IME_CAP_HANDWRITING   (1 << 2)

; ---------------------------------------------------------------------------
; ime_bridge_init
; ---------------------------------------------------------------------------
global ime_bridge_init
ime_bridge_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.ime_bridge], 0
    mov qword [rbx + Server.arena], r12

    ; Allocate IME bridge
    mov rdi, r12
    mov rsi, IMEBridge_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + IMEBridge.seat], 0
    mov qword [rbx + IMEBridge.active_ime], 0
    mov qword [rbx + IMEBridge.available_imes], 0
    mov dword [rbx + IMEBridge.ime_count], 0
    mov qword [rbx + IMEBridge.focused_text_input], 0

    mov qword [rdi + Server.ime_bridge], rbx

    ; Load available IMEs
    call ime_bridge_load_imes

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; ime_bridge_load_imes
; ---------------------------------------------------------------------------
ime_bridge_load_imes:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Scan for available IME modules
    ; For now, create a default IME

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; ime_bridge_register_ime
; ---------------------------------------------------------------------------
global ime_bridge_register_ime
ime_bridge_register_ime:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate IME info
    mov rdi, [rbx + Server.arena]
    mov rsi, IMEInfo_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + IMEInfo.name], r12
    mov qword [rbx + IMEInfo.id], r13
    mov dword [rbx + IMEInfo.capabilities], 0
    mov qword [rbx + IMEInfo.languages], 0

    ; Add to list
    mov rax, [rdi + Server.ime_bridge]
    mov rax, [rax + IMEBridge.available_imes]
    mov [rbx + IMEInfo.next], rax
    mov qword [rdi + Server.ime_bridge + IMEBridge.available_imes], rbx
    inc dword [rdi + Server.ime_bridge + IMEBridge.ime_count]

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; ime_bridge_set_active_ime
; ---------------------------------------------------------------------------
global ime_bridge_set_active_ime
ime_bridge_set_active_ime:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + IMEBridge.active_ime], r12
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; ime_bridge_get_active_ime
; ---------------------------------------------------------------------------
global ime_bridge_get_active_ime
ime_bridge_get_active_ime:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.ime_bridge]
    mov rax, [rax + IMEBridge.active_ime]
    ret

; ---------------------------------------------------------------------------
; ime_bridge_set_focused_text_input
; ---------------------------------------------------------------------------
global ime_bridge_set_focused_text_input
ime_bridge_set_focused_text_input:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov qword [rbx + IMEBridge.focused_text_input], r12

    ; Notify active IME
    mov rax, [rbx + IMEBridge.active_ime]
    test rax, rax
    jz .done

    ; TODO: Notify IME of focus change

.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; ime_bridge_forward_key
;   Forward key event to active IME
; ---------------------------------------------------------------------------
global ime_bridge_forward_key
ime_bridge_forward_key:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    mov rax, [rbx + IMEBridge.active_ime]
    test rax, rax
    jz .no_ime

    ; TODO: Forward key to IME

.no_ime:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; ime_bridge_forward_preedit
;   Forward preedit string from IME
; ---------------------------------------------------------------------------
global ime_bridge_forward_preedit
ime_bridge_forward_preedit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + IMEBridge.focused_text_input]
    test rax, rax
    jz .no_focus

    ; Forward to text input
    mov rdi, rax
    call text_input_set_preedit_string

.no_focus:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; ime_bridge_forward_commit
;   Forward commit string from IME
; ---------------------------------------------------------------------------
global ime_bridge_forward_commit
ime_bridge_forward_commit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + IMEBridge.focused_text_input]
    test rax, rax
    jz .no_focus

    ; Forward to text input
    mov rdi, rax
    call text_input_commit_string

.no_focus:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; ime_bridge_forward_surrounding
;   Forward surrounding text from IME
; ---------------------------------------------------------------------------
global ime_bridge_forward_surrounding
ime_bridge_forward_surrounding:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + IMEBridge.focused_text_input]
    test rax, rax
    jz .no_focus

    ; Forward to text input
    mov rdi, rax
    call text_input_set_surrounding_text

.no_focus:
    xor rax, rax
    ret

section .data
global ime_bridge_version
ime_bridge_version: dq 0x010000