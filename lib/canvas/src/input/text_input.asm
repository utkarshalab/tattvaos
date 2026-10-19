; ============================================================================
; Text Input / IME — Input Method Editor, Preedit, Surrounding Text
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; TextInput Struct
; ============================================================================
%define TextInput_SEAT           0
%define TextInput_SURFACE        8
%define TextInput_CONTENT_TYPE   16
%define TextInput_CONTENT_HINT   20
%define TextInput_SURROUNDING    24
%define TextInput_CURSOR         32
%define TextInput_ANCHOR         36
%define TextInput_PREEDIT        40
%define TextInput_CONTENT_PURPOSE 48
%define TextInput_CONTENT_HINT    52
%define TextInput_PREEDIT_START  56
%define TextInput_PREEDIT_END    60
%define TextInput_COMMIT_TEXT    64
%define TextInput_DELETE_SURROUND 72
%define TextInput_KEYSYM         80
%define TextInput_STATE          84
%define TextInput_PREEDIT_BUF    88
%define TextInput_SIZE           96

; Content types
%define CONTENT_TYPE_NORMAL       0
%define CONTENT_TYPE_PASSWORD     1
%define CONTENT_TYPE_TERMINAL     2

; Content hints
%define CONTENT_HINT_NONE         0
%define CONTENT_HINT_COMPLETION   (1 << 0)
%define CONTENT_HINT_SPELLCHECK   (1 << 1)
%define CONTENT_HINT_NO_SPELLCHECK (1 << 2)
%define CONTENT_HINT_AUTO_CORRECT  (1 << 3)
%define CONTENT_HINT_LOWERCASE    (1 << 4)
%define CONTENT_HINT_UPPERCASE    (1 << 5)
%define CONTENT_HINT_TITLECASE    (1 << 6)
%define CONTENT_HINT_HIDDEN_TEXT  (1 << 7)
%define CONTENT_HINT_SENSITIVE    (1 << 8)
%define CONTENT_HINT_LATIN        (1 << 9)
%define CONTENT_HINT_MULTILINE    (1 << 10)

; ============================================================================
; text_input_create
;   Create text input object
; ============================================================================
global text_input_create
text_input_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; seat
    mov r13, rdx       ; surface
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + TextInput_SEAT], r12
    mov qword [rbx + TextInput_SURFACE], r13
    mov dword [rbx + TextInput_CONTENT_TYPE], CONTENT_TYPE_NORMAL
    mov dword [rbx + TextInput_CONTENT_HINT], CONTENT_HINT_NONE
    mov qword [rbx + TextInput_SURROUNDING], 0
    mov dword [rbx + TextInput_CURSOR], 0
    mov dword [rbx + TextInput_ANCHOR], 0
    mov qword [rbx + TextInput_PREEDIT], 0
    mov dword [rbx + TextInput_CONTENT_PURPOSE], 0
    mov dword [rbx + TextInput_CONTENT_HINT], CONTENT_HINT_NONE
    mov dword [rbx + TextInput_PREEDIT_START], 0
    mov dword [rbx + TextInput_PREEDIT_END], 0
    mov qword [rbx + TextInput_COMMIT_TEXT], 0
    mov dword [rbx + TextInput_DELETE_SURROUND], 0
    mov dword [rbx + TextInput_KEYSYM], 0
    mov dword [rbx + TextInput_STATE], 0

    ; Link to seat
    mov rax, [r12 + Seat_TEXT_INPUTS]
    mov [rbx + TextInput_NEXT], rax
    mov [r12 + Seat_TEXT_INPUTS], rbx

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_destroy
;   Destroy text input
; ============================================================================
global text_input_destroy
text_input_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Unlink from seat
    mov r12, [rbx + TextInput_SEAT]
    call .unlink_from_seat

    ; Destroy preedit buffer
    mov rax, [rbx + TextInput_PREEDIT]
    test rax, rax
    jz .done
    call buffer_destroy

.done:
    xor rax, rax
    leave
    ret

.unlink_from_seat:
    mov r12, [rbx + TextInput_SEAT]
    mov rax, [r12 + Seat_TEXT_INPUTS]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + TextInput_NEXT]
    mov [r12 + Seat_TEXT_INPUTS], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + TextInput_NEXT]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + TextInput_NEXT]
    mov [r12 + TextInput_NEXT], rax

.done:
    ret

; ============================================================================
; text_input_set_content_type
;   Set content type (password, terminal, etc.)
; ============================================================================
global text_input_set_content_type
text_input_set_content_type:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput_CONTENT_TYPE], esi
    mov dword [rbx + TextInput_CONTENT_HINT], edx

    ; Notify IME
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_text_input_content_type

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_set_content_hint
;   Set content hint
; ============================================================================
global text_input_set_content_hint
text_input_set_content_hint:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput_CONTENT_HINT], esi

    ; Notify IME
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_text_input_content_hint

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_set_surrounding_text
;   Set surrounding text for IME
; ============================================================================
global text_input_set_surrounding_text
text_input_set_surrounding_text:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; text
    mov r13d, edx      ; cursor
    mov r14d, ecx      ; anchor
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + TextInput_SURROUNDING], r12
    mov dword [rbx + TextInput_CURSOR], r13d
    mov dword [rbx + TextInput_ANCHOR], r14d

    ; Notify IME
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r12
    mov edx, r13d
    mov ecx, r14d
    call surface_text_input_surrounding

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_set_cursor
;   Set cursor position
; ============================================================================
global text_input_set_cursor
text_input_set_cursor:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput_CURSOR], esi
    mov dword [rbx + TextInput_ANCHOR], edx

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_set_preedit
;   Set preedit string
; ============================================================================
global text_input_set_preedit
text_input_set_preedit:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi       ; text
    mov r13d, edx      ; cursor
    mov r14d, ecx      ; preedit_start
    mov r15d, r8d      ; preedit_end
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Store preedit string
    mov qword [rbx + TextInput_PREEDIT], r12
    mov dword [rbx + TextInput_PREEDIT_START], r14d
    mov dword [rbx + TextInput_PREEDIT_END], r15d

    ; Render preedit
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_render_preedit

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_commit
;   Commit text
; ============================================================================
global text_input_commit
text_input_commit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; text
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + TextInput_COMMIT_TEXT], r12

    ; Send to surface
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r12
    call surface_text_input_commit

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_delete_surrounding
;   Delete surrounding text
; ============================================================================
global text_input_delete_surrounding
text_input_delete_surrounding:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi       ; offset
    mov r13d, edx       ; length
    ASSERT_PTR rbx

    mov dword [rbx + TextInput_DELETE_SURROUND], r12d
    mov dword [rbx + TextInput_DELETE_SURROUND + 4], r13d

    ; Notify surface
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_text_input_delete_surrounding

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_keysym
;   Send keysym event
; ============================================================================
global text_input_keysym
text_input_keysym:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; keysym
    mov r13d, edx       ; state
    mov r14d, ecx       ; time
    ASSERT_PTR rbx

    mov dword [rbx + TextInput_KEYSYM], r12d
    mov dword [rbx + TextInput_STATE], r13d

    ; Send to surface
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call surface_text_input_keysym

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_set_state
;   Set text input state
; ============================================================================
global text_input_set_state
text_input_set_state:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + TextInput_STATE], esi

    ; Notify IME
    mov rax, [rbx + TextInput_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_text_input_state

    xor rax, rax
    leave
    ret

; ============================================================================
; text_input_reset
;   Reset text input state
; ============================================================================
global text_input_reset
text_input_reset:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Clear preedit
    mov qword [rbx + TextInput_PREEDIT], 0
    mov dword [rbx + TextInput_PREEDIT_START], 0
    mov dword [rbx + TextInput_PREEDIT_END], 0

    ; Clear commit text
    mov qword [rbx + TextInput_COMMIT_TEXT], 0

    ; Reset state
    mov dword [rbx + TextInput_STATE], 0
    mov dword [rbx + TextInput_CURSOR], 0
    mov dword [rbx + TextInput_ANCHOR], 0
    mov dword [rbx + TextInput_DELETE_SURROUND], 0

    xor rax, rax
    leave
    ret

section .data
global text_input_version
text_input_version: dq 0x010000