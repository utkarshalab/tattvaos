; ============================================================================
; Text Input — Input Method Protocol (cw_text)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/event.inc"

section .text

struc TextInput {
    .seat:              resq 1
    .surface:           resq 1
    .preedit_string:    resq 1
    .preedit_cursor:    resd 1
    .preedit_selection: resd 1
    .commit_string:     resq 1
    .delete_range:      resd 1
    .surrounding_text:  resq 1
    .cursor_pos:        resd 1
    .anchor_pos:        resd 1
    .content_type:      resd 1
    .content_hint:      resd 1
    .enabled:           resb 1
    .pending_surrounding: resb 1
}
%define TextInput_size    80

%define TEXT_CONTENT_TYPE_NORMAL       0
%define TEXT_CONTENT_TYPE_PASSWORD     1
%define TEXT_CONTENT_TYPE_TERMINAL     2

%define TEXT_CONTENT_HINT_NONE         0
%define TEXT_CONTENT_HINT_COMPLETION   (1 << 0)
%define TEXT_CONTENT_HINT_SPELLCHECK   (1 << 1)
%define TEXT_CONTENT_HINT_NO_COMPLETION (1 << 2)
%define TEXT_CONTENT_HINT_LOWERCASE    (1 << 3)
%define TEXT_CONTENT_HINT_UPPERCASE    (1 << 4)
%define TEXT_CONTENT_HINT_TITLECASE    (1 << 5)
%define TEXT_CONTENT_HINT_HIDDEN       (1 << 6)
%define TEXT_CONTENT_HINT_SENSITIVE    (1 << 7)
%define TEXT_CONTENT_HINT_LATIN        (1 << 8)
%define TEXT_CONTENT_HINT_MULTILINE    (1 << 9)

; ---------------------------------------------------------------------------
; text_input_init
; ---------------------------------------------------------------------------
global text_input_init
text_input_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.text_inputs], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_create
;   Create text input for surface
; ---------------------------------------------------------------------------
global text_input_create
text_input_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate text input
    mov rdi, [rbx + Server.arena]
    mov rsi, TextInput_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + TextInput.seat], r13
    mov qword [rbx + TextInput.surface], r12
    mov qword [rbx + TextInput.preedit_string], 0
    mov dword [rbx + TextInput.preedit_cursor], 0
    mov dword [rbx + TextInput.preedit_selection], 0
    mov qword [rbx + TextInput.commit_string], 0
    mov dword [rbx + TextInput.delete_range], 0
    mov qword [rbx + TextInput.surrounding_text], 0
    mov dword [rbx + TextInput.cursor_pos], 0
    mov dword [rbx + TextInput.anchor_pos], 0
    mov dword [rbx + TextInput.content_type], TEXT_CONTENT_TYPE_NORMAL
    mov dword [rbx + TextInput.content_hint], 0
    mov byte [rbx + TextInput.enabled], 1
    mov byte [rbx + TextInput.pending_surrounding], 0

    ; Set surface role
    mov dword [r12 + Surface.role], SHELL_ROLE_TOPLEVEL
    mov qword [r12 + Surface.text_input], rbx

    ; Add to server list
    mov rax, [r13 + Server.text_inputs]
    mov [rbx + TextInput.next], rax
    mov [r13 + Server.text_inputs], rbx

    ; Notify IME
    call text_input_send_enable

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; text_input_destroy
; ---------------------------------------------------------------------------
global text_input_destroy
text_input_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Notify IME
    call text_input_send_disable

    ; Remove from list
    ; TODO

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_enable
; ---------------------------------------------------------------------------
global text_input_enable
text_input_enable:
    PROLOGUE
    ASSERT_PTR rdi
    mov byte [rdi + TextInput.enabled], 1
    call text_input_send_enable
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_disable
; ---------------------------------------------------------------------------
global text_input_disable
text_input_disable:
    PROLOGUE
    ASSERT_PTR rdi
    mov byte [rdi + TextInput.enabled], 0
    call text_input_send_disable
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_send_enable
; ---------------------------------------------------------------------------
text_input_send_enable:
    PROLOGUE
    ; TODO: Send cw_text.enable event
    ret

; ---------------------------------------------------------------------------
; text_input_send_disable
; ---------------------------------------------------------------------------
text_input_send_disable:
    PROLOGUE
    ; TODO: Send cw_text.disable event
    ret

; ---------------------------------------------------------------------------
; text_input_commit_string
;   Client commits text
; ---------------------------------------------------------------------------
global text_input_commit_string
text_input_commit_string:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Store commit string
    mov qword [rbx + TextInput.commit_string], r12
    mov dword [rbx + TextInput.delete_range], r13d

    ; Send commit to client
    ; TODO: Send cw_text.commit_string

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_set_preedit_string
;   IME sets preedit string
; ---------------------------------------------------------------------------
global text_input_set_preedit_string
text_input_set_preedit_string:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx

    ; Store preedit
    mov qword [rbx + TextInput.preedit_string], r12
    mov dword [rbx + TextInput.preedit_cursor], r13d
    mov dword [rbx + TextInput.preedit_selection], r14d

    ; Send preedit to client
    ; TODO: Send cw_text.preedit_string

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_delete_surrounding_text
; ---------------------------------------------------------------------------
global text_input_delete_surrounding_text
text_input_delete_surrounding_text:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, esi
    mov [rbx + TextInput.delete_range], eax
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_set_surrounding_text
; ---------------------------------------------------------------------------
global text_input_set_surrounding_text
text_input_set_surrounding_text:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx

    mov qword [rbx + TextInput.surrounding_text], r12
    mov dword [rbx + TextInput.cursor_pos], r13d
    mov dword [rbx + TextInput.anchor_pos], r14d
    mov byte [rbx + TextInput.pending_surrounding], 1

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_set_content_type
; ---------------------------------------------------------------------------
global text_input_set_content_type
text_input_set_content_type:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput.content_type], r12d
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; text_input_set_content_hint
; ---------------------------------------------------------------------------
global text_input_set_content_hint
text_input_set_content_hint:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput.content_hint], r12d
    xor rax, rax
    ret

section .data
global text_input_version
text_input_version: dq 0x010000