; ============================================================================
; Tiling Policy — Binary Tree Tiling Window Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern toplevel_schedule_configure

; struct offsets (hoisted above use)
%define PolicyTiling_SIZE    56
; LayoutNode_size is supplied by struct_offsets.inc.
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

; LayoutNode struct layout (manual offsets)
; Offsets defined in inc/struct_offsets.inc

; ----------




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
    xor rdx, rdx
    mov rcx, TILING_MASTER_RATIO_DEN
    div rcx
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
    mov r13, [r12 + Output.toplevels]
mov qword [rax + LayoutNode.toplevel], r13
    mov qword [rax + LayoutNode.left], 0
    mov qword [rax + LayoutNode.right], 0
    mov qword [rax + LayoutNode.parent], 0
    mov qword [rax + LayoutNode.ratio], 0
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.build_tree:
    mov qword [rbx + PolicyTiling.layout_tree], 0
    mov r13, [r12 + Output.toplevels]
.build_loop:
    test r13, r13
    jz .build_done
    mov rdi, rbx
    mov rsi, r13
    call layout_tree_insert
    test rax, rax
    js .oom
    mov r13, [r13 + Toplevel.next_ws]
    jmp .build_loop
.build_done:
    xor rax, rax
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

    mov ecx, [rbx + PolicyTiling.gap_size]
    mov edx, [r12 + Output.x]
    add edx, ecx
    mov [rax + LayoutNode.x], edx
    mov edx, [r12 + Output.y]
    add edx, ecx
    mov [rax + LayoutNode.y], edx
    mov edx, [r12 + Output.width]
    sub edx, ecx
    sub edx, ecx
    mov [rax + LayoutNode.width], edx
    mov edx, [r12 + Output.height]
    sub edx, ecx
    sub edx, ecx
    mov [rax + LayoutNode.height], edx

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

    mov r12, [rbx + LayoutNode.left]
    mov r13, [rbx + LayoutNode.right]
    test r12, r12
    jz .check_right
    test r13, r13
    jz .check_right
    mov eax, [rbx + LayoutNode.x]
    mov [r12 + LayoutNode.x], eax
    mov [r13 + LayoutNode.x], eax
    mov eax, [rbx + LayoutNode.y]
    mov [r12 + LayoutNode.y], eax
    mov [r13 + LayoutNode.y], eax
    mov eax, [rbx + LayoutNode.width]
    mov [r12 + LayoutNode.width], eax
    mov [r13 + LayoutNode.width], eax
    mov eax, [rbx + LayoutNode.height]
    mov [r12 + LayoutNode.height], eax
    mov [r13 + LayoutNode.height], eax
    cmp dword [rbx + LayoutNode.type], NODE_TYPE_SPLIT_V
    je .vertical
    mov eax, [rbx + LayoutNode.width]
    shr eax, 1
    mov [r12 + LayoutNode.width], eax
    sub [r13 + LayoutNode.width], eax
    add [r13 + LayoutNode.x], eax
    jmp .split_done
.vertical:
    mov eax, [rbx + LayoutNode.height]
    shr eax, 1
    mov [r12 + LayoutNode.height], eax
    sub [r13 + LayoutNode.height], eax
    add [r13 + LayoutNode.y], eax
.split_done:
    ; Split node - recurse
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
    test r13, r13
    jz .done
    mov r14, [r13 + Surface.pending]
    test r14, r14
    jz .done

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

    mov r13, [r12 + Toplevel.layout_node]
    test r13, r13
    jz .done
    mov eax, [r13 + LayoutNode.width]
    mov [r12 + Toplevel.pending_width], eax
    mov eax, [r13 + LayoutNode.height]
    mov [r12 + Toplevel.pending_height], eax
    mov byte [r12 + Toplevel.pending_state], 1
    mov rdi, r12
    mov rdi, r12
    call toplevel_schedule_configure
.done:

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
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r14, rdi
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
    mov r13, [rbx + LayoutNode.toplevel]
    mov rdi, [r14 + PolicyTiling.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov dword [rax + LayoutNode.type], NODE_TYPE_LEAF
    mov [rax + LayoutNode.toplevel], r13
    mov [r13 + Toplevel.layout_node], rax
    mov qword [rax + LayoutNode.left], 0
    mov qword [rax + LayoutNode.right], 0
    mov [rax + LayoutNode.parent], rbx
    mov [rbx + LayoutNode.left], rax
    mov rdi, [r14 + PolicyTiling.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov dword [rax + LayoutNode.type], NODE_TYPE_LEAF
    mov [rax + LayoutNode.toplevel], r12
    mov [r12 + Toplevel.layout_node], rax
    mov qword [rax + LayoutNode.left], 0
    mov qword [rax + LayoutNode.right], 0
    mov [rax + LayoutNode.parent], rbx
    mov [rbx + LayoutNode.right], rax
    mov dword [rbx + LayoutNode.type], NODE_TYPE_SPLIT_H
    mov qword [rbx + LayoutNode.toplevel], 0
    mov qword [rbx + LayoutNode.ratio], 32768
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.empty:
    mov rdi, [r14 + PolicyTiling.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, LayoutNode_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov dword [rax + LayoutNode.type], NODE_TYPE_LEAF
    mov [rax + LayoutNode.toplevel], r12
    mov qword [rax + LayoutNode.left], 0
    mov qword [rax + LayoutNode.right], 0
    mov qword [rax + LayoutNode.parent], 0
    mov [r12 + Toplevel.layout_node], rax
    mov [rbx + PolicyTiling.layout_tree], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
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
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13, [r12 + Toplevel.layout_node]
    test r13, r13
    jz .done_remove
    mov rax, [r13 + LayoutNode.parent]
    test rax, rax
    jz .root_remove
    mov rcx, [rax + LayoutNode.left]
    cmp rcx, r13
    jne .use_left
    mov rcx, [rax + LayoutNode.right]
.use_left:
    mov rdx, [rax + LayoutNode.parent]
    test rdx, rdx
    jz .sibling_root
    cmp [rdx + LayoutNode.left], rax
    jne .parent_right
    mov [rdx + LayoutNode.left], rcx
    jmp .linked
.parent_right:
    mov [rdx + LayoutNode.right], rcx
.linked:
    mov [rcx + LayoutNode.parent], rdx
    jmp .clear
.sibling_root:
    mov [rbx + PolicyTiling.layout_tree], rcx
    mov qword [rcx + LayoutNode.parent], 0
    jmp .clear
.root_remove:
    mov qword [rbx + PolicyTiling.layout_tree], 0
.clear:
    mov qword [r12 + Toplevel.layout_node], 0
.done_remove:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
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

    ; Set tiled state on toplevel (r12)
    mov eax, [r12 + Toplevel.state]
    or eax, 4                  ; STATE_FLAG_TILED (1 << 2)
    mov [r12 + Toplevel.state], eax

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
