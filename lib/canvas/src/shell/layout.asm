; ============================================================================
; Layout Engine — Tiling Window Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; layout_engine_create
;   Create layout engine for workspace
; ============================================================================
global layout_engine_create
layout_engine_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi  ; server
    mov r13, rdx  ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + LAYOUT_SERVER], r12
    mov qword [rbx + LAYOUT_ROOT], 0
    mov dword [rbx + LAYOUT_NODE_COUNT], 0
    mov dword [rbx + LAYOUT_GAP_SIZE], 8
    mov dword [rbx + LAYOUT_MASTER_RATIO], 0x8000  ; 0.5 in 16.16
    mov byte [rbx + LAYOUT_SMART_GAPS], 1
    mov byte [rbx + LAYOUT_SMART_BORDERS], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; layout_engine_destroy
;   Destroy layout engine
; ============================================================================
global layout_engine_destroy
layout_engine_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Free all nodes
    mov rax, [rbx + LAYOUT_ROOT]
    test rax, rax
    jz .done
    call .free_node

.done:
    xor rax, rax
    leave
    ret

.free_node:
    ; Recursively free nodes
    ret

; ============================================================================
; layout_add_toplevel
;   Add toplevel to layout
; ============================================================================
global layout_add_toplevel
layout_add_toplevel:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi  ; toplevel
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create leaf node
    mov rdi, 112  ; LAYOUT_NODE_SIZE
    call arena_alloc
    test rax, rax
    jz .oom

    ; Initialize node
    mov dword [rax + LAYOUT_NODE_TYPE], NODE_TYPE_LEAF
    mov qword [rax + LAYOUT_NODE_LEFT], 0
    mov qword [rax + LAYOUT_NODE_RIGHT], 0
    mov qword [rax + LAYOUT_NODE_PARENT], 0
    mov qword [rax + LAYOUT_NODE_CLIENT], r12
    mov dword [rax + LAYOUT_NODE_RATIO], 0x8000  ; 0.5

    ; Link into tree
    call .link_node

    inc dword [rbx + LAYOUT_NODE_COUNT]

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -ENOMEM
    leave
    ret

.link_node:
    ; Link node into tree (simplified: append to root)
    ret

; ============================================================================
; layout_remove_toplevel
;   Remove toplevel from layout
; ============================================================================
global layout_remove_toplevel
layout_remove_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find node for this toplevel
    call .find_node
    test rax, rax
    jz .not_found

    ; Remove from tree
    call .unlink_node

    ; Free node
    ; Arena handles it

    dec dword [rbx + LAYOUT_NODE_COUNT]

    xor rax, rax
    leave
    ret

.not_found:
    xor rax, rax
    leave
    ret

; ============================================================================
; .find_node - Find layout node for a toplevel
; ============================================================================
.find_node:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi  ; layout engine
    mov r12, rsi  ; toplevel
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + LAYOUT_ROOT]
    test rax, rax
    jz .find_not_found

    ; Search tree recursively (simplified: linear search for now)
    mov r13, [rbx + LAYOUT_ROOT]
.find_loop:
    test r13, r13
    jz .find_not_found

    cmp qword [r13 + LAYOUT_NODE_CLIENT], r12
    je .find_found

    mov r13, [r13 + LAYOUT_NODE_LEFT]
    test r13, r13
    jnz .find_loop

    mov r13, [r13 + LAYOUT_NODE_RIGHT]
    test r13, r13
    jnz .find_loop

.find_not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.find_found:
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; .unlink_node - Remove node from tree
; ============================================================================
.unlink_node:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi  ; node to remove
    ASSERT_PTR rbx

    ; Get parent
    mov r12, [rbx + LAYOUT_NODE_PARENT]
    test r12, r12
    jz .unlink_root

    ; Check if node is left or right child
    cmp qword [r12 + LAYOUT_NODE_LEFT], rbx
    je .unlink_left

    ; Right child
    mov rax, [rbx + LAYOUT_NODE_RIGHT]
    mov [r12 + LAYOUT_NODE_RIGHT], rax
    jmp .unlink_done

.unlink_left:
    mov rax, [rbx + LAYOUT_NODE_RIGHT]
    mov [r12 + LAYOUT_NODE_LEFT], rax
    jmp .unlink_done

.unlink_root:
    ; Removing root - promote left child or right child
    mov rax, [rbx + LAYOUT_NODE_LEFT]
    test rax, rax
    jz .promote_right
    mov [rbx + LAYOUT_ROOT], rax
    jmp .unlink_done

.promote_right:
    mov rax, [rbx + LAYOUT_NODE_RIGHT]
    mov [rbx + LAYOUT_ROOT], rax

.unlink_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; layout_apply
;   Apply layout to toplevels
; ============================================================================
global layout_apply
layout_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; output rect
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get workspace rect
    mov r12d, [rsi + Rect_x]
    mov r13d, [rsi + Rect_y]
    mov r14d, [rsi + Rect_width]
    mov r15d, [rsi + Rect_height]

    ; Apply layout from root
    mov rax, [rbx + LAYOUT_ROOT]
    test rax, rax
    jz .done

    call .apply_node

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.apply_node:
    ; Recursively apply layout to nodes
    ret

; ============================================================================
; layout_resize
;   Handle output resize
; ============================================================================
global layout_resize
layout_resize:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Re-apply layout
    mov rdi, rbx
    mov rsi, rsp  ; use stack for rect
    ; Build rect from output
    call layout_apply

    xor rax, rax
    leave
    ret

; ============================================================================
; layout_set_master_ratio
;   Set master area ratio
; ============================================================================
global layout_set_master_ratio
layout_set_master_ratio:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Ratio in 16.16 fixed point
    mov dword [rbx + LAYOUT_MASTER_RATIO], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; layout_set_gap
;   Set gap size
; ============================================================================
global layout_set_gap
layout_set_gap:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + LAYOUT_GAP_SIZE], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; layout_toggle_smart_gaps
;   Toggle smart gaps
; ============================================================================
global layout_toggle_smart_gaps
layout_toggle_smart_gaps:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov al, [rbx + LAYOUT_SMART_GAPS]
    xor al, 1
    mov [rbx + LAYOUT_SMART_GAPS], al
    xor rax, rax
    leave
    ret

; ============================================================================
; layout_toggle_smart_borders
;   Toggle smart borders
; ============================================================================
global layout_toggle_smart_borders
layout_toggle_smart_borders:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov al, [rbx + LAYOUT_SMART_BORDERS]
    xor al, 1
    mov [rbx + LAYOUT_SMART_BORDERS], al
    xor rax, rax
    leave
    ret

section .data
global layout_version
layout_version: dq 0x010000