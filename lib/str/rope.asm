; =============================================================================
; str/rope.asm
; Balanced Rope data structure for efficient large-string editing.
; Implements AVL-balancing on branches to prevent tree degradation.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_arena_alloc
extern str_copy_bytes

ROPE_LEAF       equ 0
ROPE_BRANCH     equ 1
ROPE_LEAF_MAX   equ 512

struc RopeNode
    .tag       resb 1
    .height    resb 1       ; height of the node for AVL
    .pad       resb 6
    .weight    resq 1       ; leaf: chunk len; branch: left subtree total
    .total_len resq 1       ; total bytes in this subtree
    .data      resq 1       ; leaf: byte ptr | branch: left child ptr
    .right     resq 1       ; branch: right child ptr
endstruc

ROPE_NODE_SIZE  equ 40

section .text

; -----------------------------------------------------------------------------
; str_rope_height
;
; Returns height of a RopeNode. Helper.
; -----------------------------------------------------------------------------
_rope_node_height:
    test    rdi, rdi
    jz      .h_zero
    movzx   eax, byte [rdi + RopeNode.height]
    ret
.h_zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; _rope_update_node
;
; Recalculates height, weight, and total_len of a branch node.
; -----------------------------------------------------------------------------
_rope_update_node:
    test    rdi, rdi
    jz      .done

    movzx   eax, byte [rdi + RopeNode.tag]
    cmp     al, ROPE_LEAF
    je      .done

    push_regs rbx, r12, r13
    mov     rbx, rdi
    mov     r12, [rbx + RopeNode.data]      ; left
    mov     r13, [rbx + RopeNode.right]     ; right

    ; weight = left.total_len
    xor     ecx, ecx
    test    r12, r12
    jz      .set_weight
    mov     rcx, [r12 + RopeNode.total_len]
.set_weight:
    mov     [rbx + RopeNode.weight], rcx

    ; total_len = left.total_len + right.total_len
    xor     rdx, rdx
    test    r13, r13
    jz      .set_total
    mov     rdx, [r13 + RopeNode.total_len]
.set_total:
    add     rcx, rdx
    mov     [rbx + RopeNode.total_len], rcx

    ; height = 1 + max(left.height, right.height)
    mov     rdi, r12
    call    _rope_node_height
    mov     r12, rax            ; left height

    mov     rdi, r13
    call    _rope_node_height
    mov     r13, rax            ; right height

    cmp     r12, r13
    cmovb   r12, r13            ; r12 = max
    inc     r12
    mov     [rbx + RopeNode.height], r12b

    pop_regs r13, r12, rbx
.done:
    ret

; -----------------------------------------------------------------------------
; _rope_rotate_right
;
; Perform right rotation on branch. Returns new root.
; -----------------------------------------------------------------------------
_rope_rotate_right:
    test    rdi, rdi
    jz      .done

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, [rbx + RopeNode.data]      ; L = node.left

    ; node.left = L.right
    mov     rcx, [r12 + RopeNode.right]
    mov     [rbx + RopeNode.data], rcx

    ; L.right = node
    mov     [r12 + RopeNode.right], rbx

    ; update node first, then L
    mov     rdi, rbx
    call    _rope_update_node
    mov     rdi, r12
    call    _rope_update_node

    mov     rax, r12
    pop_regs r12, rbx
    ret
.done:
    mov     rax, rdi
    ret

; -----------------------------------------------------------------------------
; _rope_rotate_left
;
; Perform left rotation on branch. Returns new root.
; -----------------------------------------------------------------------------
_rope_rotate_left:
    test    rdi, rdi
    jz      .done

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, [rbx + RopeNode.right]     ; R = node.right

    ; node.right = R.left
    mov     rcx, [r12 + RopeNode.data]
    mov     [rbx + RopeNode.right], rcx

    ; R.left = node
    mov     [r12 + RopeNode.data], rbx

    ; update node first, then R
    mov     rdi, rbx
    call    _rope_update_node
    mov     rdi, r12
    call    _rope_update_node

    mov     rax, r12
    pop_regs r12, rbx
    ret
.done:
    mov     rax, rdi
    ret

; -----------------------------------------------------------------------------
; _rope_balance
;
; Rebalances an AVL branch node if out of balance.
; -----------------------------------------------------------------------------
_rope_balance:
    test    rdi, rdi
    jz      .done

    push_regs rbx, r12, r13
    mov     rbx, rdi

    ; update height & total sizes first
    mov     rdi, rbx
    call    _rope_update_node

    ; get balance factor = height(left) - height(right)
    mov     rdi, [rbx + RopeNode.data]
    call    _rope_node_height
    mov     r12, rax

    mov     rdi, [rbx + RopeNode.right]
    call    _rope_node_height
    mov     r13, rax

    sub     r12, r13            ; balance factor

    cmp     r12, 1
    jg      .left_heavy
    cmp     r12, -1
    jl      .right_heavy

.no_rotate:
    mov     rax, rbx
    pop_regs r13, r12, rbx
    ret

.left_heavy:
    ; check if left.left height >= left.right height
    mov     rcx, [rbx + RopeNode.data]      ; left child
    mov     rdi, [rcx + RopeNode.data]
    call    _rope_node_height
    mov     r12, rax

    mov     rdi, [rcx + RopeNode.right]
    call    _rope_node_height
    mov     r13, rax

    cmp     r12, r13
    jge     .left_left

    ; left-right case
    mov     rdi, [rbx + RopeNode.data]
    call    _rope_rotate_left
    mov     [rbx + RopeNode.data], rax

.left_left:
    mov     rdi, rbx
    call    _rope_rotate_right
    pop_regs r13, r12, rbx
    ret

.right_heavy:
    ; check if right.right height >= right.left height
    mov     rcx, [rbx + RopeNode.right]     ; right child
    mov     rdi, [rcx + RopeNode.right]
    call    _rope_node_height
    mov     r12, rax

    mov     rdi, [rcx + RopeNode.data]
    call    _rope_node_height
    mov     r13, rax

    cmp     r12, r13
    jge     .right_right

    ; right-left case
    mov     rdi, [rbx + RopeNode.right]
    call    _rope_rotate_right
    mov     [rbx + RopeNode.right], rax

.right_right:
    mov     rdi, rbx
    call    _rope_rotate_left
    pop_regs r13, r12, rbx
    ret

.done:
    mov     rax, rdi
    ret

; -----------------------------------------------------------------------------
; str_rope_leaf
;
; Create a rope leaf node from a StrSlice (copies data into arena).
;
; Signature:
;   RopeNode *str_rope_leaf(const StrSlice *chunk, StrArena *arena)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_leaf
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13
    mov     rbx, rdi            ; chunk
    mov     r12, rsi            ; arena

    ; allocate node
    mov     rdi, r12
    mov     rsi, ROPE_NODE_SIZE
    mov     rdx, 8
    call    str_arena_alloc
    test    rax, rax
    jz      .rl_null
    mov     r13, rax            ; node ptr

    ; allocate chunk data
    mov     rcx, [rbx + StrSlice.len]
    mov     rdi, r12
    mov     rsi, rcx
    mov     rdx, 1
    push    rcx
    call    str_arena_alloc
    pop     rcx
    test    rax, rax
    jz      .rl_null

    ; copy chunk bytes
    mov     rdi, rax
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, rcx
    push    rax
    push    rcx
    call    str_copy_bytes
    pop     rcx
    pop     rax

    ; fill node
    mov     byte [r13 + RopeNode.tag], ROPE_LEAF
    mov     byte [r13 + RopeNode.height], 1
    mov     [r13 + RopeNode.weight], rcx
    mov     [r13 + RopeNode.total_len], rcx
    mov     [r13 + RopeNode.data], rax

    mov     rax, r13
    pop_regs r13, r12, rbx
    pop     rbp
    ret

.rl_null:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_rope_leaf

; -----------------------------------------------------------------------------
; str_rope_concat
;
; Concatenate two ropes by creating a new branch node.
;
; Signature:
;   RopeNode *str_rope_concat(RopeNode *left, RopeNode *right, StrArena *arena)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_concat
    test    rdi, rdi
    jz      .rc_right_only
    test    rsi, rsi
    jz      .rc_left_only
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    mov     rbx, rdi            ; left
    mov     r12, rsi            ; right
    mov     r13, rdx            ; arena

    ; allocate branch node
    mov     rdi, r13
    mov     rsi, ROPE_NODE_SIZE
    mov     rdx, 8
    call    str_arena_alloc
    test    rax, rax
    jz      .rc_null
    mov     r14, rax

    mov     byte [r14 + RopeNode.tag], ROPE_BRANCH
    mov     [r14 + RopeNode.data], rbx      ; left
    mov     [r14 + RopeNode.right], r12     ; right

    ; balance and calculate sizes
    mov     rdi, r14
    call    _rope_balance

    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.rc_null:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rc_left_only:
    mov     rax, rdi
    pop     rbp
    ret

.rc_right_only:
    mov     rax, rsi
    pop     rbp
    ret
STR_ENDFUNC str_rope_concat

; -----------------------------------------------------------------------------
; str_rope_len
;
; Total length of a rope in bytes.
;
; Signature:
;   uint64_t str_rope_len(const RopeNode *rope)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_len
    test    rdi, rdi
    jz      .rlen_zero
    mov     rax, [rdi + RopeNode.total_len]
    pop     rbp
    ret
.rlen_zero:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_rope_len

; -----------------------------------------------------------------------------
; str_rope_index
;
; Get the byte at a given index.
;
; Signature:
;   int64_t str_rope_index(const RopeNode *rope, uint64_t idx, uint8_t *out)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_index
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    cmp     rsi, [rdi + RopeNode.total_len]
    jae     .ri_oob

.ri_walk:
    movzx   eax, byte [rdi + RopeNode.tag]
    cmp     al, ROPE_LEAF
    je      .ri_leaf

    mov     rcx, [rdi + RopeNode.weight]
    cmp     rsi, rcx
    jb      .ri_go_left

    sub     rsi, rcx
    mov     rdi, [rdi + RopeNode.right]
    jmp     .ri_walk

.ri_go_left:
    mov     rdi, [rdi + RopeNode.data]
    jmp     .ri_walk

.ri_leaf:
    mov     rax, [rdi + RopeNode.data]
    movzx   eax, byte [rax + rsi]
    mov     [rdx], al

    xor     eax, eax
    pop     rbp
    ret

.ri_oob:
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret
STR_ENDFUNC str_rope_index

; -----------------------------------------------------------------------------
; str_rope_to_slice
;
; Flatten a rope into a contiguous buffer.
;
; Signature:
;   int64_t str_rope_to_slice(const RopeNode *rope, uint8_t *dst,
;                              uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_to_slice
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    mov     rbx, rdi            ; rope
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    mov     rax, [rbx + RopeNode.total_len]
    cmp     rax, r13
    ja      .rts_overflow

    xor     r9, r9              ; offset

    mov     rdi, rbx
    call    .flatten
    test    rax, rax
    jnz     .rts_err

    test    r14, r14
    jz      .rts_ok
    mov     [r14], r9

.rts_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rts_overflow:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.rts_err:
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.flatten:
    push    rbp
    mov     rbp, rsp

    test    rdi, rdi
    jz      .flat_ok

    movzx   eax, byte [rdi + RopeNode.tag]
    cmp     al, ROPE_LEAF
    je      .flat_leaf

    push    rdi
    mov     rdi, [rdi + RopeNode.data]      ; left
    call    .flatten
    pop     rdi
    test    rax, rax
    jnz     .flat_ret

    mov     rdi, [rdi + RopeNode.right]     ; right
    call    .flatten
    jmp     .flat_ret

.flat_leaf:
    mov     rsi, [rdi + RopeNode.data]
    mov     rcx, [rdi + RopeNode.weight]

.flat_copy:
    test    rcx, rcx
    jz      .flat_ok

    movzx   eax, byte [rsi]
    mov     [r12 + r9], al
    inc     rsi
    inc     r9
    dec     rcx
    jmp     .flat_copy

.flat_ok:
    xor     eax, eax
.flat_ret:
    pop     rbp
    ret
STR_ENDFUNC str_rope_to_slice

; -----------------------------------------------------------------------------
; str_rope_split
;
; Split a rope at a given byte index. Returns left/right pointers.
;
; Signature:
;   int64_t str_rope_split(RopeNode *rope, uint64_t idx, StrArena *arena,
;                           RopeNode **out_left, RopeNode **out_right)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_split
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    mov     rbx, rdi            ; rope
    mov     r12, rsi            ; idx
    mov     r13, rdx            ; arena
    mov     r14, rcx            ; out_left
    mov     r15, r8             ; out_right

    ; check bounds
    mov     rax, [rbx + RopeNode.total_len]
    cmp     r12, rax
    jbe     .split_in_bounds

    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret

.split_in_bounds:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    mov     r8, r15
    call    .split_rec

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

; Recursive split: RDI = node, RSI = idx, RDX = arena, RCX = out_left, R8 = out_right
.split_rec:
    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 16             ; local space for recursive returns
    mov     rbx, rdi            ; node
    mov     r12, rsi            ; idx
    mov     r13, rdx            ; arena
    mov     r14, rcx            ; out_left
    mov     r15, r8             ; out_right

    test    rbx, rbx
    jz      .rec_null

    movzx   eax, byte [rbx + RopeNode.tag]
    cmp     al, ROPE_LEAF
    je      .rec_leaf

    ; branch split
    mov     r9, [rbx + RopeNode.weight]     ; left len
    cmp     r12, r9
    jb      .rec_go_left

    ; split right child: idx >= left_len
    sub     r12, r9             ; right_idx = idx - left_len
    mov     rdi, [rbx + RopeNode.right]
    mov     rsi, r12
    mov     rdx, r13
    lea     rcx, [rsp]          ; right_split_left is at [rsp]
    lea     r8, [rsp + 8]       ; right_split_right is at [rsp + 8]
    call    .split_rec

    ; left_out = concat(node.left, right_split_left)
    mov     rdi, [rbx + RopeNode.data]
    mov     rsi, [rsp]
    mov     rdx, r13
    call    str_rope_concat
    mov     [r14], rax          ; save left

    ; right_out = right_split_right
    mov     rax, [rsp + 8]
    mov     [r15], rax          ; save right
    jmp     .rec_done

.rec_go_left:
    ; split left child: idx < left_len
    mov     rdi, [rbx + RopeNode.data]
    mov     rsi, r12
    mov     rdx, r13
    lea     rcx, [rsp]          ; left_split_left is at [rsp]
    lea     r8, [rsp + 8]       ; left_split_right is at [rsp + 8]
    call    .split_rec

    ; left_out = left_split_left
    mov     rax, [rsp]
    mov     [r14], rax

    ; right_out = concat(left_split_right, node.right)
    mov     rdi, [rsp + 8]
    mov     rsi, [rbx + RopeNode.right]
    mov     rdx, r13
    call    str_rope_concat
    mov     [r15], rax
    jmp     .rec_done

.rec_leaf:
    ; leaf node split
    test    r12, r12
    jz      .leaf_all_right
    cmp     r12, [rbx + RopeNode.total_len]
    je      .leaf_all_left

    ; split in middle: allocate two new leaves
    sub     rsp, 32             ; StrSlice structs (2x16 bytes)
    
    ; left slice
    mov     rax, [rbx + RopeNode.data]
    mov     [rsp + StrSlice.ptr], rax
    mov     [rsp + StrSlice.len], r12
    lea     rdi, [rsp]
    mov     rsi, r13
    call    str_rope_leaf
    mov     [r14], rax

    ; right slice
    mov     rax, [rbx + RopeNode.data]
    add     rax, r12
    mov     [rsp + 16 + StrSlice.ptr], rax
    mov     rcx, [rbx + RopeNode.total_len]
    sub     rcx, r12
    mov     [rsp + 16 + StrSlice.len], rcx
    lea     rdi, [rsp + 16]
    mov     rsi, r13
    call    str_rope_leaf
    mov     [r15], rax

    add     rsp, 32
    jmp     .rec_done

.leaf_all_left:
    mov     [r14], rbx
    mov     qword [r15], 0
    jmp     .rec_done

.leaf_all_right:
    mov     qword [r14], 0
    mov     [r15], rbx
    jmp     .rec_done

.rec_null:
    mov     qword [r14], 0
    mov     qword [r15], 0

.rec_done:
    add     rsp, 16
    pop_regs r15, r14, r13, r12, rbx
    ret
STR_ENDFUNC str_rope_split

; -----------------------------------------------------------------------------
; str_rope_insert
;
; Insert a string slice at a given index.
;
; Signature:
;   RopeNode *str_rope_insert(RopeNode *rope, uint64_t idx,
;                              const StrSlice *slice, StrArena *arena)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_insert
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 32             ; allocate space for left/right nodes pointers

    mov     rbx, rdi            ; rope
    mov     r12, rsi            ; idx
    mov     r13, rdx            ; slice
    mov     r14, rcx            ; arena

    ; if empty slice, return as-is
    mov     rax, [r13 + StrSlice.len]
    test    rax, rax
    jz      .ins_as_is

    ; if rope is null, create leaf directly
    test    rbx, rbx
    jz      .ins_create_leaf

    ; split at index
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r14
    lea     rcx, [rsp]          ; left is at [rsp]
    lea     r8, [rsp + 8]       ; right is at [rsp + 8]
    call    str_rope_split

    ; create leaf for slice
    mov     rdi, r13
    mov     rsi, r14
    call    str_rope_leaf
    mov     [rsp + 16], rax     ; leaf node

    ; concat left + leaf
    mov     rdi, [rsp]
    mov     rsi, [rsp + 16]
    mov     rdx, r14
    call    str_rope_concat
    mov     [rsp], rax          ; temp node

    ; concat temp + right
    mov     rdi, [rsp]
    mov     rsi, [rsp + 8]
    mov     rdx, r14
    call    str_rope_concat

    add     rsp, 32
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.ins_create_leaf:
    mov     rdi, r13
    mov     rsi, r14
    call    str_rope_leaf
    add     rsp, 32
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.ins_as_is:
    mov     rax, rbx
    add     rsp, 32
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_rope_insert

; -----------------------------------------------------------------------------
; str_rope_delete
;
; Delete a range of bytes from the rope.
;
; Signature:
;   RopeNode *str_rope_delete(RopeNode *rope, uint64_t idx, uint64_t len,
;                              StrArena *arena)
; -----------------------------------------------------------------------------
STR_FUNC str_rope_delete
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 48             ; space for node pointers

    mov     rbx, rdi            ; rope
    mov     r12, rsi            ; idx
    mov     r13, rdx            ; len
    mov     r14, rcx            ; arena

    test    r13, r13
    jz      .del_as_is
    test    rbx, rbx
    jz      .del_as_is

    ; split at index: split(rope, idx) -> (left, temp)
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r14
    lea     rcx, [rsp]          ; left is at [rsp]
    lea     r8, [rsp + 8]       ; temp is at [rsp + 8]
    call    str_rope_split

    ; split temp at len: split(temp, len) -> (mid, right)
    mov     rdi, [rsp + 8]
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rsp + 16]     ; mid is at [rsp + 16]
    lea     r8, [rsp + 24]      ; right is at [rsp + 24]
    call    str_rope_split

    ; concat left + right
    mov     rdi, [rsp]
    mov     rsi, [rsp + 24]
    mov     rdx, r14
    call    str_rope_concat

    add     rsp, 48
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.del_as_is:
    mov     rax, rbx
    add     rsp, 48
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_rope_delete