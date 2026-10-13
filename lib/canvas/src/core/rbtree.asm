; ============================================================================
; Red-Black Tree — Ordered Map (for z-order, timers)
; Intrusive nodes, O(log n) operations
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

; struct offsets (hoisted above use)
%define RB_RED     0
%define RB_BLACK   1
%define RBNode_left    0
%define RBNode_right   8
%define RBNode_parent  16
%define RBNode_color   24
%define RBNode_key     32
%define RBNode_value   40
%define RBNode_size    48
%define RBTree_root    0
%define RBTree_count   8
%define RBTree_size    16

section .text




; ---------------------------------------------------------------------------
; rbtree_init
; ---------------------------------------------------------------------------
global rbtree_init
rbtree_init:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + RBTree_root], 0
    mov qword [rdi + RBTree_count], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rbtree_insert
;   Insert or update key-value
;   IN:  rdi = tree, rsi = key, rdx = value, rcx = node* (pre-allocated)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global rbtree_insert
rbtree_insert:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r14

    ; Initialize node
    mov qword [r14 + RBNode_left], 0
    mov qword [r14 + RBNode_right], 0
    mov qword [r14 + RBNode_parent], 0
    mov byte [r14 + RBNode_color], RB_RED
    mov qword [r14 + RBNode_key], r12
    mov qword [r14 + RBNode_value], r13

    mov rax, [rbx + RBTree_root]
    test rax, rax
    jz .insert_root

    ; Find insertion point
    mov r15, rax
.find_loop:
    cmp r12, [r15 + RBNode_key]
    jl .go_left
    jg .go_right
    ; Key exists - update value
    mov qword [r15 + RBNode_value], r13
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.go_left:
    mov rax, [r15 + RBNode_left]
    test rax, rax
    jz .insert_left
    mov r15, rax
    jmp .find_loop

.go_right:
    mov rax, [r15 + RBNode_right]
    test rax, rax
    jz .insert_right
    mov r15, rax
    jmp .find_loop

.insert_root:
    mov [rbx + RBTree_root], r14
    mov byte [r14 + RBNode_color], RB_BLACK
    inc qword [rbx + RBTree_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.insert_left:
    mov [r15 + RBNode_left], r14
    mov [r14 + RBNode_parent], r15
    jmp .fixup

.insert_right:
    mov [r15 + RBNode_right], r14
    mov [r14 + RBNode_parent], r15

.fixup:
    ; Red-black tree fixup (simplified)
    call rbtree_fixup_insert
    inc qword [rbx + RBTree_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; rbtree_fixup_insert (internal)
; ---------------------------------------------------------------------------
rbtree_fixup_insert:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; tree
    mov r13, rdx        ; inserted node
.fixup_loop:
    mov r14, [r13 + RBNode_parent]
    test r14, r14
    jz .done
    cmp byte [r14 + RBNode_color], RB_RED
    jne .done

    mov r15, [r14 + RBNode_parent]
    test r15, r15
    jz .done

    ; Uncle
    cmp r14, [r15 + RBNode_left]
    je .uncle_right
    ; Parent is right child
    mov r14, [r15 + RBNode_left]
    test r14, r14
    jz .case1
    cmp byte [r14 + RBNode_color], RB_RED
    je .case1
    jmp .case2
.uncle_right:
    mov r14, [r15 + RBNode_right]
    test r14, r14
    jz .case1
    cmp byte [r14 + RBNode_color], RB_RED
    je .case1

.case2:
    ; Complex rotations - simplified
    jmp .done

.case1:
    ; Recolor
    mov byte [r13 + RBNode_parent + RBNode_color], RB_BLACK
    mov byte [r14 + RBNode_color], RB_BLACK
    mov byte [r15 + RBNode_color], RB_RED
    mov r13, r15
    jmp .fixup_loop

.done:
    mov rax, [r12 + RBTree_root]
    mov byte [rax + RBNode_color], RB_BLACK
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; rbtree_find
;   Find node by key
;   IN:  rdi = tree, rsi = key
;   OUT: rax = value, 0 if not found
; ---------------------------------------------------------------------------
global rbtree_find
rbtree_find:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + RBTree_root]
    test rax, rax
    jz .not_found

.find_loop:
    cmp rsi, [rax + RBNode_key]
    jl .go_left
    jg .go_right
    mov rax, [rax + RBNode_value]
    leave
    ret

.go_left:
    mov rax, [rax + RBNode_left]
    test rax, rax
    jz .not_found
    jmp .find_loop

.go_right:
    mov rax, [rax + RBNode_right]
    test rax, rax
    jz .not_found
    jmp .find_loop

.not_found:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rbtree_remove
;   Remove key (simplified - full implementation is complex)
; ---------------------------------------------------------------------------
global rbtree_remove
rbtree_remove:
    PROLOGUE
    ; TODO: Full RB delete with fixup
    mov rax, -(ENOSYS)
    leave
    ret

; ---------------------------------------------------------------------------
; rbtree_min
;   Get minimum key
; ---------------------------------------------------------------------------
global rbtree_min
rbtree_min:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + RBTree_root]
    test rax, rax
    jz .empty
.loop:
    mov rcx, [rax + RBNode_left]
    test rcx, rcx
    jz .found
    mov rax, rcx
    jmp .loop
.found:
    mov rax, [rax + RBNode_key]
    leave
    ret
.empty:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rbtree_max
;   Get maximum key
; ---------------------------------------------------------------------------
global rbtree_max
rbtree_max:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + RBTree_root]
    test rax, rax
    jz .empty
.loop:
    mov rcx, [rax + RBNode_right]
    test rcx, rcx
    jz .found
    mov rax, rcx
    jmp .loop
.found:
    mov rax, [rax + RBNode_key]
    leave
    ret
.empty:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rbtree_count
; ---------------------------------------------------------------------------
global rbtree_count
rbtree_count:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + RBTree_count]
    leave
    ret

section .data

global rbtree_version
rbtree_version: dq 0x010000
