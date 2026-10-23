; ============================================================================
; A11y Tree — Accessibility Tree Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/server_offsets.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define A11Y_ROLE_WINDOW          1
%define A11Y_ROLE_BUTTON          2
%define A11Y_ROLE_LINK            3
%define A11Y_ROLE_TEXT            3
%define A11Y_ROLE_LIST            4
%define A11Y_ROLE_LIST_ITEM       5
%define A11Y_ROLE_TABLE           6
%define A11Y_ROLE_TABLE_CELL      7
%define A11Y_ROLE_TREE            8
%define A11Y_ROLE_TREE_ITEM       9
%define A11Y_ROLE_MENU            10
%define A11Y_ROLE_MENU_ITEM       11
%define A11Y_ROLE_SLIDER          12
%define A11Y_ROLE_SCROLLBAR       13
%define A11Y_ROLE_PROGRESSBAR     14
%define A11Y_ROLE_TAB             15
%define A11Y_ROLE_TAB_PANEL       16
%define A11Y_ROLE_DIALOG          17
%define A11Y_ROLE_ALERT           18
%define A11Y_ROLE_TOOLTIP         19
%define A11Y_ROLE_NOTIFICATION    20
%define A11Y_ROLE_STATUSBAR       21
%define A11Y_ROLE_SCROLLVIEW      22
%define A11Y_STATE_FOCUSABLE      (1 << 0)
%define A11Y_STATE_FOCUSED        (1 << 1)
%define A11Y_STATE_SELECTABLE     (1 << 2)
%define A11Y_STATE_SELECTED       (1 << 2)
%define A11Y_STATE_EXPANDED       (1 << 3)
%define A11Y_STATE_COLLAPSED      (1 << 4)
%define A11Y_STATE_CHECKED        (1 << 5)
%define A11Y_STATE_DISABLED       (1 << 6)
%define A11Y_STATE_VISIBLE        (1 << 7)
%define A11Y_STATE_OFFSCREEN      (1 << 8)
%define A11Y_STATE_REQUIRED       (1 << 9)
%define A11Y_STATE_READONLY       (1 << 10)
%define A11Y_STATE_MULTILINE      (1 << 11)
%define A11Y_STATE_HAS_POPUP      (1 << 12)
%define A11Y_STATE_MODAL          (1 << 13)

section .text

struc A11yTree
    .root:          resq 1
    .nodes:         resq 1
    .node_count:    resd 1
    .focused_node:  resq 1
    .seat:          resq 1
endstruc

struc A11yNode
    .surface:           resq 1
    .role:              resd 1
    .name:              resq 1
    .description:       resq 1
    .states:            resq 1
    .attributes:        resq 1
    .parent:            resq 1
    .first_child:       resq 1
    .last_child:        resq 1
    .next_sibling:      resq 1
    .prev_sibling:      resq 1
    .x:                 resd 1
    .y:                 resd 1
    .width:             resd 1
    .height:            resd 1
    .transform:         resq 1
endstruc



global a11y_tree_init
a11y_tree_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.a11y_tree], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

global a11y_node_create
a11y_node_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, A11yNode_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + A11yNode.surface], r12
    mov dword [rbx + A11yNode.role], r13d
    mov qword [rbx + A11yNode.name], 0
    mov qword [rbx + A11yNode.description], 0
    mov qword [rbx + A11yNode.states], 0
    mov qword [rbx + A11yNode.attributes], 0
    mov qword [rbx + A11yNode.parent], 0
    mov qword [rbx + A11yNode.first_child], 0
    mov qword [rbx + A11yNode.last_child], 0
    mov qword [rbx + A11yNode.next_sibling], 0
    mov qword [rbx + A11yNode.prev_sibling], 0
    mov dword [rbx + A11yNode.x], 0
    mov dword [rbx + A11yNode.y], 0
    mov dword [rbx + A11yNode.width], 0
    mov dword [rbx + A11yNode.height], 0
    mov qword [rbx + A11yNode.transform], 0

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global a11y_node_destroy
a11y_node_destroy:
    PROLOGUE
    xor rax, rax
    leave
    ret

global a11y_node_set_role
a11y_node_set_role:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + A11yNode.role], esi
    xor rax, rax
    leave
    ret

global a11y_node_set_name
a11y_node_set_name:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + A11yNode.name]
    test rax, rax
    jz .set_new

.set_new:
    call str_dup_arena
    test rax, rax
    jz .oom
    mov [rbx + A11yNode.name], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

global a11y_node_set_geometry
a11y_node_set_geometry:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + A11yNode.x], esi
    mov dword [rbx + A11yNode.y], edx
    mov dword [rbx + A11yNode.width], ecx
    mov dword [rbx + A11yNode.height], r8d
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

global a11y_node_add_child
a11y_node_add_child:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + A11yNode.last_child]
    test rax, rax
    jz .first_child

    mov [rax + A11yNode.next_sibling], r12
    mov [r12 + A11yNode.prev_sibling], rax
    mov [rbx + A11yNode.last_child], r12
    mov [r12 + A11yNode.parent], rbx
    EPILOGUE_RESTORE rbx, r12
    ret

.first_child:
    mov [rbx + A11yNode.first_child], r12
    mov [rbx + A11yNode.last_child], r12
    mov [r12 + A11yNode.parent], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

global a11y_tree_get_focused
a11y_tree_get_focused:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + A11yTree.focused_node]
    leave
    ret

global a11y_tree_set_focused
a11y_tree_set_focused:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov qword [rbx + A11yTree.focused_node], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global a11y_tree_version
a11y_tree_version: dq 0x010000
