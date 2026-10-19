; ============================================================================
; Z-Order — Surface Stacking Order (RBTree)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

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

    mov rdi, r12
    mov rsi, 16
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Server.z_order_tree], rax
    mov rdi, rax
    mov rsi, r12
    call rbtree_init
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
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
    mov rcx, rax
    mov rax, r13
    shl rax, 32
    mov edx, [r12 + Surface.id]
    or rax, rdx
    mov rsi, rax
    mov rdx, r12
    mov rdi, [rbx + Server.z_order_tree]
    call rbtree_insert
    test rax, rax
    js .insert_out
    mov [r12 + Surface.z_order], r13
.insert_out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

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

    mov rax, [r12 + Surface.z_order]
    shl rax, 32
    mov edx, [r12 + Surface.id]
    or rax, rdx
    mov rdi, [rbx + Server.z_order_tree]
    mov rsi, rax
    call rbtree_remove
    EPILOGUE_RESTORE rbx, r12
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
    mov rdi, rbx
    mov rsi, r12
    call zorder_remove
    test rax, rax
    js .move_out
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call zorder_insert
.move_out:
    EPILOGUE_RESTORE rbx, r12, r13
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
    EPILOGUE_RESTORE rbx, r12, r13
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
    EPILOGUE_RESTORE rbx, r12, r13
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
    mov rdi, [rbx + Server.z_order_tree]
    call rbtree_max
    test rax, rax
    jz .empty

    add rax, 1
    mov rdx, rax
    call zorder_move
    EPILOGUE_RESTORE rbx, r12
    ret

.empty:
    mov rdx, 1
    call zorder_move
    EPILOGUE_RESTORE rbx, r12
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
    mov rdi, [rbx + Server.z_order_tree]
    call rbtree_min
    test rax, rax
    jz .empty

    sub rax, 1
    mov rdx, rax
    call zorder_move
    EPILOGUE_RESTORE rbx, r12
    ret

.empty:
    mov rdx, 1
    call zorder_move
    EPILOGUE_RESTORE rbx, r12
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
    sub rsp, 512
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r14, [rbx + Server.z_order_tree]
    test r14, r14
    jz .done
    mov r14, [r14]
    xor ecx, ecx
.walk:
    test r14, r14
    jz .pop
    cmp ecx, 64
    jae .overflow
    mov [rsp + rcx * 8], r14
    inc ecx
    mov r14, [r14]
    jmp .walk
.pop:
    test ecx, ecx
    jz .done
    dec ecx
    mov r14, [rsp + rcx * 8]
    mov [rsp + 504], rcx
    mov rdi, [r14 + 40]
    mov rsi, r13
    call r12
    test rax, rax
    js .out
    mov rcx, [rsp + 504]
    mov r14, [r14 + 8]
    jmp .walk
.done:
    xor rax, rax
    jmp .out
.overflow:
    mov rax, -(EOVERFLOW)
.out:
    add rsp, 512
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global zorder_version
zorder_version: dq 0x010000
