; =============================================================================
; str/rope.asm
; Rope data structure — balanced binary tree of string chunks for efficient
; large-string editing (insert, delete, concat in O(log n)).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   mem/arena.asm   (str_arena_alloc)
;   core/copy.asm   (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; A rope is a binary tree where:
;   - Leaves hold short string chunks (up to ROPE_LEAF_MAX bytes)
;   - Internal nodes hold left + right children and cached total weight
;   - Concat = create a new internal node (O(1) amortized)
;   - Split = walk tree to cut point (O(log n))
;   - Insert = split + concat + concat (O(log n))
;   - Index = walk tree using weights (O(log n))
;
; This is crucial for uide: text editors need O(log n) insert/delete on
; large files. A flat buffer gives O(n) for every edit.
;
; RopeNode layout (48 bytes):
;   .tag       db   — ROPE_LEAF (0) or ROPE_BRANCH (1)
;   .pad       db 7
;   .weight    dq   — for leaf: chunk length; for branch: left subtree size
;   .total_len dq   — total bytes in this subtree
;   ; leaf fields:
;   .data      dq   — pointer to chunk bytes
;   ; branch fields (union with data):
;   .left      dq   — left child node pointer
;   .right     dq   — right child node pointer
;
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_arena_alloc
extern str_copy_bytes

ROPE_LEAF       equ 0
ROPE_BRANCH     equ 1
ROPE_LEAF_MAX   equ 512     ; max bytes in a leaf chunk

struc RopeNode
    .tag       resb 1
    .pad       resb 7
    .weight    resq 1       ; leaf: chunk len; branch: left subtree total
    .total_len resq 1       ; total bytes in this subtree
    .data      resq 1       ; leaf: byte ptr | branch: left child ptr
    .right     resq 1       ; branch: right child ptr (leaf: unused)
endstruc

ROPE_NODE_SIZE  equ 40

section .text

; -----------------------------------------------------------------------------
; str_rope_leaf
;
; Create a rope leaf node from a StrSlice (copies data into arena).
;
; Signature:
;   RopeNode *str_rope_leaf(const StrSlice *chunk, StrArena *arena)
;
; Returns: pointer to new RopeNode, or null on failure.
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
;   RopeNode *str_rope_concat(RopeNode *left, RopeNode *right,
;                              StrArena *arena)
;
; Returns: pointer to new branch node, or null on failure.
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

    ; weight = left.total_len
    mov     rcx, [rbx + RopeNode.total_len]
    mov     [r14 + RopeNode.weight], rcx

    ; total_len = left.total_len + right.total_len
    mov     rdx, [r12 + RopeNode.total_len]
    add     rcx, rdx
    mov     [r14 + RopeNode.total_len], rcx

    ; children
    mov     [r14 + RopeNode.data], rbx      ; left
    mov     [r14 + RopeNode.right], r12     ; right

    mov     rax, r14
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
;
; Returns: RAX = STR_OK, or STR_ERR_INVALID if out of bounds.
; -----------------------------------------------------------------------------

STR_FUNC str_rope_index

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; bounds check
    cmp     rsi, [rdi + RopeNode.total_len]
    jae     .ri_oob

.ri_walk:
    movzx   eax, byte [rdi + RopeNode.tag]
    cmp     al, ROPE_LEAF
    je      .ri_leaf

    ; branch: idx < weight → go left, else go right (idx -= weight)
    mov     rcx, [rdi + RopeNode.weight]
    cmp     rsi, rcx
    jb      .ri_go_left

    sub     rsi, rcx
    mov     rdi, [rdi + RopeNode.right]
    jmp     .ri_walk

.ri_go_left:
    mov     rdi, [rdi + RopeNode.data]      ; left child
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

    ; check total fits
    mov     rax, [rbx + RopeNode.total_len]
    cmp     rax, r13
    ja      .rts_overflow

    ; recursive flatten via stack
    xor     r9, r9              ; write offset

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

; Internal recursive flatten: RDI = node, uses r9/r12/r13
.flatten:
    push    rbp
    mov     rbp, rsp

    test    rdi, rdi
    jz      .flat_ok

    movzx   eax, byte [rdi + RopeNode.tag]
    cmp     al, ROPE_LEAF
    je      .flat_leaf

    ; branch: flatten left then right
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