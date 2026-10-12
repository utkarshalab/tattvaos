; ============================================================================
; Primary Selection — X11-style Primary Selection (Middle-click Paste)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; Uses same Clipboard struct as clipboard.asm
%define SELECTION_PRIMARY      1
%define SELECTION_CLIPBOARD    0

; ---------------------------------------------------------------------------
; selection_init
;   Initialize primary selection (shared with clipboard_init)
; ---------------------------------------------------------------------------
global selection_init
selection_init:
    PROLOGUE
    ; Primary selection is initialized in clipboard_init
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; selection_set
;   Set primary selection
;   IN:  rdi = server*, rsi = client*, rdx = mime_type, rcx = mime_len, r8 = data, r9 = data_len
; ---------------------------------------------------------------------------
global selection_set
selection_set:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check size limit
    cmp r9, CLIPBOARD_MAX_SIZE
    ja .too_large

    ; Get primary selection
    mov rbx, [rbx + Server.primary_selection]
    test rbx, rbx
    jz .fail

    ; Same logic as clipboard_set but for primary selection
    ; Free old data
    mov rax, [rbx + Clipboard.data]
    test rax, rax
    jz .no_old_data
    ; TODO: Free old data

.no_old_data:
    ; Allocate new data
    mov rdi, [r12 + Server.arena]
    mov rsi, r9
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Copy data
    mov rdi, rax
    mov rsi, r8
    mov rcx, r9
    call memcopy

    ; Copy mime type
    mov rdi, [r12 + Server.arena]
    mov rsi, r14
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov rdi, rax
    mov rsi, r13
    mov rcx, r14
    call memcopy

    ; Update primary selection
    mov rax, [rdi + Server.primary_selection]
    mov qword [rax + Clipboard.data], rbx
    mov qword [rax + Clipboard.data_len], r9
    mov qword [rax + Clipboard.mime_type], r12
    mov qword [rax + Clipboard.mime_type_len], r14
    mov qword [rax + Clipboard.source_client], rdi
    inc qword [rax + Clipboard.serial]

    ; Send selection event
    call selection_send_event

    xor rax, rax
    ret

.too_large:
    RETURN_ERROR ECLIP_SIZE
.fail:
    RETURN_ERROR ENOMEM
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; selection_get
;   Get primary selection
; ---------------------------------------------------------------------------
global selection_get
selection_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Server.primary_selection]
    test rax, rax
    jz .empty

    mov rax, [rax + Clipboard.data]
    mov rdx, [rax + Clipboard.data_len]
    ret

.empty:
    xor rax, rax
    xor rdx, rdx
    ret

; ---------------------------------------------------------------------------
; selection_send_event
; ---------------------------------------------------------------------------
selection_send_event:
    PROLOGUE
    ; TODO: Send primary selection event to clients
    ret

section .data
global selection_version
selection_version: dq 0x010000