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
    CASE th_properties
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

; QA-08: a handle table of 8 against a model. From four seeds, 400 random
; steps: create (when 8 are live it must fail, else give a handle), destroy
; any handle ever given (a live one goes, a dead one is refused), resolve
; any (a live one gives its object, a dead one nothing, though its slot be
; used again); the count always the live ones
%define PROP_HANDLES    64              ; handles given, at most
%define PROP_STEPS      400
th_properties:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    xor r14d, r14d
.seed:
    lea rax, [rel prop_seeds]
    mov rax, [rax + r14 * 8]
    mov [rel prop_seed], rax
    mov edx, 8
    call fresh
    test rax, rax
    jnz .fail
    xor ebx, ebx                        ; handles given
    xor r13d, r13d                      ; live
    lea rdi, [rel prop_live]
    xor eax, eax
    mov ecx, PROP_HANDLES
    rep stosb
    xor r12d, r12d
.step:
    mov edi, 3
    call prop_below
    test eax, eax
    jz .create
    test ebx, ebx
    jz .counted                         ; nothing given yet
    cmp eax, 1
    je .destroy
    mov edi, ebx                        ; resolve one
    call prop_below
    mov r8d, eax
    lea rcx, [rel prop_handles]
    mov esi, [rcx + r8 * 4]
    lea rdi, [rel table]
    push r8
    push r8
    call handle_resolve
    pop r8
    pop r8
    lea rcx, [rel prop_live]
    cmp byte [rcx + r8], 0
    je .dead_resolves
    lea rcx, [rel prop_objects]
    lea rcx, [rcx + r8 * 8]
    cmp rax, rcx
    jne .fail
    jmp .counted
.dead_resolves:
    test rax, rax
    jnz .fail
    jmp .counted
.create:
    cmp ebx, PROP_HANDLES
    jae .counted
    lea rdi, [rel table]
    lea rsi, [rel prop_objects]
    lea rsi, [rsi + rbx * 8]
    call handle_create
    cmp r13d, 8
    jb .room
    test eax, eax                       ; full: refused
    jnz .fail
    jmp .counted
.room:
    test eax, eax
    jz .fail
    lea rcx, [rel prop_handles]
    mov [rcx + rbx * 4], eax
    lea rcx, [rel prop_live]
    mov byte [rcx + rbx], 1
    inc ebx
    inc r13d
    jmp .counted
.destroy:
    mov edi, ebx
    call prop_below
    mov r8d, eax
    lea rcx, [rel prop_handles]
    mov esi, [rcx + r8 * 4]
    lea rdi, [rel table]
    push r8
    push r8
    call handle_destroy
    pop r8
    pop r8
    lea rcx, [rel prop_live]
    cmp byte [rcx + r8], 0
    je .dead_destroyed
    test rax, rax                       ; a live one goes
    jnz .fail
    mov byte [rcx + r8], 0
    dec r13d
    jmp .counted
.dead_destroyed:
    test rax, rax                       ; a dead one is refused
    jz .fail
.counted:
    lea rdi, [rel table]
    call handle_count
    cmp eax, r13d
    jne .fail
    inc r12d
    cmp r12d, PROP_STEPS
    jb .step
    inc r14d
    cmp r14d, 4
    jb .seed
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -> rax = the next random number (xorshift64), from prop_seed
prop_random:
    mov rax, [rel prop_seed]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [rel prop_seed], rax
    ret

; edi = n -> eax = a random number below n
prop_below:
    push rdi
    call prop_random
    pop rcx
    xor edx, edx
    div rcx
    mov eax, edx
    ret

section .rodata
alignb 8
prop_seeds:     dq 0x9E3779B97F4A7C15, 0x0123456789ABCDEF, 0xD1B54A32D192ED03, 0x8CB92BA72F3D8DD7

section .bss
alignb 16
prop_objects:   resq PROP_HANDLES       ; what the handles stand for
prop_handles:   resd PROP_HANDLES
prop_live:      resb PROP_HANDLES
prop_seed:      resq 1
alignb 16
store:      resb 65536
arena:      resq 4
table:      resq 6
obj_a:      resq 1
obj_b:      resq 1
obj_c:      resq 1
saved:      resd 1
