; ============================================================================
; Preedit — Preedit String Management (Composition Text)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/str.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define PREEDIT_ATTR_UNDERLINE      1
%define PREEDIT_ATTR_HIGHLIGHT      2
%define PREEDIT_ATTR_INCORRECT      3
%define PREEDIT_ATTR_COMPOSING      4
%define PREEDIT_ATTR_CURSOR         5

section .text

; ---------------------------------------------------------------------------
; preedit_init
;   Initialize preedit string
;   IN:  rdi = preedit*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global preedit_init
preedit_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + PreeditString.text], 0
    mov qword [rbx + PreeditString.text_len], 0
    mov dword [rbx + PreeditString.cursor], 0
    mov dword [rbx + PreeditString.selection_start], 0
    mov dword [rbx + PreeditString.selection_end], 0
    mov qword [rbx + PreeditString.attributes], 0
    mov dword [rbx + PreeditString.attr_count], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; preedit_set_text
;   Set preedit text
; ---------------------------------------------------------------------------
global preedit_set_text
preedit_set_text:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Preedit text is borrowed until the next update; IME owns its lifetime.
    mov qword [rbx + PreeditString.text], r12
    mov qword [rbx + PreeditString.text_len], r13

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; preedit_set_cursor
;   Set cursor position
; ---------------------------------------------------------------------------
global preedit_set_cursor
preedit_set_cursor:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov eax, esi
    ASSERT_PTR rbx

    mov dword [rbx + PreeditString.cursor], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; preedit_add_attribute
;   Add attribute to preedit string
; ---------------------------------------------------------------------------
global preedit_add_attribute
preedit_add_attribute:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx

    mov eax, [rbx + PreeditString.attr_count]
    cmp eax, 64
    jae .attr_full
    mov rax, [rbx + PreeditString.attributes]
    test rax, rax
    jnz .attr_have_array
    mov rdi, r12
    mov rsi, 64 * PreeditAttribute_SIZE
    call arena_alloc
    test rax, rax
    jz .attr_oom
    mov [rbx + PreeditString.attributes], rax
.attr_have_array:
    mov edx, [rbx + PreeditString.attr_count]
    imul rdx, PreeditAttribute_SIZE
    add rax, rdx
    mov [rax + PreeditAttribute.type], r13d
    mov [rax + PreeditAttribute.start], r14d
    mov [rax + PreeditAttribute.end], r15d
    mov dword [rax + PreeditAttribute.color], 0
    inc dword [rbx + PreeditString.attr_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.attr_full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.attr_oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; preedit_clear
;   Clear preedit string
; ---------------------------------------------------------------------------
global preedit_clear
preedit_clear:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + PreeditString.text], 0
    mov qword [rbx + PreeditString.text_len], 0
    mov dword [rbx + PreeditString.cursor], 0
    mov dword [rbx + PreeditString.selection_start], 0
    mov dword [rbx + PreeditString.selection_end], 0
    mov qword [rbx + PreeditString.attributes], 0
    mov dword [rbx + PreeditString.attr_count], 0

    xor rax, rax
    leave
    ret

section .data
global preedit_version
preedit_version: dq 0x010000
