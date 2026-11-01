; ============================================================================
; Unit Test — Red-Black Tree, Bitset, UTF-8
;             (src/core/rbtree.asm, src/core/bitset.asm, src/core/utf8.asm)
; ============================================================================
; test_tree_suite -> eax = failed cases (each case returns 0 / 1).
; rbtree: 200 keys in a scrambled order (every invariant after each insert:
; order, no red child of a red node, equal black heights, parent links, the
; count), all found, a present key's value replaced, min / max, removing
; every other key (invariants after each; the removed node unlinked, the
; others still holding their own keys), removing a missing key -ENOENT,
; emptying it. bitset: init (no bits refused), set / test / clear / flip,
; out of range -ERANGE, count, find_first, clear_all, a 130-bit set's last
; word. utf8: decode (1 to 4 bytes, overlong, surrogate, past U+10FFFF, a
; stray continuation, truncated), validate, encode (sizes, a surrogate and
; too large refused, the buffer too small).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern rbtree_init
extern rbtree_insert
extern rbtree_find
extern rbtree_remove
extern rbtree_min
extern rbtree_max
extern rbtree_count
extern bitset_init
extern bitset_set
extern bitset_clear
extern bitset_flip
extern bitset_test
extern bitset_count
extern bitset_find_first
extern bitset_clear_all
extern utf8_decode
extern utf8_validate
extern utf8_encode
extern arena_init

%define N_L     0                       ; RBNode
%define N_R     8
%define N_P     16
%define N_C     24
%define N_KEY   32
%define N_VAL   40
%define N_SIZE  48
%define NKEYS   200

section .text

global test_tree_suite
global test_tree_main
test_tree_suite:
test_tree_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE trb_insert
    CASE trb_find
    CASE trb_update
    CASE trb_min_max
    CASE trb_remove
    CASE trb_remove_missing
    CASE trb_empty
    CASE tbs_basic
    CASE tbs_range
    CASE tbs_count_find
    CASE tbs_wide
    CASE tu_decode
    CASE tu_invalid
    CASE tu_validate
    CASE tu_encode
    mov eax, ebx
    pop rbx
    ret

%macro FAIL_IF 1
    j%1 .fail
%endmacro
%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; key i: a scramble of 0 .. NKEYS-1 times 10 (37 is prime to 200)
%macro KEY_OF 2                         ; dst, index register
    imul %1, %2, 37
    mov rax, %1
    xor edx, edx
    mov ecx, NKEYS
    div ecx
    imul %1, rdx, 10
%endmacro

; check the whole tree -> eax 0 good, 1 broken
check_tree:
    push rbx
    mov rdi, [rel tree]                 ; root
    test rdi, rdi
    jz .empty
    cmp qword [rdi + N_P], 0
    jne .bad
    cmp byte [rdi + N_C], 1             ; the root black
    jne .bad
    mov qword [rel seen], 0
    mov rsi, 0x8000000000000000         ; low bound
    mov rdx, 0x7FFFFFFFFFFFFFFF         ; high bound
    call check_node
    test rax, rax
    js .bad
    mov rax, [rel seen]
    cmp rax, [rel tree + 8]             ; the count
    jne .bad
    xor eax, eax
    pop rbx
    ret
.empty:
    xor eax, eax
    cmp qword [rel tree + 8], 0
    setne al
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

; rdi = node (not 0), rsi / rdx = the key bounds -> rax = black height, -1 broken
check_node:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    inc qword [rel seen]
    mov rax, [rbx + N_KEY]
    cmp rax, r12
    jl .bad
    cmp rax, r13
    jg .bad
    ; a red node's children are black
    cmp byte [rbx + N_C], 0
    jne .children
    mov rcx, [rbx + N_L]
    test rcx, rcx
    jz .red_right
    cmp byte [rcx + N_C], 0
    je .bad
.red_right:
    mov rcx, [rbx + N_R]
    test rcx, rcx
    jz .children
    cmp byte [rcx + N_C], 0
    je .bad
.children:
    ; left: parent link, keys below
    mov r14d, 1                         ; a null child's black height
    mov rdi, [rbx + N_L]
    test rdi, rdi
    jz .left_done
    cmp [rdi + N_P], rbx
    jne .bad
    mov rsi, r12
    mov rdx, [rbx + N_KEY]
    dec rdx
    call check_node
    test rax, rax
    js .bad
    mov r14, rax
.left_done:
    mov eax, 1
    mov rdi, [rbx + N_R]
    test rdi, rdi
    jz .right_done
    cmp [rdi + N_P], rbx
    jne .bad
    mov rsi, [rbx + N_KEY]
    inc rsi
    mov rdx, r13
    call check_node
    test rax, rax
    js .bad
.right_done:
    cmp rax, r14
    jne .bad
    cmp byte [rbx + N_C], 1
    jne .out
    inc rax
    jmp .out
.bad:
    mov rax, -1
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; the tree with all NKEYS keys (value = key + 1), checked after each insert
fill:
    push rbx
    push r12
    lea rdi, [rel tree]
    call rbtree_init
    xor ebx, ebx
.each:
    KEY_OF r12, rbx
    lea rdi, [rel tree]
    mov rsi, r12
    lea rdx, [r12 + 1]
    imul rcx, rbx, N_SIZE
    lea r8, [rel nodes]
    add rcx, r8
    call rbtree_insert
    test rax, rax
    jnz .bad
    call check_tree
    test eax, eax
    jnz .bad
    inc ebx
    cmp ebx, NKEYS
    jb .each
    xor eax, eax
    pop r12
    pop rbx
    ret
.bad:
    mov eax, 1
    pop r12
    pop rbx
    ret

trb_insert:
    sub rsp, 8
    call fill
    test eax, eax
    FAIL_IF nz
    lea rdi, [rel tree]
    call rbtree_count
    cmp rax, NKEYS
    FAIL_IF ne
    PASS

trb_find:
    push rbx
    call fill
    xor ebx, ebx
.each:
    imul rsi, rbx, 10
    lea rdi, [rel tree]
    call rbtree_find
    imul rcx, rbx, 10
    inc rcx
    cmp rax, rcx
    FAIL_IF ne
    inc ebx
    cmp ebx, NKEYS
    jb .each
    lea rdi, [rel tree]
    mov esi, 5                          ; between keys
    call rbtree_find
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

trb_update:
    sub rsp, 8
    call fill
    lea rdi, [rel tree]
    mov esi, 500
    mov edx, 7777
    lea rcx, [rel spare]
    call rbtree_insert
    lea rdi, [rel tree]
    mov esi, 500
    call rbtree_find
    cmp rax, 7777
    FAIL_IF ne
    lea rdi, [rel tree]
    call rbtree_count
    cmp rax, NKEYS
    FAIL_IF ne
    call check_tree
    test eax, eax
    FAIL_IF nz
    PASS

trb_min_max:
    sub rsp, 8
    call fill
    lea rdi, [rel tree]
    call rbtree_min
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel tree]
    call rbtree_max
    cmp rax, (NKEYS - 1) * 10
    FAIL_IF ne
    PASS

; every other inserted key removed: invariants each time; the removed
; node unlinked; every node left holds its own key, all still found
trb_remove:
    push rbx
    push r12
    sub rsp, 8
    call fill
    xor ebx, ebx
.each:
    KEY_OF r12, rbx
    lea rdi, [rel tree]
    mov rsi, r12
    call rbtree_remove
    test rax, rax
    FAIL_IF nz
    call check_tree
    test eax, eax
    FAIL_IF nz
    imul rcx, rbx, N_SIZE
    lea r8, [rel nodes]
    cmp qword [r8 + rcx + N_P], 0
    FAIL_IF ne
    cmp qword [r8 + rcx + N_L], 0
    FAIL_IF ne
    add ebx, 2
    cmp ebx, NKEYS
    jb .each
    lea rdi, [rel tree]
    call rbtree_count
    cmp rax, NKEYS / 2
    FAIL_IF ne
    mov ebx, 1
.kept:
    KEY_OF r12, rbx
    imul rcx, rbx, N_SIZE
    lea r8, [rel nodes]
    cmp [r8 + rcx + N_KEY], r12         ; its own key
    FAIL_IF ne
    lea rdi, [rel tree]
    mov rsi, r12
    call rbtree_find
    lea rcx, [r12 + 1]
    cmp rax, rcx
    FAIL_IF ne
    add ebx, 2
    cmp ebx, NKEYS
    jb .kept
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

trb_remove_missing:
    sub rsp, 8
    call fill
    lea rdi, [rel tree]
    mov esi, 3
    call rbtree_remove
    cmp rax, -(ENOENT)
    FAIL_IF ne
    PASS

; all removed in insertion order: empty, the root 0
trb_empty:
    push rbx
    push r12
    sub rsp, 8
    call fill
    xor ebx, ebx
.each:
    KEY_OF r12, rbx
    lea rdi, [rel tree]
    mov rsi, r12
    call rbtree_remove
    test rax, rax
    FAIL_IF nz
    call check_tree
    test eax, eax
    FAIL_IF nz
    inc ebx
    cmp ebx, NKEYS
    jb .each
    cmp qword [rel tree], 0
    FAIL_IF ne
    lea rdi, [rel tree]
    call rbtree_max
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; a fresh bitset of esi bits -> rax
fresh_bits:
    push rbx
    mov ebx, esi
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 4096
    call arena_init
    lea rdi, [rel bset]
    mov esi, ebx
    lea rdx, [rel arena]
    call bitset_init
    pop rbx
    ret

%macro BIT 2                            ; operation, index -> rax
    lea rdi, [rel bset]
    mov esi, %2
    call bitset_%1
%endmacro

tbs_basic:
    sub rsp, 8
    xor esi, esi
    call fresh_bits
    cmp rax, -(EINVAL)
    FAIL_IF ne
    mov esi, 100
    call fresh_bits
    test rax, rax
    FAIL_IF nz
    BIT test, 5
    test rax, rax
    FAIL_IF nz
    BIT set, 5
    BIT set, 70
    BIT test, 5
    cmp rax, 1
    FAIL_IF ne
    BIT test, 70
    cmp rax, 1
    FAIL_IF ne
    BIT test, 6
    test rax, rax
    FAIL_IF nz
    BIT clear, 5
    BIT test, 5
    test rax, rax
    FAIL_IF nz
    BIT flip, 6
    BIT test, 6
    cmp rax, 1
    FAIL_IF ne
    BIT flip, 6
    BIT test, 6
    test rax, rax
    FAIL_IF nz
    PASS

tbs_range:
    sub rsp, 8
    mov esi, 100
    call fresh_bits
    BIT set, 100
    cmp rax, -(ERANGE)
    FAIL_IF ne
    BIT test, 1000
    cmp rax, -(ERANGE)
    FAIL_IF ne
    BIT set, 99
    test rax, rax
    FAIL_IF nz
    PASS

tbs_count_find:
    sub rsp, 8
    mov esi, 200
    call fresh_bits
    lea rdi, [rel bset]
    call bitset_find_first
    cmp rax, -1
    FAIL_IF ne
    BIT set, 150
    BIT set, 64
    BIT set, 199
    lea rdi, [rel bset]
    call bitset_count
    cmp rax, 3
    FAIL_IF ne
    lea rdi, [rel bset]
    call bitset_find_first
    cmp rax, 64
    FAIL_IF ne
    lea rdi, [rel bset]
    call bitset_clear_all
    lea rdi, [rel bset]
    call bitset_count
    test rax, rax
    FAIL_IF nz
    PASS

; 130 bits: bit 129 in the third word, the storage after it untouched
tbs_wide:
    sub rsp, 8
    mov esi, 130
    call fresh_bits
    mov rax, [rel bset]                 ; the words
    mov qword [rax + 24], 0x5A5A        ; past the three words
    BIT set, 129
    mov rax, [rel bset]
    cmp qword [rax + 16], 2
    FAIL_IF ne
    lea rdi, [rel bset]
    call bitset_clear_all
    mov rax, [rel bset]
    cmp qword [rax + 24], 0x5A5A
    FAIL_IF ne
    PASS

; decode bytes in u8buf (length edx) -> rax bytes, the code point in cp
%macro DECODE 1+
    lea rdi, [rel %%bytes]
    mov esi, %%end - %%bytes
    lea rdx, [rel cp]
    call utf8_decode
    jmp %%after
%%bytes: db %1
%%end:
%%after:
%endmacro

tu_decode:
    sub rsp, 8
    DECODE 'A'
    cmp rax, 1
    FAIL_IF ne
    cmp dword [rel cp], 'A'
    FAIL_IF ne
    DECODE 0xC3, 0xA9                   ; U+00E9
    cmp rax, 2
    FAIL_IF ne
    cmp dword [rel cp], 0xE9
    FAIL_IF ne
    DECODE 0xE2, 0x82, 0xAC             ; U+20AC
    cmp rax, 3
    FAIL_IF ne
    cmp dword [rel cp], 0x20AC
    FAIL_IF ne
    DECODE 0xF0, 0x9F, 0x98, 0x80       ; U+1F600
    cmp rax, 4
    FAIL_IF ne
    cmp dword [rel cp], 0x1F600
    FAIL_IF ne
    DECODE 0xF4, 0x8F, 0xBF, 0xBF       ; U+10FFFF
    cmp rax, 4
    FAIL_IF ne
    PASS

tu_invalid:
    sub rsp, 8
    DECODE 0xC0, 0x80                   ; overlong NUL
    test rax, rax
    FAIL_IF nz
    DECODE 0xE0, 0x80, 0x80             ; overlong
    test rax, rax
    FAIL_IF nz
    DECODE 0xED, 0xA0, 0x80             ; U+D800
    test rax, rax
    FAIL_IF nz
    DECODE 0xF4, 0x90, 0x80, 0x80       ; past U+10FFFF
    test rax, rax
    FAIL_IF nz
    DECODE 0x80                         ; a stray continuation
    test rax, rax
    FAIL_IF nz
    DECODE 0xE2, 0x82                   ; truncated
    test rax, rax
    FAIL_IF nz
    DECODE 0xC3, 0x41                   ; not a continuation
    test rax, rax
    FAIL_IF nz
    PASS

tu_validate:
    sub rsp, 8
    lea rdi, [rel good_text]
    mov esi, good_text_end - good_text
    call utf8_validate
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel bad_text]
    mov esi, bad_text_end - bad_text
    call utf8_validate
    cmp rax, -(EILSEQ)
    FAIL_IF ne
    lea rdi, [rel good_text]
    xor esi, esi
    call utf8_validate
    test rax, rax
    FAIL_IF nz
    PASS

tu_encode:
    sub rsp, 8
    mov edi, 0x20AC
    lea rsi, [rel u8buf]
    mov edx, 4
    call utf8_encode
    cmp rax, 3
    FAIL_IF ne
    cmp byte [rel u8buf], 0xE2
    FAIL_IF ne
    cmp byte [rel u8buf + 2], 0xAC
    FAIL_IF ne
    mov edi, 0x1F600
    lea rsi, [rel u8buf]
    mov edx, 4
    call utf8_encode
    cmp rax, 4
    FAIL_IF ne
    cmp dword [rel u8buf], 0x80989FF0
    FAIL_IF ne
    mov edi, 0xD800
    lea rsi, [rel u8buf]
    mov edx, 4
    call utf8_encode
    test rax, rax
    FAIL_IF nz
    mov edi, 0x110000
    lea rsi, [rel u8buf]
    mov edx, 4
    call utf8_encode
    test rax, rax
    FAIL_IF nz
    mov edi, 0xE9
    lea rsi, [rel u8buf]
    mov edx, 1
    call utf8_encode
    test rax, rax
    FAIL_IF nz
    PASS

section .rodata
good_text:  db "caf", 0xC3, 0xA9, " ", 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80
good_text_end:
bad_text:   db "ok", 0xED, 0xA0, 0x80, "x"
bad_text_end:

section .bss
alignb 16
tree:       resq 2
nodes:      resb NKEYS * N_SIZE
spare:      resb N_SIZE
seen:       resq 1
store:      resb 4096
arena:      resq 4
bset:       resq 2
cp:         resd 1
u8buf:      resb 8
