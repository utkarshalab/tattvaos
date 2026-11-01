; ============================================================================
; Unit Test — Ring Buffer (src/core/ring.asm)
; ============================================================================
; test_ring_suite -> eax = failed cases (each case returns 0 / 1).
; init (a power of two, a zero element size refused); empty (pop / peek
; -EAGAIN); push / pop in order (12-byte elements kept whole); peek not
; consuming; full at capacity - 1 (-ENOSPC); available / free; wrapping
; around many times in order; clear.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern ring_init
extern ring_push
extern ring_pop
extern ring_peek
extern ring_available
extern ring_free
extern ring_clear
extern arena_init

%define R_CAP       8                   ; Ring fields
%define ELEM        12

section .text

global test_ring_suite
global test_ring_main
test_ring_suite:
test_ring_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tr_init
    CASE tr_init_zero_size
    CASE tr_empty
    CASE tr_order
    CASE tr_peek
    CASE tr_full
    CASE tr_counts
    CASE tr_wrap
    CASE tr_clear
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

; a fresh ring of capacity edx, ELEM-byte elements -> rax
fresh:
    push rbx
    mov ebx, edx
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 8192
    call arena_init
    lea rdi, [rel ring]
    lea rsi, [rel arena]
    mov edx, ebx
    mov ecx, ELEM
    call ring_init
    pop rbx
    ret

; push the element "value v": 3 dwords v, v + 1, v + 2 -> rax
push_value:
    lea ecx, [rdi + 1]
    mov [rel elem_in], edi
    mov [rel elem_in + 4], ecx
    inc ecx
    mov [rel elem_in + 8], ecx
    lea rdi, [rel ring]
    lea rsi, [rel elem_in]
    jmp ring_push

; pop into elem_out -> rax; ecx 1 when it holds value edi (all three dwords)
pop_value:
    push rbx
    mov ebx, edi
    lea rdi, [rel ring]
    lea rsi, [rel elem_out]
    call ring_pop
    xor ecx, ecx
    cmp [rel elem_out], ebx
    jne .no
    lea edx, [rbx + 1]
    cmp [rel elem_out + 4], edx
    jne .no
    inc edx
    cmp [rel elem_out + 8], edx
    jne .no
    mov ecx, 1
.no:
    pop rbx
    ret

tr_init:
    sub rsp, 8
    mov edx, 6
    call fresh
    test rax, rax
    FAIL_IF nz
    cmp qword [rel ring + R_CAP], 8
    FAIL_IF ne
    PASS

tr_init_zero_size:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 8192
    call arena_init
    lea rdi, [rel ring]
    lea rsi, [rel arena]
    mov edx, 8
    xor ecx, ecx
    call ring_init
    cmp rax, -(EINVAL)
    FAIL_IF ne
    PASS

tr_empty:
    sub rsp, 8
    mov edx, 8
    call fresh
    lea rdi, [rel ring]
    lea rsi, [rel elem_out]
    call ring_pop
    cmp rax, -(EAGAIN)
    FAIL_IF ne
    lea rdi, [rel ring]
    lea rsi, [rel elem_out]
    call ring_peek
    cmp rax, -(EAGAIN)
    FAIL_IF ne
    PASS

; 10, 20, 30 in, out in that order, whole
tr_order:
    sub rsp, 8
    mov edx, 8
    call fresh
    mov edi, 10
    call push_value
    test rax, rax
    FAIL_IF nz
    mov edi, 20
    call push_value
    mov edi, 30
    call push_value
    mov edi, 10
    call pop_value
    test rax, rax
    FAIL_IF nz
    test ecx, ecx
    FAIL_IF z
    mov edi, 20
    call pop_value
    test ecx, ecx
    FAIL_IF z
    mov edi, 30
    call pop_value
    test ecx, ecx
    FAIL_IF z
    PASS

; peek shows the next one twice; the pop then takes it
tr_peek:
    sub rsp, 8
    mov edx, 8
    call fresh
    mov edi, 5
    call push_value
    mov edi, 6
    call push_value
    lea rdi, [rel ring]
    lea rsi, [rel elem_out]
    call ring_peek
    cmp dword [rel elem_out], 5
    FAIL_IF ne
    lea rdi, [rel ring]
    lea rsi, [rel elem_out]
    call ring_peek
    cmp dword [rel elem_out], 5
    FAIL_IF ne
    mov edi, 5
    call pop_value
    test ecx, ecx
    FAIL_IF z
    mov edi, 6
    call pop_value
    test ecx, ecx
    FAIL_IF z
    PASS

; capacity 4 holds 3; the fourth -ENOSPC
tr_full:
    sub rsp, 8
    mov edx, 4
    call fresh
    mov edi, 1
    call push_value
    mov edi, 2
    call push_value
    mov edi, 3
    call push_value
    test rax, rax
    FAIL_IF nz
    mov edi, 4
    call push_value
    cmp rax, -(ENOSPC)
    FAIL_IF ne
    mov edi, 1
    call pop_value
    test ecx, ecx
    FAIL_IF z
    PASS

; capacity 8 with 3 in: 3 available, 4 free
tr_counts:
    sub rsp, 8
    mov edx, 8
    call fresh
    mov edi, 1
    call push_value
    mov edi, 2
    call push_value
    mov edi, 3
    call push_value
    lea rdi, [rel ring]
    call ring_available
    cmp rax, 3
    FAIL_IF ne
    lea rdi, [rel ring]
    call ring_free
    cmp rax, 4
    FAIL_IF ne
    PASS

; 100 values through a capacity-4 ring, two at a time: all in order
tr_wrap:
    push rbx
    mov edx, 4
    call fresh
    xor ebx, ebx
.round:
    mov edi, ebx
    call push_value
    test rax, rax
    FAIL_IF nz
    lea edi, [rbx + 1000]
    call push_value
    test rax, rax
    FAIL_IF nz
    mov edi, ebx
    call pop_value
    test ecx, ecx
    FAIL_IF z
    lea edi, [rbx + 1000]
    call pop_value
    test ecx, ecx
    FAIL_IF z
    inc ebx
    cmp ebx, 100
    jb .round
    lea rdi, [rel ring]
    call ring_available
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

tr_clear:
    sub rsp, 8
    mov edx, 8
    call fresh
    mov edi, 1
    call push_value
    lea rdi, [rel ring]
    call ring_clear
    lea rdi, [rel ring]
    call ring_available
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel ring]
    lea rsi, [rel elem_out]
    call ring_pop
    cmp rax, -(EAGAIN)
    FAIL_IF ne
    PASS

section .bss
alignb 16
store:      resb 8192
arena:      resq 4
ring:       resq 7
elem_in:    resd 3
elem_out:   resd 3
