; ============================================================================
; Unit Test — Hash Map (src/core/map.asm, src/core/hash.asm)
; ============================================================================
; test_map_suite -> eax = failed cases (each case returns 0 / 1).
; fnv1a_hash (FNV-1a 64 known values); map_init (16 at least, a power of
; two, bad arguments refused); put / get (a missing key 0, an overwrite
; keeping the count, keys of equal length or prefix told apart, the empty
; key); remove (then missing, a missing key -ENOENT, the slot reused);
; growth past three quarters (every key still found); clear.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern fnv1a_hash
extern map_init
extern map_put
extern map_get
extern map_remove
extern map_count
extern map_clear
extern arena_init

%define M_CAP       8                   ; map fields (src/core/map.asm)
%define M_MASK      16
%define N_KEYS      40                  ; keys for the growth case
%define STORE       65536

section .text

global test_map_suite
global test_map_main
test_map_suite:
test_map_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tmap_fnv
    CASE tmap_init
    CASE tmap_init_bad
    CASE tmap_put_get
    CASE tmap_overwrite
    CASE tmap_similar_keys
    CASE tmap_empty_key
    CASE tmap_remove
    CASE tmap_remove_missing
    CASE tmap_reuse
    CASE tmap_grow
    CASE tmap_clear
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

; a fresh arena and map (capacity asked: edx) -> rax 0
fresh:
    push rbx
    mov ebx, edx
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, STORE
    call arena_init
    lea rdi, [rel map]
    lea rsi, [rel arena]
    mov edx, ebx
    call map_init
    pop rbx
    ret

; put key rsi (length edx) = value rcx
%macro PUT 3
    lea rdi, [rel map]
    lea rsi, [rel %1]
    mov edx, %2
    mov rcx, %3
    call map_put
%endmacro
%macro GET 2
    lea rdi, [rel map]
    lea rsi, [rel %1]
    mov edx, %2
    call map_get
%endmacro

tmap_fnv:
    sub rsp, 8
    lea rdi, [rel k_a]
    xor esi, esi
    call fnv1a_hash
    mov rcx, 0xcbf29ce484222325         ; the offset basis
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel k_a]
    mov esi, 1
    call fnv1a_hash
    mov rcx, 0xaf63dc4c8601ec8c         ; FNV-1a 64 of "a"
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel k_foobar]
    mov esi, 6
    call fnv1a_hash
    mov rcx, 0x85944171f73967e8         ; of "foobar"
    cmp rax, rcx
    FAIL_IF ne
    PASS

; asked 5: 16; asked 100: 128; empty
tmap_init:
    sub rsp, 8
    mov edx, 5
    call fresh
    test rax, rax
    FAIL_IF nz
    cmp qword [rel map + M_CAP], 16
    FAIL_IF ne
    cmp qword [rel map + M_MASK], 15
    FAIL_IF ne
    lea rdi, [rel map]
    call map_count
    test rax, rax
    FAIL_IF nz
    mov edx, 100
    call fresh
    cmp qword [rel map + M_CAP], 128
    FAIL_IF ne
    PASS

tmap_init_bad:
    sub rsp, 8
    xor edi, edi
    lea rsi, [rel arena]
    mov edx, 16
    call map_init
    cmp rax, -(EINVAL)
    FAIL_IF ne
    lea rdi, [rel map]
    xor esi, esi
    mov edx, 16
    call map_init
    cmp rax, -(EINVAL)
    FAIL_IF ne
    PASS

tmap_put_get:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_alpha, 5, 111
    test rax, rax
    FAIL_IF nz
    PUT k_beta, 4, 222
    GET k_alpha, 5
    cmp rax, 111
    FAIL_IF ne
    GET k_beta, 4
    cmp rax, 222
    FAIL_IF ne
    GET k_gamma, 5
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel map]
    call map_count
    cmp rax, 2
    FAIL_IF ne
    PASS

tmap_overwrite:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_alpha, 5, 1
    PUT k_alpha2, 5, 2                  ; the same bytes elsewhere
    GET k_alpha, 5
    cmp rax, 2
    FAIL_IF ne
    lea rdi, [rel map]
    call map_count
    cmp rax, 1
    FAIL_IF ne
    PASS

; "alpha" / "alphb" (same length), "alp" (a prefix): three keys
tmap_similar_keys:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_alpha, 5, 10
    PUT k_alphb, 5, 20
    PUT k_alpha, 3, 30
    GET k_alpha, 5
    cmp rax, 10
    FAIL_IF ne
    GET k_alphb, 5
    cmp rax, 20
    FAIL_IF ne
    GET k_alpha, 3
    cmp rax, 30
    FAIL_IF ne
    lea rdi, [rel map]
    call map_count
    cmp rax, 3
    FAIL_IF ne
    PASS

tmap_empty_key:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_a, 0, 77
    test rax, rax
    FAIL_IF nz
    GET k_a, 0
    cmp rax, 77
    FAIL_IF ne
    GET k_a, 1
    test rax, rax
    FAIL_IF nz
    PASS

tmap_remove:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_alpha, 5, 5
    PUT k_beta, 4, 6
    lea rdi, [rel map]
    lea rsi, [rel k_alpha]
    mov edx, 5
    call map_remove
    test rax, rax
    FAIL_IF nz
    GET k_alpha, 5
    test rax, rax
    FAIL_IF nz
    GET k_beta, 4
    cmp rax, 6
    FAIL_IF ne
    lea rdi, [rel map]
    call map_count
    cmp rax, 1
    FAIL_IF ne
    PASS

tmap_remove_missing:
    sub rsp, 8
    mov edx, 16
    call fresh
    lea rdi, [rel map]
    lea rsi, [rel k_alpha]
    mov edx, 5
    call map_remove
    cmp rax, -(ENOENT)
    FAIL_IF ne
    PASS

; removed then put again: found, counted once
tmap_reuse:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_alpha, 5, 1
    lea rdi, [rel map]
    lea rsi, [rel k_alpha]
    mov edx, 5
    call map_remove
    PUT k_alpha, 5, 9
    GET k_alpha, 5
    cmp rax, 9
    FAIL_IF ne
    lea rdi, [rel map]
    call map_count
    cmp rax, 1
    FAIL_IF ne
    PASS

; 40 keys (8-byte keys "key" + index) in a 16 table: grown, all found
tmap_grow:
    push rbx
    mov edx, 16
    call fresh
    xor ebx, ebx
.put:
    lea rsi, [rel keys + rbx * 8]
    mov dword [rsi], 'key_'
    mov [rsi + 4], ebx
    lea rdi, [rel map]
    mov edx, 8
    lea rcx, [rbx + 1000]
    call map_put
    test rax, rax
    FAIL_IF nz
    inc ebx
    cmp ebx, N_KEYS
    jb .put
    cmp qword [rel map + M_CAP], 64
    FAIL_IF b
    lea rdi, [rel map]
    call map_count
    cmp rax, N_KEYS
    FAIL_IF ne
    xor ebx, ebx
.get:
    lea rdi, [rel map]
    lea rsi, [rel keys + rbx * 8]
    mov edx, 8
    call map_get
    lea rcx, [rbx + 1000]
    cmp rax, rcx
    FAIL_IF ne
    inc ebx
    cmp ebx, N_KEYS
    jb .get
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

tmap_clear:
    sub rsp, 8
    mov edx, 16
    call fresh
    PUT k_alpha, 5, 1
    PUT k_beta, 4, 2
    lea rdi, [rel map]
    call map_clear
    lea rdi, [rel map]
    call map_count
    test rax, rax
    FAIL_IF nz
    GET k_alpha, 5
    test rax, rax
    FAIL_IF nz
    PASS

section .rodata
k_a:        db "a"
k_foobar:   db "foobar"
k_alpha:    db "alpha"
k_alpha2:   db "alpha"
k_alphb:    db "alphb"
k_beta:     db "beta"
k_gamma:    db "gamma"

section .bss
alignb 16
store:      resb STORE
arena:      resq 4
map:        resq 5
keys:       resq N_KEYS
