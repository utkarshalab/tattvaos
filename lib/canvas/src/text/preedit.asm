; ============================================================================
; Preedit — Preedit String Management (Composition Text)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/str.inc"

section .text

struc PreeditString {
    .text:          resq 1
    .text_len:      resq 1
    .cursor:        resd 1
    .selection_start: resd 1
    .selection_end:   resd 1
    .attributes:    resq 1
    .attr_count:    resd 1
}
%define PreeditString_size    48

struc PreeditAttribute {
    .type:      resd 1
    .start:     resd 1
    .end:       resd 1
    .value:     resd 1
}
%define PreeditAttribute_size    16

%define PREEDIT_ATTR_UNDERLINE      1
%define PREEDIT_ATTR_HIGHLIGHT      2
%define PREEDIT_ATTR_INCORRECT      3
%define PREEDIT_ATTR_COMPOSING      4
%define PREEDIT_ATTR_CURSOR         5

; ---------------------------------------------------------------------------
; preedit_init
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
    ret

; ---------------------------------------------------------------------------
; preedit_set_text
; ---------------------------------------------------------------------------
global preedit_set_text
preedit_set_text:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Free old text
    mov rax, [rbx + PreeditString.text]
    test rax, rax
    jz .set_new

    ; TODO: Free old text

.set_new:
    ; Copy new text
    call str_dup_arena
    test rax, rax
    jz .oom
    mov qword [rbx + PreeditString.text], rax
    mov qword [rbx + PreeditString.text_len], r13

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; preedit_set_cursor
; ---------------------------------------------------------------------------
global preedit_set_cursor
preedit_set_cursor:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + PreeditString.cursor], esi
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; preedit_set_selection
; ---------------------------------------------------------------------------
global preedit_set_selection
preedit_set_selection:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + PreeditString.selection_start], esi
    mov dword [rdi + PreeditString.selection_end], edx
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; preedit_add_attribute
; ---------------------------------------------------------------------------
global preedit_add_attribute
preedit_add_attribute:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx

    ; Allocate attribute
    mov rdi, [rbx + Server.arena]
    mov rsi, PreeditAttribute_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov dword [rax + PreeditAttribute.type], r12d
    mov dword [rax + PreeditAttribute.start], r13d
    mov dword [rax + PreeditAttribute.end], r14d
    mov dword [rax + PreeditAttribute.value], r15d

    ; Add to attribute list
    ; TODO: Link into attribute list

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; preedit_clear_attributes
; ---------------------------------------------------------------------------
global preedit_clear_attributes
preedit_clear_attributes:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + PreeditString.attributes], 0
    mov dword [rdi + PreeditString.attr_count], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; preedit_get_text
; ---------------------------------------------------------------------------
global preedit_get_text
preedit_get_text:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + PreeditString.text]
    mov rdx, [rdi + PreeditString.text_len]
    ret

; ---------------------------------------------------------------------------
; preedit_get_cursor
; ---------------------------------------------------------------------------
global preedit_get_cursor
preedit_get_cursor:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + PreeditString.cursor]
    ret

section .data
global preedit_version
preedit_version: dq 0x010000