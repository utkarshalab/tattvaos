; ============================================================================
; Client Registry — RBTree by Client ID
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

; ---------------------------------------------------------------------------
; client_registry_init
;   Initialize client registry
;   IN:  rdi = registry*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global client_registry_init
client_registry_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, r12
    call rbtree_init
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; client_registry_add
;   Add client to registry
;   IN:  rdi = registry*, rsi = client_id, rdx = client*, rcx = arena*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global client_registry_add
client_registry_add:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate node
    mov rdi, r14
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rax], 0      ; left
    mov qword [rax + 8], 0  ; right
    mov qword [rax + 16], 0 ; parent
    mov byte [rax + 24], 1  ; color = RED
    mov qword [rax + 32], r12 ; key = client_id
    mov qword [rax + 40], r13 ; value = client*

    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    call rbtree_insert
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; client_registry_remove
;   Remove client from registry
;   IN:  rdi = registry*, rsi = client_id
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global client_registry_remove
client_registry_remove:
    PROLOGUE
    ASSERT_PTR rdi
    call rbtree_remove
    leave
    ret

; ---------------------------------------------------------------------------
; client_registry_find
;   Find client by ID
;   IN:  rdi = registry*, rsi = client_id
;   OUT: rax = client*, 0 if not found
; ---------------------------------------------------------------------------
global client_registry_find
client_registry_find:
    PROLOGUE
    ASSERT_PTR rdi
    call rbtree_find
    leave
    ret

section .data
global client_registry_version
client_registry_version: dq 0x010000
