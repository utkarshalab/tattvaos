; ============================================================================
; Tiling Policy — Binary Tree Tiling Window Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define PolicyTiling_size    56
%define LayoutNode_size    64
%define NODE_TYPE_LEAF    0
%define NODE_TYPE_SPLIT_H 1
%define NODE_TYPE_SPLIT_V 2
%define TILING_MASTER_RATIO_NUM  3
%define TILING_MASTER_RATIO_DEN  5

section .text

struc PolicyTiling
    .base:              resq 1
    .server:            resq 1
    .data:              resq 1
    .layout_tree:       resq 1
    .master_ratio:      resq 1
    .gap_size:          resd 1
    .smart_gaps:        resb 1
    .smart_borders:     resb 1
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
endstruc



; ---------------------------------------------------------------------------
; policy_tiling_init
; ---------------------------------------------------------------------------
global policy_tiling_init
policy_tiling_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + PolicyTiling.base], rdi
    mov qword [rbx + PolicyTiling.server], r12
    mov qword [rbx + PolicyTiling.data], 0
    mov qword [rbx + PolicyTiling.layout_tree], 0
    mov qword [rbx + PolicyTiling.master_ratio], 0
    mov dword [rbx + PolicyTiling.gap_size], 4
    mov byte [rbx + PolicyTiling.smart_gaps], 1
    mov byte [rbx + PolicyTiling.smart_borders], 1

    ; Set function pointers
    mov qword [rdi + Policy.layout], policy_tiling_layout
    mov qword [rdi + Policy.configure], policy_tiling_configure
    mov qword [rdi + Policy.focus_change], policy_tiling_focus_change
    mov qword [rdi + Policy.new_window], policy_tiling_new_window
    mov qword [rdi + Policy.close_window], policy_tiling_close_window
    mov qword [rdi + Policy.workspace_changed], policy_tiling_workspace_changed
    mov qword [rdi + Policy.tile_window], policy_tiling_tile_window
    mov qword [rdi + Policy.window_configured], policy_tiling_window_configured

    ; Initialize layout tree
    call layout_tree_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; layout_tree_init
; ---------------------------------------------------------------------------
layout_tree_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Set default master ratio (3:5)
    mov rax, TILING_MASTER_RATIO_NUM
    shl rax, 16
    div dword TILING_MASTER_RATIO_DEN
    mov [rbx + PolicyTiling.master_ratio], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_tiling_layout
;   Layout windows using binary tree tiling
; ---------------------------------------------------------------------------
global policy_tiling_layout
policy_tiling_layout:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get output geometry
    mov r13d, [r12 + Output.width]
    mov r14d, [r12 + Output.height]
    mov r15d, [r12 + Output.x]
    mov r14, [r12 + Output.y]

    ; Apply gaps
    mov eax, [rbx + PolicyTiling.gap_size]
    sub r13d, eax
    sub r14d, eax
    sub r13d, eax
    sub r14d, eax

    ; Build/update layout tree
    call layout_tree_build

    ; Apply layout to windows
    call layout_tree_apply

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; layout_tree_build
;   Build/update binary tree from window list
; ---------------------------------------------------------------------------
layout_tree_build:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get toplevels on this output
    mov r13, [r12 + Output.toplevels]
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
    ; If only one window, make it full screen
    cmp r14d, 1
    jne .build_tree

    ; Single window - full screen
    mov rax, [rbx + PolicyTiling.layout_tree]
    test rax, rax
    jnz .reuse
    ; Allocate new root
    mov rdi, [rbx + PolicyTiling.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + PolicyTiling.layout_tree], rax

.reuse:
    mov dword [rax + LayoutNode.type], NODE_TYPE_LEAF
    mov qword [rax + LayoutNode.toplevel], [r12 + Output.toplevels]
    mov qword [rax + LayoutNode.left], 0
    mov qword [rax + LayoutNode.right], 0
    mov qword [rax + LayoutNode.parent], 0
    mov qword [rax + LayoutNode.ratio], 0
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.build_tree:
    ; Build binary tree - master on left, stack on right
    ; For simplicity, create a balanced tree
    ; TODO: Implement proper binary tree building

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.empty:
    ; No windows - clear tree
    mov qword [rbx + PolicyTiling.layout_tree], 0
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; layout_tree_apply
;   Apply layout tree to windows
; ---------------------------------------------------------------------------
layout_tree_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + PolicyTiling.layout_tree]
    test rax, rax
    jz .done

    ; Recursively apply layout
    mov rdi, rax
    call layout_node_apply

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; layout_node_apply
;   Apply layout to single node
; ---------------------------------------------------------------------------
layout_node_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + LayoutNode.type]
    cmp eax, NODE_TYPE_LEAF
    je .leaf

    ; Split node - recurse
    mov r12, [rbx + LayoutNode.left]
    test r12, r12
    jz .check_right
    push rbx
    mov rdi, r12
    call layout_node_apply
    pop rbx

.check_right:
    mov r12, [rbx + LayoutNode.right]
    test r12, r12
    jz .done
    push rbx
    mov rdi, r12
    call layout_node_apply
    pop rbx

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.leaf:
    ; Apply geometry to toplevel
    mov r12, [rbx + LayoutNode.toplevel]
    test r12, r12
    jz .done

    mov r13, [r12 + Toplevel.surface]
    mov r14, [r13 + Surface.pending]

    mov eax, [rbx + LayoutNode.x]
    mov [r14 + SurfaceState.buf_x], eax
    mov eax, [rbx + LayoutNode.y]
    mov [r14 + SurfaceState.buf_y], eax
    mov eax, [rbx + LayoutNode.width]
    mov [r14 + SurfaceState.width], eax
    mov eax, [rbx + LayoutNode.height]
    mov [r14 + SurfaceState.height], eax

    mov byte [r14 + SurfaceState.pending], 1

    call toplevel_schedule_configure
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; policy_tiling_configure
; ---------------------------------------------------------------------------
global policy_tiling_configure
policy_tiling_configure:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Tiling policy: constrain to layout
    ; TODO: Adjust configure to fit layout

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_tiling_focus_change
; ---------------------------------------------------------------------------
global policy_tiling_focus_change
policy_tiling_focus_change:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_tiling_new_window
;   Add new window to layout
; ---------------------------------------------------------------------------
global policy_tiling_new_window
policy_tiling_new_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Rebuild layout tree
    call layout_tree_build

    ; Place new window in layout
    ; By default, add as rightmost leaf
    call layout_tree_insert

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_tree_insert
; ---------------------------------------------------------------------------
layout_tree_insert:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + PolicyTiling.layout_tree]
    test rax, rax
    jz .empty

    ; Find rightmost leaf
    mov rbx, rax
.find_rightmost:
    mov rax, [rbx + LayoutNode.right]
    test rax, rax
    jz .found
    mov rbx, rax
    jmp .find_rightmost

.found:
    ; Convert leaf to split, add new leaf as right child
    ; TODO: Implement split
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.empty:
    ; First window - already handled in layout_tree_build
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_tiling_close_window
; ---------------------------------------------------------------------------
global policy_tiling_close_window
policy_tiling_close_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Remove from layout tree
    call layout_tree_remove

    ; Rebuild layout
    call layout_tree_build

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; layout_tree_remove
; ---------------------------------------------------------------------------
layout_tree_remove:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Remove node and merge split
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_tiling_workspace_changed
; ---------------------------------------------------------------------------
global policy_tiling_workspace_changed
policy_tiling_workspace_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Rebuild layout for new workspace
    call layout_tree_build

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_tiling_tile_window
;   Tile a specific window
; ---------------------------------------------------------------------------
global policy_tiling_tile_window
policy_tiling_tile_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Set tiled state
    call states_tile

    ; Rebuild layout
    call layout_tree_build

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_tiling_window_configured
; ---------------------------------------------------------------------------
global policy_tiling_window_configured
policy_tiling_window_configured:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
global policy_tiling_version
policy_tiling_version: dq 0x010000
