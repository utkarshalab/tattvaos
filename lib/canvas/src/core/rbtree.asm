; ============================================================================
; Red-Black Tree — Ordered Map (for z-order, timers)
; Intrusive nodes, O(log n) operations
; ============================================================================
; Keys are signed 64-bit. The caller owns the nodes (often inside its own
; objects); insert links the given node, remove unlinks the key's own node
; (nodes are relinked, never their contents moved), so a node always stays
; with its object. Balanced as CLRS has it (null children as black leaves).
;
;   rbtree_init(tree)
;   rbtree_insert(tree, key, value, node*)  -> 0 (a present key: its value
;                                              replaced, the node not linked)
;   rbtree_find(tree, key)                  -> value, 0 when absent
;   rbtree_remove(tree, key)                -> 0, -ENOENT, -EINVAL
;   rbtree_min(tree) / rbtree_max(tree)     -> the least / greatest key (0 empty)
;   rbtree_count(tree)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

%define RB_RED     0
%define RB_BLACK   1

struc RBNode
    .left:                    resq 1
    .right:                   resq 1
    .parent:                  resq 1
    .color:                   resq 1
    .key:                     resq 1
    .value:                   resq 1
endstruc

struc RBTree
    .root:                    resq 1
    .count:                   resq 1
endstruc

%define L   RBNode.left
%define R   RBNode.right
%define P   RBNode.parent
%define C   RBNode.color

section .text

global rbtree_init
rbtree_init:
    mov qword [rdi + RBTree.root], 0
    mov qword [rdi + RBTree.count], 0
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; rotations — rbx = tree, rdi = x (clobbers rax, rcx)
; ---------------------------------------------------------------------------
; x's right child y takes x's place, x becomes y's left child
rb_rotate_left:
    mov rax, [rdi + R]                  ; y
    mov rcx, [rax + L]
    mov [rdi + R], rcx
    test rcx, rcx
    jz .parent
    mov [rcx + P], rdi
.parent:
    mov rcx, [rdi + P]
    mov [rax + P], rcx
    test rcx, rcx
    jnz .child
    mov [rbx + RBTree.root], rax
    jmp .link
.child:
    cmp [rcx + L], rdi
    jne .right
    mov [rcx + L], rax
    jmp .link
.right:
    mov [rcx + R], rax
.link:
    mov [rax + L], rdi
    mov [rdi + P], rax
    ret

; x's left child y takes x's place, x becomes y's right child
rb_rotate_right:
    mov rax, [rdi + L]                  ; y
    mov rcx, [rax + R]
    mov [rdi + L], rcx
    test rcx, rcx
    jz .parent
    mov [rcx + P], rdi
.parent:
    mov rcx, [rdi + P]
    mov [rax + P], rcx
    test rcx, rcx
    jnz .child
    mov [rbx + RBTree.root], rax
    jmp .link
.child:
    cmp [rcx + L], rdi
    jne .right
    mov [rcx + L], rax
    jmp .link
.right:
    mov [rcx + R], rax
.link:
    mov [rax + R], rdi
    mov [rdi + P], rax
    ret

; ---------------------------------------------------------------------------
; rbtree_insert — rdi = tree, rsi = key, rdx = value, rcx = node -> rax = 0
; ---------------------------------------------------------------------------
global rbtree_insert
rbtree_insert:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    test rcx, rcx
    jz .invalid
    ; find the place (or the key)
    xor r8d, r8d                        ; parent
    mov rax, [rbx + RBTree.root]
.find:
    test rax, rax
    jz .place
    mov r8, rax
    cmp rsi, [rax + RBNode.key]
    jl .left
    jg .right
    mov [rax + RBNode.value], rdx       ; present: the value replaced
    jmp .ok
.left:
    mov rax, [rax + L]
    jmp .find
.right:
    mov rax, [rax + R]
    jmp .find
.place:
    mov qword [rcx + L], 0
    mov qword [rcx + R], 0
    mov [rcx + P], r8
    mov byte [rcx + C], RB_RED
    mov [rcx + RBNode.key], rsi
    mov [rcx + RBNode.value], rdx
    inc qword [rbx + RBTree.count]
    test r8, r8
    jnz .under
    mov [rbx + RBTree.root], rcx
    jmp .fixup
.under:
    cmp rsi, [r8 + RBNode.key]
    jl .under_left
    mov [r8 + R], rcx
    jmp .fixup
.under_left:
    mov [r8 + L], rcx
.fixup:
    mov r12, rcx                        ; z
.loop:
    mov r13, [r12 + P]                  ; p
    test r13, r13
    jz .done
    cmp byte [r13 + C], RB_RED
    jne .done
    mov r8, [r13 + P]                   ; g (p is red, so not the root)
    cmp r13, [r8 + L]
    jne .p_right
    ; p is g's left child; the uncle is g's right
    mov r9, [r8 + R]
    test r9, r9
    jz .left_rotate
    cmp byte [r9 + C], RB_RED
    jne .left_rotate
    mov byte [r13 + C], RB_BLACK
    mov byte [r9 + C], RB_BLACK
    mov byte [r8 + C], RB_RED
    mov r12, r8
    jmp .loop
.left_rotate:
    cmp r12, [r13 + R]
    jne .left_straight
    mov r12, r13                        ; z = p, rotated left
    mov rdi, r12
    call rb_rotate_left
    mov r13, [r12 + P]
.left_straight:
    mov byte [r13 + C], RB_BLACK
    mov r8, [r13 + P]
    mov byte [r8 + C], RB_RED
    mov rdi, r8
    call rb_rotate_right
    jmp .loop
.p_right:
    ; mirrored: the uncle is g's left
    mov r9, [r8 + L]
    test r9, r9
    jz .right_rotate
    cmp byte [r9 + C], RB_RED
    jne .right_rotate
    mov byte [r13 + C], RB_BLACK
    mov byte [r9 + C], RB_BLACK
    mov byte [r8 + C], RB_RED
    mov r12, r8
    jmp .loop
.right_rotate:
    cmp r12, [r13 + L]
    jne .right_straight
    mov r12, r13
    mov rdi, r12
    call rb_rotate_right
    mov r13, [r12 + P]
.right_straight:
    mov byte [r13 + C], RB_BLACK
    mov r8, [r13 + P]
    mov byte [r8 + C], RB_RED
    mov rdi, r8
    call rb_rotate_left
    jmp .loop
.done:
    mov rax, [rbx + RBTree.root]
    mov byte [rax + C], RB_BLACK
.ok:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
.invalid:
    mov rax, -(EINVAL)
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; rbtree_find — rdi = tree, rsi = key -> rax = value, 0 when absent
; ---------------------------------------------------------------------------
global rbtree_find
rbtree_find:
    mov rax, [rdi + RBTree.root]
.loop:
    test rax, rax
    jz .none
    cmp rsi, [rax + RBNode.key]
    jl .left
    jg .right
    mov rax, [rax + RBNode.value]
    ret
.left:
    mov rax, [rax + L]
    jmp .loop
.right:
    mov rax, [rax + R]
    jmp .loop
.none:
    xor eax, eax
    ret

; rbx = tree: v takes u's place under u's parent (v may be 0); clobbers rax
rb_transplant:                          ; rdi = u, rsi = v
    mov rax, [rdi + P]
    test rax, rax
    jnz .child
    mov [rbx + RBTree.root], rsi
    jmp .parent
.child:
    cmp [rax + L], rdi
    jne .right
    mov [rax + L], rsi
    jmp .parent
.right:
    mov [rax + R], rsi
.parent:
    test rsi, rsi
    jz .out
    mov [rsi + P], rax
.out:
    ret

; rcx = a node or 0 -> ZF set when it is black (0 is black)
%macro IS_BLACK 1
    test %1, %1
    jz %%black
    cmp byte [%1 + C], RB_BLACK
%%black:
%endmacro

; ---------------------------------------------------------------------------
; rbtree_remove — rdi = tree, rsi = key -> rax = 0, -ENOENT, -EINVAL
; ---------------------------------------------------------------------------
global rbtree_remove
rbtree_remove:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    test rbx, rbx
    jz .invalid
    mov r12, [rbx + RBTree.root]        ; z
.find:
    test r12, r12
    jz .not_found
    cmp rsi, [r12 + RBNode.key]
    jl .find_left
    jg .find_right
    jmp .found
.find_left:
    mov r12, [r12 + L]
    jmp .find
.find_right:
    mov r12, [r12 + R]
    jmp .find
.found:
    ; r13 = x, r14 = x's parent, r15b = the removed color
    movzx r15d, byte [r12 + C]
    cmp qword [r12 + L], 0
    jne .has_left
    mov r13, [r12 + R]
    mov r14, [r12 + P]
    mov rdi, r12
    mov rsi, r13
    call rb_transplant
    jmp .removed
.has_left:
    cmp qword [r12 + R], 0
    jne .two
    mov r13, [r12 + L]
    mov r14, [r12 + P]
    mov rdi, r12
    mov rsi, r13
    call rb_transplant
    jmp .removed
.two:
    ; y = the least node right of z takes z's place
    mov r8, [r12 + R]
.min:
    mov rax, [r8 + L]
    test rax, rax
    jz .have_min
    mov r8, rax
    jmp .min
.have_min:
    movzx r15d, byte [r8 + C]
    mov r13, [r8 + R]
    cmp [r8 + P], r12
    jne .deep
    mov r14, r8
    jmp .replace
.deep:
    mov r14, [r8 + P]
    push r8
    sub rsp, 8
    mov rdi, r8
    mov rsi, r13
    call rb_transplant
    add rsp, 8
    pop r8
    mov rax, [r12 + R]
    mov [r8 + R], rax
    mov [rax + P], r8
.replace:
    push r8
    sub rsp, 8
    mov rdi, r12
    mov rsi, r8
    call rb_transplant
    add rsp, 8
    pop r8
    mov rax, [r12 + L]
    mov [r8 + L], rax
    mov [rax + P], r8
    mov al, [r12 + C]
    mov [r8 + C], al
.removed:
    mov qword [r12 + L], 0
    mov qword [r12 + R], 0
    mov qword [r12 + P], 0
    dec qword [rbx + RBTree.count]
    cmp r15d, RB_BLACK
    jne .ok
    ; a black node gone: fix up from x (r13, maybe 0) under r14
.fix:
    cmp r13, [rbx + RBTree.root]
    je .fix_done
    IS_BLACK r13
    jne .fix_done
    cmp r13, [r14 + L]
    jne .x_right
    ; x is the left child; w its sibling
    mov rdi, [r14 + R]
    cmp byte [rdi + C], RB_RED
    jne .l_black
    mov byte [rdi + C], RB_BLACK
    mov byte [r14 + C], RB_RED
    mov rdi, r14
    call rb_rotate_left
    mov rdi, [r14 + R]
.l_black:
    mov rcx, [rdi + L]
    IS_BLACK rcx
    jne .l_near_red
    mov rcx, [rdi + R]
    IS_BLACK rcx
    jne .l_far
    mov byte [rdi + C], RB_RED
    mov r13, r14
    mov r14, [r13 + P]
    jmp .fix
.l_near_red:
    mov rcx, [rdi + R]
    IS_BLACK rcx
    jne .l_far
    mov rcx, [rdi + L]
    mov byte [rcx + C], RB_BLACK
    mov byte [rdi + C], RB_RED
    call rb_rotate_right
    mov rdi, [r14 + R]
.l_far:
    mov al, [r14 + C]
    mov [rdi + C], al
    mov byte [r14 + C], RB_BLACK
    mov rcx, [rdi + R]
    test rcx, rcx
    jz .l_rotate
    mov byte [rcx + C], RB_BLACK
.l_rotate:
    mov rdi, r14
    call rb_rotate_left
    mov r13, [rbx + RBTree.root]
    jmp .fix_done
.x_right:
    ; mirrored: x is the right child
    mov rdi, [r14 + L]
    cmp byte [rdi + C], RB_RED
    jne .r_black
    mov byte [rdi + C], RB_BLACK
    mov byte [r14 + C], RB_RED
    mov rdi, r14
    call rb_rotate_right
    mov rdi, [r14 + L]
.r_black:
    mov rcx, [rdi + R]
    IS_BLACK rcx
    jne .r_near_red
    mov rcx, [rdi + L]
    IS_BLACK rcx
    jne .r_far
    mov byte [rdi + C], RB_RED
    mov r13, r14
    mov r14, [r13 + P]
    jmp .fix
.r_near_red:
    mov rcx, [rdi + L]
    IS_BLACK rcx
    jne .r_far
    mov rcx, [rdi + R]
    mov byte [rcx + C], RB_BLACK
    mov byte [rdi + C], RB_RED
    call rb_rotate_left
    mov rdi, [r14 + L]
.r_far:
    mov al, [r14 + C]
    mov [rdi + C], al
    mov byte [r14 + C], RB_BLACK
    mov rcx, [rdi + L]
    test rcx, rcx
    jz .r_rotate
    mov byte [rcx + C], RB_BLACK
.r_rotate:
    mov rdi, r14
    call rb_rotate_right
    mov r13, [rbx + RBTree.root]
.fix_done:
    test r13, r13
    jz .ok
    mov byte [r13 + C], RB_BLACK
.ok:
    xor eax, eax
    jmp .out
.not_found:
    mov rax, -(ENOENT)
    jmp .out
.invalid:
    mov rax, -(EINVAL)
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; rbtree_min / rbtree_max — rdi = tree -> rax = the least / greatest key
; ---------------------------------------------------------------------------
global rbtree_min
rbtree_min:
    mov rax, [rdi + RBTree.root]
    test rax, rax
    jz .empty
.loop:
    mov rcx, [rax + L]
    test rcx, rcx
    jz .found
    mov rax, rcx
    jmp .loop
.found:
    mov rax, [rax + RBNode.key]
    ret
.empty:
    xor eax, eax
    ret

global rbtree_max
rbtree_max:
    mov rax, [rdi + RBTree.root]
    test rax, rax
    jz .empty
.loop:
    mov rcx, [rax + R]
    test rcx, rcx
    jz .found
    mov rax, rcx
    jmp .loop
.found:
    mov rax, [rax + RBNode.key]
    ret
.empty:
    xor eax, eax
    ret

global rbtree_count
rbtree_count:
    mov rax, [rdi + RBTree.count]
    ret

section .data
global rbtree_version
rbtree_version: dq 0x010100
