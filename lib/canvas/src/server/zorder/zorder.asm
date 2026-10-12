; ============================================================================
; Z-Order — Surface Stacking Order (RBTree)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; zorder_init
;   Initialize z-order subsystem
; ---------------------------------------------------------------------------
global zorder_init
zorder_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, r12
    call rbtree_init
    ret

; ---------------------------------------------------------------------------
; zorder_insert
;   Insert surface at z-position
;   IN:  rdi = server*, rsi = surface*, rdx = z_index
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global zorder_insert
zorder_insert:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate RBTree node
    mov rdi, [rbx + Server.arena]
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .oom

    ; Key = z_index << 32 | surface_id
    mov r12, rsi
    shl r12, 32
    or r12, [rsi + Surface.id]

    mov qword [rax], 0
    mov qword [rax + 8], 0
    mov qword [rax + 16], 0
    mov byte [rax + 24], 1
    mov qword [rax + 32], r12
    mov qword [rax + 40], rsi

    mov rdi, rbx
    call rbtree_insert
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; zorder_remove
;   Remove surface from z-order
; ---------------------------------------------------------------------------
global zorder_remove
zorder_remove:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r12, rsi
    shl r12, 32
    or r12, [rsi + Surface.id]

    mov rdi, rbx
    mov rsi, r12
    call rbtree_remove
    ret

; ---------------------------------------------------------------------------
; zorder_move
;   Move surface to new z-position
; ---------------------------------------------------------------------------
global zorder_move
zorder_move:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Remove old position
    mov r12, rsi
    shl r12, 32
    or r12, [rsi + Surface.id]

    mov rdi, rbx
    call rbtree_remove

    ; Insert at new position
    call zorder_insert
    ret

; ---------------------------------------------------------------------------
; zorder_above
;   Move surface above another
; ---------------------------------------------------------------------------
global zorder_above
zorder_above:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get target's z-index
    mov rax, [r13 + Surface.z_order]
    add rax, 1

    ; Move surface
    call zorder_move
    ret

; ---------------------------------------------------------------------------
; zorder_below
;   Move surface below another
; ---------------------------------------------------------------------------
global zorder_below
zorder_below:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get target's z-index
    mov rax, [r13 + Surface.z_order]
    sub rax, 1

    call zorder_move
    ret

; ---------------------------------------------------------------------------
; zorder_top
;   Move surface to top
; ---------------------------------------------------------------------------
global zorder_top
zorder_top:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find max z-index
    mov rdi, rbx
    call rbtree_max
    test rax, rax
    jz .empty

    add rax, 1
    mov rdx, rax
    call zorder_move
    ret

.empty:
    mov rdx, 1
    call zorder_move
    ret

; ---------------------------------------------------------------------------
; zorder_bottom
;   Move surface to bottom
; ---------------------------------------------------------------------------
global zorder_bottom
zorder_bottom:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find min z-index
    mov rdi, rbx
    call rbtree_min
    test rax, rax
    jz .empty

    sub rax, 1
    mov rdx, rax
    call zorder_move
    ret

.empty:
    mov rdx, 1
    call zorder_move
    ret

; ---------------------------------------------------------------------------
; zorder_iterate
;   Iterate surfaces in z-order (bottom to top)
;   IN:  rdi = server*, rsi = callback(surface*, user_data), rdx = user_data
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global zorder_iterate
zorder_iterate:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; In-order traversal
    ; TODO: Implement tree traversal
    xor rax, rax
    ret

section .data
global zorder_version
zorder_version: dq 0x010000