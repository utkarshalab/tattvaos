; ============================================================================
; Unit Test — Vector and List (src/core/vec.asm, src/core/list.asm)
; ============================================================================
; test_vec_suite -> eax = failed cases (each case returns 0 / 1).
; vec: init (a zero element size refused), push returning indexes, get
; (and out of range 0), growth past the initial capacity with every element
; kept, set, pop (last first, empty -EINVAL), clear. list: push back /
; front order, pointers cleared whole (all 8 bytes), remove from the
; middle / head / tail, pop front / back, empty.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern vec_init
extern vec_push
extern vec_pop
extern vec_get
extern vec_set
extern vec_length
extern vec_clear
extern list_init
extern list_push_back
extern list_push_front
extern list_remove
extern list_pop_front
extern list_pop_back
extern list_count
extern list_empty
extern arena_init

%define L_HEAD      0                   ; List / ListNode fields
%define L_TAIL      8
%define N_PREV      0
%define N_NEXT      8

section .text

global test_vec_suite
global test_vec_main
test_vec_suite:
test_vec_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tv_init_bad
    CASE tv_push_get
    CASE tv_grow
    CASE tv_set
    CASE tv_pop
    CASE tv_clear
    CASE tl_order
    CASE tl_cleared_whole
    CASE tl_remove
    CASE tl_pop
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

; a fresh vec of 8-byte elements, capacity edx -> rax
fresh_vec:
    push rbx
    mov ebx, edx
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 65536
    call arena_init
    lea rdi, [rel vec]
    lea rsi, [rel arena]
    mov edx, 8
    mov ecx, ebx
    call vec_init
    pop rbx
    ret

; push the qword edi -> rax
push_q:
    mov [rel elem], rdi
    lea rdi, [rel vec]
    lea rsi, [rel elem]
    jmp vec_push

tv_init_bad:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 65536
    call arena_init
    lea rdi, [rel vec]
    lea rsi, [rel arena]
    xor edx, edx
    mov ecx, 4
    call vec_init
    cmp rax, -(EINVAL)
    FAIL_IF ne
    PASS

; three pushes: indexes 0, 1, 2; each element back; index 3 out of range
tv_push_get:
    sub rsp, 8
    mov edx, 4
    call fresh_vec
    test rax, rax
    FAIL_IF nz
    mov edi, 100
    call push_q
    test rax, rax
    FAIL_IF nz
    mov edi, 200
    call push_q
    cmp rax, 1
    FAIL_IF ne
    mov edi, 300
    call push_q
    cmp rax, 2
    FAIL_IF ne
    lea rdi, [rel vec]
    xor esi, esi
    call vec_get
    cmp qword [rax], 100
    FAIL_IF ne
    lea rdi, [rel vec]
    mov esi, 2
    call vec_get
    cmp qword [rax], 300
    FAIL_IF ne
    lea rdi, [rel vec]
    mov esi, 3
    call vec_get
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel vec]
    call vec_length
    cmp rax, 3
    FAIL_IF ne
    PASS

; 50 pushes into capacity 2: all kept in order
tv_grow:
    push rbx
    mov edx, 2
    call fresh_vec
    xor ebx, ebx
.push:
    lea edi, [rbx * 3 + 7]
    call push_q
    cmp rax, rbx
    FAIL_IF ne
    inc ebx
    cmp ebx, 50
    jb .push
    xor ebx, ebx
.check:
    lea rdi, [rel vec]
    mov esi, ebx
    call vec_get
    test rax, rax
    FAIL_IF z
    lea ecx, [rbx * 3 + 7]
    cmp [rax], rcx
    FAIL_IF ne
    inc ebx
    cmp ebx, 50
    jb .check
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

tv_set:
    sub rsp, 8
    mov edx, 4
    call fresh_vec
    mov edi, 1
    call push_q
    mov edi, 2
    call push_q
    mov qword [rel elem], 99
    lea rdi, [rel vec]
    mov esi, 1
    lea rdx, [rel elem]
    call vec_set
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel vec]
    mov esi, 1
    call vec_get
    cmp qword [rax], 99
    FAIL_IF ne
    lea rdi, [rel vec]
    mov esi, 5
    lea rdx, [rel elem]
    call vec_set
    cmp rax, -(EINVAL)
    FAIL_IF ne
    PASS

tv_pop:
    sub rsp, 8
    mov edx, 4
    call fresh_vec
    mov edi, 10
    call push_q
    mov edi, 20
    call push_q
    lea rdi, [rel vec]
    lea rsi, [rel out]
    call vec_pop
    test rax, rax
    FAIL_IF nz
    cmp qword [rel out], 20
    FAIL_IF ne
    lea rdi, [rel vec]
    lea rsi, [rel out]
    call vec_pop
    cmp qword [rel out], 10
    FAIL_IF ne
    lea rdi, [rel vec]
    lea rsi, [rel out]
    call vec_pop
    cmp rax, -(EINVAL)
    FAIL_IF ne
    PASS

tv_clear:
    sub rsp, 8
    mov edx, 4
    call fresh_vec
    mov edi, 1
    call push_q
    lea rdi, [rel vec]
    call vec_clear
    lea rdi, [rel vec]
    call vec_length
    test rax, rax
    FAIL_IF nz
    mov edi, 5
    call push_q
    test rax, rax                       ; index 0 again
    FAIL_IF nz
    PASS

; back a, back b, front c: c a b; count 3
tl_order:
    sub rsp, 8
    call fresh_list
    lea rdi, [rel list]
    lea rsi, [rel node_a]
    call list_push_back
    lea rdi, [rel list]
    lea rsi, [rel node_b]
    call list_push_back
    lea rdi, [rel list]
    lea rsi, [rel node_c]
    call list_push_front
    lea rcx, [rel node_c]
    cmp [rel list + L_HEAD], rcx
    FAIL_IF ne
    lea rcx, [rel node_a]
    cmp [rel node_c + N_NEXT], rcx
    FAIL_IF ne
    lea rcx, [rel node_b]
    cmp [rel node_a + N_NEXT], rcx
    FAIL_IF ne
    cmp [rel list + L_TAIL], rcx
    FAIL_IF ne
    lea rcx, [rel node_a]
    cmp [rel node_b + N_PREV], rcx
    FAIL_IF ne
    lea rdi, [rel list]
    call list_count
    cmp rax, 3
    FAIL_IF ne
    PASS

; nodes holding garbage pushed / popped: their links 0 in all 8 bytes
tl_cleared_whole:
    sub rsp, 8
    call fresh_list
    mov rax, -1
    mov [rel node_a + N_PREV], rax
    mov [rel node_a + N_NEXT], rax
    lea rdi, [rel list]
    lea rsi, [rel node_a]
    call list_push_back
    cmp qword [rel node_a + N_PREV], 0
    FAIL_IF ne
    cmp qword [rel node_a + N_NEXT], 0
    FAIL_IF ne
    lea rdi, [rel list]
    call list_pop_front
    cmp qword [rel list + L_HEAD], 0
    FAIL_IF ne
    cmp qword [rel list + L_TAIL], 0
    FAIL_IF ne
    PASS

; a b c: remove b (middle), a (head), c (tail): empty
tl_remove:
    sub rsp, 8
    call fresh_list
    call abc
    lea rdi, [rel list]
    lea rsi, [rel node_b]
    call list_remove
    lea rcx, [rel node_c]
    cmp [rel node_a + N_NEXT], rcx
    FAIL_IF ne
    lea rcx, [rel node_a]
    cmp [rel node_c + N_PREV], rcx
    FAIL_IF ne
    lea rdi, [rel list]
    lea rsi, [rel node_a]
    call list_remove
    lea rcx, [rel node_c]
    cmp [rel list + L_HEAD], rcx
    FAIL_IF ne
    cmp qword [rel node_c + N_PREV], 0
    FAIL_IF ne
    lea rdi, [rel list]
    lea rsi, [rel node_c]
    call list_remove
    lea rdi, [rel list]
    call list_empty
    cmp rax, 1
    FAIL_IF ne
    cmp qword [rel list + L_HEAD], 0
    FAIL_IF ne
    cmp qword [rel list + L_TAIL], 0
    FAIL_IF ne
    PASS

; a b c: pop front a, pop back c, pop back b, then 0
tl_pop:
    sub rsp, 8
    call fresh_list
    call abc
    lea rdi, [rel list]
    call list_pop_front
    lea rcx, [rel node_a]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel list]
    call list_pop_back
    lea rcx, [rel node_c]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel list]
    call list_pop_back
    lea rcx, [rel node_b]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel list]
    call list_pop_front
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel list]
    call list_count
    test rax, rax
    FAIL_IF nz
    PASS

fresh_list:
    lea rdi, [rel list]
    jmp list_init

; the list a b c
abc:
    sub rsp, 8
    lea rdi, [rel list]
    lea rsi, [rel node_a]
    call list_push_back
    lea rdi, [rel list]
    lea rsi, [rel node_b]
    call list_push_back
    lea rdi, [rel list]
    lea rsi, [rel node_c]
    call list_push_back
    add rsp, 8
    ret

section .bss
alignb 16
store:      resb 65536
arena:      resq 4
vec:        resq 5
elem:       resq 1
out:        resq 1
list:       resq 3
node_a:     resq 2
node_b:     resq 2
node_c:     resq 2
