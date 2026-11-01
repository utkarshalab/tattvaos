; ============================================================================
; Unit Test — Strings and Memory (src/core/str.asm, src/core/memops.asm)
; ============================================================================
; test_str_suite -> eax = failed cases (each case returns 0 / 1).
; str_len, str_cmp / str_ncmp (order, prefix, limit), str_dup_arena (a copy
; with its terminator, the empty string), str_cat_arena, str_find_char (a
; character, the terminator, missing; rbx kept), str_find_substr (found,
; missing, the empty needle); memcopy (aligned and not), memmove (both
; overlaps, returning the destination), memset, memcmp.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern str_len
extern str_cmp
extern str_ncmp
extern str_dup_arena
extern str_cat_arena
extern str_find_char
extern str_find_substr
extern memcopy
extern memmove
extern memset
extern memcmp
extern arena_init

section .text

global test_str_suite
global test_str_main
test_str_suite:
test_str_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE ts_len
    CASE ts_cmp
    CASE ts_ncmp
    CASE ts_dup
    CASE ts_dup_empty
    CASE ts_cat
    CASE ts_find_char
    CASE ts_find_char_keeps_rbx
    CASE ts_find_substr
    CASE tm_copy
    CASE tm_move_up
    CASE tm_move_down
    CASE tm_set
    CASE tm_cmp
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

fresh_arena:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 4096
    call arena_init
    add rsp, 8
    ret

ts_len:
    sub rsp, 8
    lea rdi, [rel s_hello]
    call str_len
    cmp rax, 5
    FAIL_IF ne
    lea rdi, [rel s_empty]
    call str_len
    test rax, rax
    FAIL_IF nz
    PASS

; equal 0; "abc" < "abd" negative; "abd" > "abc" positive; a prefix is less
ts_cmp:
    sub rsp, 8
    lea rdi, [rel s_abc]
    lea rsi, [rel s_abc2]
    call str_cmp
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel s_abc]
    lea rsi, [rel s_abd]
    call str_cmp
    test rax, rax
    FAIL_IF ns
    lea rdi, [rel s_abd]
    lea rsi, [rel s_abc]
    call str_cmp
    test rax, rax
    FAIL_IF le
    lea rdi, [rel s_ab]
    lea rsi, [rel s_abc]
    call str_cmp
    test rax, rax
    FAIL_IF ns
    PASS

; the first two of "abc" / "abd" equal, three differ; a limit of 0 is equal
ts_ncmp:
    sub rsp, 8
    lea rdi, [rel s_abc]
    lea rsi, [rel s_abd]
    mov edx, 2
    call str_ncmp
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel s_abc]
    lea rsi, [rel s_abd]
    mov edx, 3
    call str_ncmp
    test rax, rax
    FAIL_IF ns
    lea rdi, [rel s_abc]
    lea rsi, [rel s_abd]
    xor edx, edx
    call str_ncmp
    test rax, rax
    FAIL_IF nz
    PASS

; a copy in the arena: another pointer, the same bytes and terminator
ts_dup:
    push rbx
    call fresh_arena
    lea rdi, [rel arena]
    lea rsi, [rel s_hello]
    call str_dup_arena
    test rax, rax
    FAIL_IF z
    mov rbx, rax
    lea rcx, [rel s_hello]
    cmp rax, rcx
    FAIL_IF e
    mov rdi, rbx
    lea rsi, [rel s_hello]
    call str_cmp
    test rax, rax
    FAIL_IF nz
    cmp byte [rbx + 5], 0
    FAIL_IF ne
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

ts_dup_empty:
    sub rsp, 8
    call fresh_arena
    lea rdi, [rel arena]
    lea rsi, [rel s_empty]
    call str_dup_arena
    test rax, rax
    FAIL_IF z
    cmp byte [rax], 0
    FAIL_IF ne
    PASS

ts_cat:
    sub rsp, 8
    call fresh_arena
    lea rdi, [rel arena]
    lea rsi, [rel s_ab]
    lea rdx, [rel s_hello]
    call str_cat_arena
    test rax, rax
    FAIL_IF z
    mov rdi, rax
    lea rsi, [rel s_abhello]
    call str_cmp
    test rax, rax
    FAIL_IF nz
    PASS

; 'l' in "hello" at 2; the terminator found at 5; 'z' missing
ts_find_char:
    sub rsp, 8
    lea rdi, [rel s_hello]
    mov esi, 'l'
    call str_find_char
    lea rcx, [rel s_hello + 2]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel s_hello]
    xor esi, esi
    call str_find_char
    lea rcx, [rel s_hello + 5]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel s_hello]
    mov esi, 'z'
    call str_find_char
    test rax, rax
    FAIL_IF nz
    PASS

; rbx is the caller's: unchanged across the call
ts_find_char_keeps_rbx:
    push rbx
    mov rbx, 0x1234567890
    lea rdi, [rel s_hello]
    mov esi, 'o'
    call str_find_char
    mov rcx, 0x1234567890
    cmp rbx, rcx
    FAIL_IF ne
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; "ll" in "hello" at 2; "lo!" missing; the empty needle at the start
ts_find_substr:
    sub rsp, 8
    lea rdi, [rel s_hello]
    lea rsi, [rel s_ll]
    call str_find_substr
    lea rcx, [rel s_hello + 2]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel s_hello]
    lea rsi, [rel s_lox]
    call str_find_substr
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel s_hello]
    lea rsi, [rel s_empty]
    call str_find_substr
    lea rcx, [rel s_hello]
    cmp rax, rcx
    FAIL_IF ne
    PASS

; 32 aligned bytes, then 7 unaligned: copied, the destination returned
tm_copy:
    sub rsp, 8
    call pattern
    lea rdi, [rel buf_b]
    lea rsi, [rel buf_a]
    mov edx, 32
    call memcopy
    lea rcx, [rel buf_b]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel buf_a]
    lea rsi, [rel buf_b]
    mov edx, 32
    call memcmp
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel buf_b + 33]
    lea rsi, [rel buf_a + 3]
    mov edx, 7
    call memcopy
    lea rdi, [rel buf_b + 33]
    lea rsi, [rel buf_a + 3]
    mov edx, 7
    call memcmp
    test rax, rax
    FAIL_IF nz
    PASS

; moving 10 bytes up by 3 over themselves: the bytes kept, the destination returned
tm_move_up:
    sub rsp, 8
    call pattern
    lea rdi, [rel buf_a + 3]
    lea rsi, [rel buf_a]
    mov edx, 10
    call memmove
    lea rcx, [rel buf_a + 3]
    cmp rax, rcx
    FAIL_IF ne
    xor ecx, ecx
.up:
    lea edx, [rcx + 1]                  ; pattern: byte i is i + 1
    cmp [rel buf_a + 3 + rcx], dl
    FAIL_IF ne
    inc ecx
    cmp ecx, 10
    jb .up
    PASS

; and down by 3
tm_move_down:
    sub rsp, 8
    call pattern
    lea rdi, [rel buf_a]
    lea rsi, [rel buf_a + 3]
    mov edx, 10
    call memmove
    lea rcx, [rel buf_a]
    cmp rax, rcx
    FAIL_IF ne
    xor ecx, ecx
.down:
    lea edx, [rcx + 4]
    cmp [rel buf_a + rcx], dl
    FAIL_IF ne
    inc ecx
    cmp ecx, 10
    jb .down
    PASS

tm_set:
    sub rsp, 8
    call pattern
    lea rdi, [rel buf_a + 1]
    mov esi, 0xAB
    mov edx, 5
    call memset
    lea rcx, [rel buf_a + 1]
    cmp rax, rcx
    FAIL_IF ne
    cmp byte [rel buf_a], 1
    FAIL_IF ne
    cmp dword [rel buf_a + 1], 0xABABABAB
    FAIL_IF ne
    cmp byte [rel buf_a + 5], 0xAB
    FAIL_IF ne
    cmp byte [rel buf_a + 6], 7
    FAIL_IF ne
    PASS

; equal 0; a smaller byte negative, a larger positive (unsigned)
tm_cmp:
    sub rsp, 8
    lea rdi, [rel m_1]
    lea rsi, [rel m_1]
    mov edx, 4
    call memcmp
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel m_1]
    lea rsi, [rel m_2]
    mov edx, 4
    call memcmp
    test rax, rax
    FAIL_IF ns
    lea rdi, [rel m_2]
    lea rsi, [rel m_1]
    mov edx, 4
    call memcmp
    test rax, rax
    FAIL_IF le
    PASS

; buf_a: bytes 1, 2, 3, ...
pattern:
    xor ecx, ecx
.fill:
    lea eax, [rcx + 1]
    mov [rel buf_a + rcx], al
    inc ecx
    cmp ecx, 64
    jb .fill
    ret

section .rodata
s_hello:    db "hello", 0
s_empty:    db 0
s_abc:      db "abc", 0
s_abc2:     db "abc", 0
s_abd:      db "abd", 0
s_ab:       db "ab", 0
s_abhello:  db "abhello", 0
s_ll:       db "ll", 0
s_lox:      db "lo!", 0
m_1:        db 1, 2, 3, 4
m_2:        db 1, 2, 0x80, 4

section .bss
alignb 16
store:      resb 4096
arena:      resq 4
alignb 16
buf_a:      resb 64
buf_b:      resb 64
