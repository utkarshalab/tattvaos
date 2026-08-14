%ifndef GUARD_LIB_STR_TRIE_ASM
%define GUARD_LIB_STR_TRIE_ASM
; =============================================================================
; str/trie.asm
; Prefix tree (trie) for dictionary lookup, autocomplete, and prefix search.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   mem/arena.asm   (str_arena_alloc)
;
; -----------------------------------------------------------------------------
; A trie stores a set of strings with shared-prefix compression.
; Each path from root to a marked node represents an inserted string.
;
; Use cases in Tattva OS:
;   - uide autocomplete (identifiers, keywords)
;   - utasm directive/mnemonic lookup
;   - DNS label matching
;   - Command-line tab completion
;
; Design: array-of-children trie with arena allocation.
; Each node uses a linked-list of children (sparse: most nodes have
; very few children, so a 256-entry array would waste memory).
;
; TrieNode layout (40 bytes):
;   .child_head  dq   — first child node index (-1 = none)
;   .sibling     dq   — next sibling in parent's child list (-1 = none)
;   .byte_val    db   — the edge byte this node represents
;   .is_terminal db   — 1 if this node marks end of an inserted string
;   .pad         db 6
;   .value       dq   — user-attached value (e.g. token ID), valid if terminal
;   .count       dq   — number of terminal nodes in this subtree
;
; Functions:
;   str_trie_init          — initialize an empty trie
;   str_trie_insert        — insert a string (with optional value)
;   str_trie_lookup        — exact lookup: is this string in the trie?
;   str_trie_starts_with   — prefix check: any string starts with this?
;   str_trie_count         — number of strings in the trie
;   str_trie_prefix_count  — number of strings starting with prefix
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

struc TrieNode
    .child_head  resq 1
    .sibling     resq 1
    .byte_val    resb 1
    .is_terminal resb 1
    .pad         resb 6
    .value       resq 1
    .count       resq 1
endstruc

TRIE_NODE_SIZE  equ 40

struc Trie
    .arena       resq 1     ; pointer to StrArena
    .root        resq 1     ; pointer to root TrieNode
    .total       resq 1     ; total strings inserted
endstruc

TRIE_SIZE       equ 24

section .text

; Internal: find child of node for byte.
; RDI = node ptr, SIL = byte
; Returns RAX = child TrieNode ptr, or 0 if none.
_trie_find_child:
    mov     rax, [rdi + TrieNode.child_head]

.tfc_walk:
    test    rax, rax
    jz      .tfc_none
    cmp     rax, -1
    je      .tfc_none_neg

    movzx   ecx, byte [rax + TrieNode.byte_val]
    cmp     cl, sil
    je      .tfc_found

    mov     rax, [rax + TrieNode.sibling]
    jmp     .tfc_walk

.tfc_found:
    ret

.tfc_none:
    ret

.tfc_none_neg:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; str_trie_init
;
; Initialize an empty trie.
;
; Signature:
;   int64_t str_trie_init(Trie *trie, StrArena *arena)
; -----------------------------------------------------------------------------

STR_FUNC str_trie_init

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     [rbx + Trie.arena], r12
    mov     qword [rbx + Trie.total], 0

    ; allocate root node
    mov     rdi, r12
    mov     rsi, TRIE_NODE_SIZE
    mov     rdx, 8
    call    str_arena_alloc
    test    rax, rax
    jz      .ti_oom

    mov     [rbx + Trie.root], rax

    ; initialize root
    mov     qword [rax + TrieNode.child_head], -1
    mov     qword [rax + TrieNode.sibling], -1
    mov     byte  [rax + TrieNode.byte_val], 0
    mov     byte  [rax + TrieNode.is_terminal], 0
    mov     qword [rax + TrieNode.value], 0
    mov     qword [rax + TrieNode.count], 0

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ti_oom:
    pop_regs r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_trie_init

; -----------------------------------------------------------------------------
; str_trie_insert
;
; Insert a string into the trie with an optional associated value.
;
; Signature:
;   int64_t str_trie_insert(Trie *trie, const StrSlice *key, uint64_t value)
; -----------------------------------------------------------------------------

STR_FUNC str_trie_insert

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; trie
    mov     r12, [rsi + StrSlice.ptr]   ; key ptr
    mov     r13, [rsi + StrSlice.len]   ; key len
    mov     r14, rdx            ; value

    mov     r15, [rbx + Trie.root]  ; current node = root

    xor     r9, r9              ; byte index

.tins_loop:
    cmp     r9, r13
    jae     .tins_mark

    movzx   esi, byte [r12 + r9]

    ; find child for this byte
    mov     rdi, r15
    push    r9
    call    _trie_find_child
    pop     r9

    test    rax, rax
    jnz     .tins_descend

    ; create new child
    mov     rdi, [rbx + Trie.arena]
    mov     rsi, TRIE_NODE_SIZE
    mov     rdx, 8
    push    r9
    call    str_arena_alloc
    pop     r9
    test    rax, rax
    jz      .tins_oom

    ; init new node
    mov     qword [rax + TrieNode.child_head], -1
    mov     byte  [rax + TrieNode.is_terminal], 0
    mov     qword [rax + TrieNode.value], 0
    mov     qword [rax + TrieNode.count], 0

    movzx   ecx, byte [r12 + r9]
    mov     [rax + TrieNode.byte_val], cl

    ; prepend to parent's child list
    mov     rcx, [r15 + TrieNode.child_head]
    mov     [rax + TrieNode.sibling], rcx
    mov     [r15 + TrieNode.child_head], rax

    mov     r15, rax            ; descend
    inc     r9
    jmp     .tins_loop

.tins_descend:
    mov     r15, rax
    inc     r9
    jmp     .tins_loop

.tins_mark:
    ; mark as terminal
    cmp     byte [r15 + TrieNode.is_terminal], 1
    je      .tins_exists        ; already inserted

    mov     byte [r15 + TrieNode.is_terminal], 1
    mov     [r15 + TrieNode.value], r14
    inc     qword [rbx + Trie.total]

.tins_exists:
    ; update value even if already exists
    mov     [r15 + TrieNode.value], r14

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tins_oom:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_trie_insert

; -----------------------------------------------------------------------------
; str_trie_lookup
;
; Check if a string exists in the trie. If found, returns its value.
;
; Signature:
;   int64_t str_trie_lookup(const Trie *trie, const StrSlice *key,
;                            uint64_t *out_value)
;
; Returns:
;   RAX = STR_OK         found (value written to *out_value if non-null)
;   RAX = STR_ERR_NOT_FOUND  not in trie
; -----------------------------------------------------------------------------

STR_FUNC str_trie_lookup

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, [rsi + StrSlice.ptr]
    mov     r13, [rsi + StrSlice.len]
    mov     r14, rdx            ; out_value

    mov     r15, [rbx + Trie.root]
    xor     r9, r9

.tlk_loop:
    cmp     r9, r13
    jae     .tlk_check_terminal

    movzx   esi, byte [r12 + r9]
    mov     rdi, r15
    push    r9
    call    _trie_find_child
    pop     r9

    test    rax, rax
    jz      .tlk_not_found

    mov     r15, rax
    inc     r9
    jmp     .tlk_loop

.tlk_check_terminal:
    cmp     byte [r15 + TrieNode.is_terminal], 1
    jne     .tlk_not_found

    test    r14, r14
    jz      .tlk_found
    mov     rax, [r15 + TrieNode.value]
    mov     [r14], rax

.tlk_found:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tlk_not_found:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_trie_lookup

; -----------------------------------------------------------------------------
; str_trie_starts_with
;
; Check if any inserted string starts with the given prefix.
;
; Signature:
;   int64_t str_trie_starts_with(const Trie *trie, const StrSlice *prefix)
;
; Returns: RAX = 1 yes, 0 no
; -----------------------------------------------------------------------------

STR_FUNC str_trie_starts_with

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, [rsi + StrSlice.ptr]
    mov     r13, [rsi + StrSlice.len]

    mov     r15, [rbx + Trie.root]
    xor     r9, r9

.tsw_loop:
    cmp     r9, r13
    jae     .tsw_yes            ; all prefix bytes matched

    movzx   esi, byte [r12 + r9]
    mov     rdi, r15
    push    r9
    call    _trie_find_child
    pop     r9

    test    rax, rax
    jz      .tsw_no

    mov     r15, rax
    inc     r9
    jmp     .tsw_loop

.tsw_yes:
    pop_regs r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.tsw_no:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_trie_starts_with

; -----------------------------------------------------------------------------
; str_trie_count
; Returns: RAX = total number of strings in the trie.
; -----------------------------------------------------------------------------

STR_FUNC str_trie_count

    test    rdi, rdi
    jz      .tc_zero
    mov     rax, [rdi + Trie.total]
    pop     rbp
    ret
.tc_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_trie_count
%endif ; GUARD_LIB_STR_TRIE_ASM
