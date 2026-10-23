; ============================================================================
; Text Input — Input Method Protocol (cw_text)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/event.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

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
%define TEXT_CONTENT_HINT_HIDDEN       (1 << 5)
%define TEXT_CONTENT_HINT_SENSITIVE    (1 << 6)
%define TEXT_CONTENT_HINT_LATIN        (1 << 6)
%define TEXT_CONTENT_HINT_MULTILINE    (1 << 9)
%define TextInput.next 88

section .text

; ---------------------------------------------------------------------------
; text_input_init
;   Initialize text input
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global text_input_init
text_input_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.text_inputs], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; text_input_create
;   Create text input object
;   IN:  rdi = server*, rsi = seat*, rdx = text_input*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global text_input_create
text_input_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Allocate TextInput
    mov rdi, [rbx + Server.arena]
    mov rsi, TextInput_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax

    ; Initialize TextInput
    mov qword [r14 + TextInput.seat], r12
    mov qword [r14 + TextInput.surface], 0
    mov dword [r14 + TextInput.content_type], TEXT_CONTENT_TYPE_NORMAL
    mov dword [r14 + TextInput.content_hint], TEXT_CONTENT_HINT_NONE
    mov qword [r14 + TextInput.surrounding_text], 0
    mov dword [r14 + TextInput.cursor], 0
    mov dword [r14 + TextInput.anchor], 0
    mov qword [r14 + TextInput.preedit], 0
    mov dword [r14 + TextInput.content_purpose], 0
    mov dword [r14 + TextInput.content_hint], 0
    mov dword [r14 + TextInput.preedit_start], 0
    mov dword [r14 + TextInput.preedit_end], 0
    mov qword [r14 + TextInput.commit_text], 0
    mov qword [r14 + TextInput.delete_surrounding_text], 0
    mov dword [r14 + TextInput.keysym], 0
    mov dword [r14 + TextInput.state], 0
    mov qword [r14 + TextInput.preedit], 0

    mov rax, [rbx + Server.text_inputs]
    mov [r14 + TextInput.next], rax
    mov [rbx + Server.text_inputs], r14

    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

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

    lea rcx, [rbx + Server.text_inputs]
.destroy_find:
    mov rax, [rcx]
    test rax, rax
    jz .destroy_missing
    cmp rax, r12
    je .destroy_remove
    lea rcx, [rax + TextInput.next]
    jmp .destroy_find
.destroy_remove:
    mov rax, [r12 + TextInput.next]
    mov [rcx], rax
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.destroy_missing:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; text_input_set_content_type
; ---------------------------------------------------------------------------
global text_input_set_content_type
text_input_set_content_type:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput.content_type], r12d
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; text_input_set_content_hint
; ---------------------------------------------------------------------------
global text_input_set_content_hint
text_input_set_content_hint:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput.content_hint], r12d
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; text_input_set_surrounding_text
; ---------------------------------------------------------------------------
global text_input_set_surrounding_text
text_input_set_surrounding_text:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + TextInput.surrounding_text], r12
    mov [rbx + TextInput.cursor], r13d
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; text_input_set_cursor
; ---------------------------------------------------------------------------
global text_input_set_cursor
text_input_set_cursor:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov dword [rbx + TextInput.cursor], r12d
    mov dword [rbx + TextInput.anchor], r13d
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; text_input_commit
; ---------------------------------------------------------------------------
global text_input_commit
text_input_commit:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + TextInput.commit_text]
    test rax, rax
    jz .commit_done
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call rax
.commit_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; text_input_delete_surrounding_text
; ---------------------------------------------------------------------------
global text_input_delete_surrounding_text
text_input_delete_surrounding_text:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov rax, [rbx + TextInput.delete_surrounding_text]
    test rax, rax
    jz .delete_done
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call rax
.delete_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global text_input_version
text_input_version: dq 0x010000
