; ============================================================================
; Layout Engine — Tiling Tree Management (Binary Space Partitioning)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define LayoutEngine_size    40
%define LAYOUT_NODE_LEAF    0
%define LAYOUT_NODE_HSPLIT  1
%define LAYOUT_NODE_VSPLIT  2
%define LayoutNode_size    64

section .text

struc LayoutEngine
    .root:          resq 1
    .node_count:    resd 1
    .gap_size:      resd 1
    .master_ratio:  resq 1
    .smart_gaps:    resb 1
    .smart_borders: resb 1
endstruc


struc LayoutNode
    .type:          resd 1
    .toplevel:      resq 1
    .left:          resq 1
    .right:         resq 1
    .parent:        resq 1
    .ratio:         resq 1
    .x:             resd 1
    .y:             resd 1
    .width:         resd 1
    .height:        resd 1
    .gap:           resd 1
endstruc

; ---------------------------------------------------------------------------
; layout_engine_init
; ---------------------------------------------------------------------------
global layout_engine_init
layout_engine_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + LayoutEngine.root], 0
    mov dword [rbx + LayoutEngine.node_count], 0
    mov dword [rbx + LayoutEngine.gap_size], 4
    mov qword [rbx + LayoutEngine.master_ratio], 0
    mov byte [rbx + LayoutEngine.smart_gaps], 1
    mov byte [rbx + LayoutEngine.smart_borders], 1

    ; Default master ratio 3:5
    mov rax, 3
    shl rax, 16
    mov rdx, 5
    div rdx
    mov qword [rbx + LayoutEngine.master_ratio], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_engine_build
;   Build layout tree from window list
; ---------------------------------------------------------------------------
global layout_engine_build
layout_engine_build:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Get window list
    mov r13, rdx
    test r13, r13
    jz .empty

    ; Count windows
    mov r14, r13
    xor r14d, r14d
.count_loop:
    test r13, r13
    jz .count_done
    inc r14d
    mov r13, [r13 + Toplevel.next_ws]
    jmp .count_loop

.count_done:
    cmp r14d, 1
    jne .build

    ; Single window - full screen
    call layout_engine_create_leaf
    test rax, rax
    jz .oom
    mov [rbx + LayoutEngine.root], rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.build:
    ; Build binary tree
    call layout_tree_build_recursive
    test rax, rax
    jz .oom
    mov [rbx + LayoutEngine.root], rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.empty:
    mov qword [rbx + LayoutEngine.root], 0
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; layout_tree_build_recursive
; ---------------------------------------------------------------------------
layout_tree_build_recursive:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx

    cmp r14d, 1
    je .leaf

    ; Split
    ; For tiling: split horizontally (master on left, stack on right)
    ; For now, create a balanced binary tree
    mov r14d, r14d
    shr r14d, 1
    test r14d, r14d
    jz .leaf

    ; Allocate split node
    push rbx
    mov rdi, [rbx + LayoutEngine.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    pop rbx
    test rax, rax
    jz .oom

    mov r12, rax
    mov dword [r12 + LayoutNode.type], LAYOUT_NODE_HSPLIT
    mov qword [r12 + LayoutNode.left], 0
    mov qword [r12 + LayoutNode.right], 0
    mov qword [r12 + LayoutNode.parent], 0

    ; Build left subtree (master)
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp + 8]  ; window list
    mov rcx, r14d       ; left count
    call layout_tree_build_recursive
    test rax, rax
    jz .oom
    mov [r12 + LayoutNode.left], rax
    mov [rax + LayoutNode.parent], r12

    ; Build right subtree (stack)
    mov r14d, [rsp + 12]  ; right count
    test r14d, r14d
    jz .leaf

    push rbx
    mov rdi, [rbx + LayoutEngine.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    pop rbx
    test rax, rax
    jz .oom

    mov r13, rax
    mov dword [r13 + LayoutNode.type], LAYOUT_NODE_VSPLIT
    mov qword [r13 + LayoutNode.left], 0
    mov qword [r13 + LayoutNode.right], 0
    mov qword [r13 + LayoutNode.parent], r12
    mov [r12 + LayoutNode.right], r13

    ; Build right subtree
    ; TODO: Pass correct window list slice

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.leaf:
    call layout_engine_create_leaf
    test rax, rax
    jz .oom
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; layout_engine_create_leaf
; ---------------------------------------------------------------------------
layout_engine_create_leaf:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rdi, [rbx + LayoutEngine.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov dword [rax + LayoutNode.type], LAYOUT_NODE_LEAF
    mov qword [rax + LayoutNode.toplevel], rsi
    mov qword [rax + LayoutNode.left], 0
    mov qword [rax + LayoutNode.right], 0
    mov qword [rax + LayoutNode.parent], 0
    mov qword [rax + LayoutNode.ratio], 0
    xor eax, eax
    mov [rax + LayoutNode.x], eax
    mov [rax + LayoutNode.y], eax
    mov [rax + LayoutNode.width], eax
    mov [rax + LayoutNode.height], eax
    mov eax, [rbx + LayoutEngine.gap_size]
    mov [rax + LayoutNode.gap], eax

    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_engine_apply
;   Apply layout to windows
; ---------------------------------------------------------------------------
global layout_engine_apply
layout_engine_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + LayoutEngine.root]
    test rax, rax
    jz .done

    ; Apply recursively
    mov rdi, rax
    call layout_node_apply

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_node_apply
; ---------------------------------------------------------------------------
layout_node_apply:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + LayoutNode.type]
    cmp eax, LAYOUT_NODE_LEAF
    je .leaf

    ; Recurse on children
    mov rax, [rbx + LayoutNode.left]
    test rax, rax
    jz .check_right
    push rbx
    mov rdi, rax
    call layout_node_apply
    pop rbx

.check_right:
    mov rax, [rbx + LayoutNode.right]
    test rax, rax
    jz .done
    push rbx
    mov rdi, rax
    call layout_node_apply
    pop rbx

.done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.leaf:
    ; Apply geometry to toplevel
    mov r12, [rbx + LayoutNode.toplevel]
    test r12, r12
    jz .done

    mov r13, [r12 + Toplevel.surface]
    mov rax, [r13 + Surface.pending]

    mov eax, [rbx + LayoutNode.x]
    mov [rax + SurfaceState.buf_x], eax
    mov eax, [rbx + LayoutNode.y]
    mov [rax + SurfaceState.buf_y], eax
    mov eax, [rbx + LayoutNode.width]
    mov [rax + SurfaceState.width], eax
    mov eax, [rbx + LayoutNode.height]
    mov [rax + SurfaceState.height], eax

    mov byte [rax + SurfaceState.pending], 1

    call toplevel_schedule_configure
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; layout_engine_resize
;   Handle output resize
; ---------------------------------------------------------------------------
global layout_engine_resize
layout_engine_resize:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Rebuild layout
    call layout_engine_build

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_engine_add_window
; ---------------------------------------------------------------------------
global layout_engine_add_window
layout_engine_add_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Rebuild layout with new window
    call layout_engine_build

    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_engine_remove_window
; ---------------------------------------------------------------------------
global layout_engine_remove_window
layout_engine_remove_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Rebuild without window
    call layout_engine_build

    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global layout_engine_version
layout_engine_version: dq 0x010000
