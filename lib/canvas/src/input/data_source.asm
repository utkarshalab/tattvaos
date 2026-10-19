; ============================================================================
; Data Source — Clipboard, Primary Selection, Drag-and-Drop
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; DataSource Struct
; ============================================================================
%define DataSource_OFFER_MIMES    0
%define DataSource_OFFER_COUNT    8
%define DataSource_ACTIONS        16
%define DataSource_TARGET         24
%define DataSource_SEND_FD        32
%define DataSource_DESTROY        40
%define DataSource_USER_DATA      48
%define DataSource_SIZE           56

; Action flags
%define ACTION_COPY      (1 << 0)
%define ACTION_MOVE      (1 << 1)
%define ACTION_ASK       (1 << 2)
%define ACTION_LINK      (1 << 3)

; ============================================================================
; data_source_create
;   Create data source
; ============================================================================
global data_source_create
data_source_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate data source
    mov rdi, r12
    mov rsi, DataSource_SIZE
    call arena_alloc
    test rax, rax
    jz .oom

    mov rbx, rax
    mov rdi, r12
    mov rsi, 16 * 8
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + DataSource_OFFER_MIMES], rax
    mov dword [rbx + DataSource_OFFER_COUNT], 0
    mov dword [rbx + DataSource_ACTIONS], 0
    mov qword [rbx + DataSource_TARGET], 0
    mov qword [rbx + DataSource_SEND_FD], 0
    mov qword [rbx + DataSource_DESTROY], 0
    mov qword [rbx + DataSource_USER_DATA], 0

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; data_source_destroy
;   Destroy data source
; ============================================================================
global data_source_destroy
data_source_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Call destroy callback if set
    mov rax, [rbx + DataSource_DESTROY]
    test rax, rax
    jz .done
    call rax

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; data_source_offer
;   Add MIME type offer
; ============================================================================
global data_source_offer
data_source_offer:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; mime_type string
    mov r13d, edx      ; length
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx + DataSource_OFFER_COUNT]
    cmp eax, 16
    jae .offer_full
    mov rcx, [rbx + DataSource_OFFER_MIMES]
    mov [rcx + rax * 8], r12
    inc dword [rbx + DataSource_OFFER_COUNT]

    xor rax, rax
    leave
    ret
.offer_full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; data_source_set_actions
;   Set available actions
; ============================================================================
global data_source_set_actions
data_source_set_actions:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + DataSource_ACTIONS], esi

    xor rax, rax
    leave
    ret

; ============================================================================
; data_source_set_target
;   Set target for drag-and-drop
; ============================================================================
global data_source_set_target
data_source_set_target:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov r12, rsi       ; surface
    ASSERT_PTR rbx

    mov qword [rbx + DataSource_TARGET], r12

    xor rax, rax
    leave
    ret

; ============================================================================
; data_source_send
;   Send data for MIME type
; ============================================================================
global data_source_send
data_source_send:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; mime_type
    mov r13, rdx       ; file descriptor
    ASSERT_PTR rbx

    mov [rbx + DataSource_SEND_FD], r13

    xor rax, rax
    leave
    ret

; ============================================================================
; data_source_set_destroy
;   Set destroy callback
; ============================================================================
global data_source_set_destroy
data_source_set_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov r12, rsi       ; callback
    ASSERT_PTR rbx

    mov qword [rbx + DataSource_DESTROY], r12

    xor rax, rax
    leave
    ret

; ============================================================================
; data_source_set_user_data
;   Set user data pointer
; ============================================================================
global data_source_set_user_data
data_source_set_user_data:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov qword [rbx + DataSource_USER_DATA], r12

    xor rax, rax
    leave
    ret

; ============================================================================
; data_source_get_user_data
;   Get user data pointer
; ============================================================================
global data_source_get_user_data
data_source_get_user_data:
    PROLOGUE
    mov rax, [rdi + DataSource_USER_DATA]
    leave
    ret

; ============================================================================
; data_source_action
;   Get/set current action
; ============================================================================
global data_source_action
data_source_action:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    test rsi, rsi
    jz .get

    mov dword [rbx + DataSource_ACTIONS], esi
    xor rax, rax
    leave
    ret

.get:
    mov eax, [rdi + DataSource_ACTIONS]
    leave
    ret

section .data
global data_source_version
data_source_version: dq 0x010000
