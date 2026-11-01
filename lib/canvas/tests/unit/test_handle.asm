; ============================================================================
; Unit Test — Handle Table (src/core/handle.asm)
; ============================================================================
; test_handle_suite -> eax = failed cases (each case returns 0 / 1).
; init (rounded to a power of two, over the limit refused); create / resolve
; (never 0, distinct, the object back); a bad index or generation resolving
; to 0; destroy (the count, the handle dead, the other alive, twice refused);
; a slot reused with a new generation (the old handle stays dead); full;
; clear; callee-saved registers kept.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern handle_table_init
extern handle_create
extern handle_resolve
extern handle_destroy
extern handle_count
extern handle_table_clear
extern arena_init

%define HT_CAP      8                   ; HandleTable fields

section .text

global test_handle_suite
global test_handle_main
test_handle_suite:
test_handle_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE th_init
    CASE th_init_too_big
    CASE th_create_resolve
    CASE th_bad_handles
    CASE th_destroy
    CASE th_destroy_twice
    CASE th_reuse
    CASE th_full
    CASE th_clear
    CASE th_keeps_registers
    mov eax, ebx
    pop rbx
    ret

%macro FAIL_IF 1
    j%1 .fail
%endmacro

; a fresh table of capacity edx -> rax
fresh:
    push rbx
    mov ebx, edx
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, 65536
    call arena_init
    lea rdi, [rel table]
    lea rsi, [rel arena]
    mov edx, ebx
    call handle_table_init
    pop rbx
    ret

%macro CREATE 1                         ; object address -> eax handle
    lea rdi, [rel table]
    lea rsi, [rel %1]
    call handle_create
%endmacro
%macro RESOLVE 1                        ; handle register -> rax
    lea rdi, [rel table]
    mov esi, %1
    call handle_resolve
%endmacro

th_init:
    sub rsp, 8
    mov edx, 5
    call fresh
    test rax, rax
    FAIL_IF nz
    cmp qword [rel table + HT_CAP], 8
    FAIL_IF ne
    lea rdi, [rel table]
    call handle_count
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

th_init_too_big:
    sub rsp, 8
    mov edx, 2 * 1048576
    call fresh
    cmp rax, -(EINVAL)
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; two objects: handles not 0 and distinct, each resolving to its object
th_create_resolve:
    push rbx
    push r12
    sub rsp, 8
    mov edx, 16
    call fresh
    CREATE obj_a
    test eax, eax
    FAIL_IF z
    mov ebx, eax
    CREATE obj_b
    test eax, eax
    FAIL_IF z
    mov r12d, eax
    cmp ebx, r12d
    FAIL_IF e
    RESOLVE ebx
    lea rcx, [rel obj_a]
    cmp rax, rcx
    FAIL_IF ne
    RESOLVE r12d
    lea rcx, [rel obj_b]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel table]
    call handle_count
    cmp rax, 2
    FAIL_IF ne
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; an index past the capacity, a wrong generation, a free slot: 0
th_bad_handles:
    push rbx
    mov edx, 16
    call fresh
    CREATE obj_a
    mov ebx, eax
    mov eax, 100                        ; index 100 of 16
    or eax, 1 << 20
    RESOLVE eax
    test rax, rax
    FAIL_IF nz
    lea eax, [rbx + (1 << 20)]          ; the next generation
    RESOLVE eax
    test rax, rax
    FAIL_IF nz
    mov eax, ebx
    inc eax                             ; the free slot after it
    RESOLVE eax
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

th_destroy:
    push rbx
    push r12
    sub rsp, 8
    mov edx, 16
    call fresh
    CREATE obj_a
    mov ebx, eax
    CREATE obj_b
    mov r12d, eax
    lea rdi, [rel table]
    mov esi, ebx
    call handle_destroy
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel table]
    call handle_count
    cmp rax, 1
    FAIL_IF ne
    RESOLVE ebx
    test rax, rax
    FAIL_IF nz
    RESOLVE r12d
    lea rcx, [rel obj_b]
    cmp rax, rcx
    FAIL_IF ne
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; destroying a handle twice: refused the second time, the count right
th_destroy_twice:
    push rbx
    mov edx, 16
    call fresh
    CREATE obj_a
    mov ebx, eax
    CREATE obj_b
    lea rdi, [rel table]
    mov esi, ebx
    call handle_destroy
    lea rdi, [rel table]
    mov esi, ebx
    call handle_destroy
    cmp rax, -(EINVAL)
    FAIL_IF ne
    lea rdi, [rel table]
    call handle_count
    cmp rax, 1
    FAIL_IF ne
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; a table of 4 filled, one freed, created again: the slot reused with a
; new generation; the old handle dead, the new one alive
th_reuse:
    push rbx
    push r12
    sub rsp, 8
    mov edx, 4
    call fresh
    CREATE obj_a
    mov ebx, eax
    CREATE obj_b
    CREATE obj_b
    CREATE obj_b
    lea rdi, [rel table]
    mov esi, ebx
    call handle_destroy
    CREATE obj_c
    test eax, eax
    FAIL_IF z
    mov r12d, eax
    mov eax, r12d
    and eax, 0xFFFFF
    mov ecx, ebx
    and ecx, 0xFFFFF
    cmp eax, ecx                        ; the same slot
    FAIL_IF ne
    cmp r12d, ebx                       ; another generation
    FAIL_IF e
    RESOLVE ebx
    test rax, rax
    FAIL_IF nz
    RESOLVE r12d
    lea rcx, [rel obj_c]
    cmp rax, rcx
    FAIL_IF ne
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

th_full:
    sub rsp, 8
    mov edx, 4
    call fresh
    CREATE obj_a
    CREATE obj_a
    CREATE obj_a
    CREATE obj_a
    CREATE obj_a
    test eax, eax
    FAIL_IF nz
    lea rdi, [rel table]
    call handle_count
    cmp rax, 4
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

th_clear:
    push rbx
    mov edx, 16
    call fresh
    CREATE obj_a
    mov ebx, eax
    lea rdi, [rel table]
    call handle_table_clear
    lea rdi, [rel table]
    call handle_count
    test rax, rax
    FAIL_IF nz
    RESOLVE ebx
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; resolve and destroy keep rbx, r12 .. r15
th_keeps_registers:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov edx, 16
    call fresh
    CREATE obj_a
    mov [rel saved], eax
    mov rbx, 0x1111
    mov r12, 0x2222
    mov r13, 0x3333
    mov r14, 0x4444
    mov r15, 0x5555
    RESOLVE [rel saved]
    lea rdi, [rel table]
    mov esi, [rel saved]
    call handle_destroy
    xor eax, eax
    cmp rbx, 0x1111
    setne al
    cmp r12, 0x2222
    setne cl
    or al, cl
    cmp r13, 0x3333
    setne cl
    or al, cl
    cmp r14, 0x4444
    setne cl
    or al, cl
    cmp r15, 0x5555
    setne cl
    or al, cl
    movzx eax, al
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .bss
alignb 16
store:      resb 65536
arena:      resq 4
table:      resq 6
obj_a:      resq 1
obj_b:      resq 1
obj_c:      resq 1
saved:      resd 1
