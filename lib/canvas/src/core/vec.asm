; ============================================================================
; Vector — Growable Array (Arena-Aware)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern arena_alloc
extern memcopy

; struct offsets (hoisted above use)
%define Vec_data        0
%define Vec.data 0
%define Vec_capacity    8
%define Vec.capacity 8
%define Vec_length      16
%define Vec.length 16
%define Vec_element_size 24
%define Vec.element_size 24
%define Vec_arena       32
%define Vec.arena 32
%define Vec_size        40

section .text

; ---------------------------------------------------------------------------
; vec_init
;   Initialize vector
;   IN:  rdi = vec pointer (Vec*)
;        rsi = arena
;        rdx = element_size
;        rcx = initial_capacity (0 = default 16)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global vec_init
vec_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi        ; vec
    mov r12, rsi        ; arena
    mov r13, rdx        ; element_size
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jnz .ok
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.ok:
    test rcx, rcx
    jnz .has_cap
    mov rcx, 16
.has_cap:
    ; Allocate buffer
    mov rdi, r12
    mov rsi, r13
    imul rsi, rcx
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Vec.data], rax
    mov qword [rbx + Vec.capacity], rcx
    mov qword [rbx + Vec.length], 0
    mov qword [rbx + Vec.element_size], r13
    mov qword [rbx + Vec.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; vec_push
;   Append element to vector
;   IN:  rdi = vec, rsi = element_ptr
;   OUT: rax = index, negative error
; ---------------------------------------------------------------------------
global vec_push
vec_push:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Vec.length]
    mov rcx, [rbx + Vec.capacity]
    cmp rax, rcx
    jae .grow

    ; Copy element
    mov rdi, [rbx + Vec.data]
    mov rsi, r12
    mov rdx, [rbx + Vec.element_size]
    call memcopy
    mov qword [rbx + Vec.length], rax
    inc qword [rbx + Vec.length]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.grow:
    ; Double capacity
    lea rcx, [rcx * 2]
    mov rdi, [rbx + Vec.arena]
    mov rsi, [rbx + Vec.element_size]
    imul rsi, rcx
    call arena_alloc
    test rax, rax
    jz .oom

    ; Copy old data
    mov rdi, rax
    mov rsi, [rbx + Vec.data]
    mov rdx, [rbx + Vec.element_size]
    imul rdx, [rbx + Vec.length]
    call memcopy

    mov qword [rbx + Vec.data], rax
    mov qword [rbx + Vec.capacity], rcx
    ; Now push
    mov rax, [rbx + Vec.length]
    mov rdi, [rbx + Vec.data]
    add rdi, rax
    imul rax, [rbx + Vec.element_size]
    add rdi, rax
    mov rsi, r12
    mov rdx, [rbx + Vec.element_size]
    call memcopy
    inc qword [rbx + Vec.length]
    mov rax, [rbx + Vec.length]
    dec rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; vec_pop
;   Remove and return last element
;   IN:  rdi = vec, rsi = out_ptr
;   OUT: rax = 0 OK, EINVAL if empty
; ---------------------------------------------------------------------------
global vec_pop
vec_pop:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Vec.length]
    test rax, rax
    jz .empty
    dec rax
    mov qword [rbx + Vec.length], rax
    imul rax, [rbx + Vec.element_size]
    mov rdi, r12
    mov rsi, [rbx + Vec.data]
    add rsi, rax
    mov rdx, [rbx + Vec.element_size]
    call memcopy
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.empty:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vec_get
;   Get element pointer by index
;   IN:  rdi = vec, rsi = index
;   OUT: rax = element_ptr, 0 if OOB
; ---------------------------------------------------------------------------
global vec_get
vec_get:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Vec.length]
    cmp rsi, rax
    jae .oob
    imul rsi, [rdi + Vec.element_size]
    mov rax, [rdi + Vec.data]
    add rax, rsi
    leave
    ret
.oob:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; vec_set
;   Set element at index
;   IN:  rdi = vec, rsi = index, rdx = element_ptr
;   OUT: rax = 0 OK, EINVAL if OOB
; ---------------------------------------------------------------------------
global vec_set
vec_set:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rax, [rbx + Vec.length]
    cmp r12, rax
    jae .oob
    imul r12, [rbx + Vec.element_size]
    mov rdi, [rbx + Vec.data]
    add rdi, r12
    mov rsi, rdx
    mov rdx, [rbx + Vec.element_size]
    call memcopy
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oob:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vec_length
;   Get current length
;   IN:  rdi = vec
;   OUT: rax = length
; ---------------------------------------------------------------------------
global vec_length
vec_length:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Vec.length]
    leave
    ret

; ---------------------------------------------------------------------------
; vec_clear
;   Clear vector (length = 0)
;   IN:  rdi = vec
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global vec_clear
vec_clear:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + Vec.length], 0
    xor rax, rax
    leave
    ret

section .data


global vec_version
vec_version: dq 0x010000
