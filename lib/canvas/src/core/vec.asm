; ============================================================================
; Vector — Growable Array (Arena-Aware)
; ============================================================================
; Elements of a fixed size in one arena block; growing doubles the block
; (a new one, the old left to the arena).
;
;   vec_init(vec, arena, element_size, capacity)  -> 0, -EINVAL, -ENOMEM
;   vec_push(vec, element*)                       -> its index, -ENOMEM
;   vec_pop(vec, out*)                            -> 0, -EINVAL (empty)
;   vec_get(vec, index)                           -> element*, 0 out of range
;   vec_set(vec, index, element*)                 -> 0, -EINVAL out of range
;   vec_length(vec), vec_clear(vec)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern arena_alloc
extern memcopy

; struct offsets (struct_offsets.inc has the same)
struc Vec
    .data:                    resq 1
    .capacity:                resq 1
    .length:                  resq 1
    .element_size:            resq 1
    .arena:                   resq 1
endstruc

section .text

; ---------------------------------------------------------------------------
; vec_init
;   IN:  rdi = vec pointer (Vec*)
;        rsi = arena
;        rdx = element_size
;        rcx = initial_capacity (0 = default 16)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global vec_init
vec_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi        ; vec
    mov r12, rsi        ; arena
    mov r13, rdx        ; element_size
    mov r14, rcx        ; capacity
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .bad
    test r14, r14
    jnz .has_cap
    mov r14, 16
.has_cap:
    mov rax, r13
    mul r14
    jo .bad
    mov rdi, r12
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Vec.data], rax
    mov qword [rbx + Vec.capacity], r14
    mov qword [rbx + Vec.length], 0
    mov qword [rbx + Vec.element_size], r13
    mov qword [rbx + Vec.arena], r12
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; vec_push
;   Append element to vector (doubling the block when full)
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
    cmp rax, [rbx + Vec.capacity]
    jb .store
    ; full: a block twice the size, the elements copied over
    mov r13, [rbx + Vec.capacity]
    add r13, r13                        ; new capacity
    jc .oom
    mov rax, [rbx + Vec.element_size]
    mul r13
    jo .oom
    mov rdi, [rbx + Vec.arena]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax                        ; new block
    mov rdi, rax
    mov rsi, [rbx + Vec.data]
    mov rdx, [rbx + Vec.element_size]
    imul rdx, [rbx + Vec.length]
    call memcopy
    mov [rbx + Vec.data], r14
    mov [rbx + Vec.capacity], r13
.store:
    mov rdi, [rbx + Vec.length]
    imul rdi, [rbx + Vec.element_size]
    add rdi, [rbx + Vec.data]
    mov rsi, r12
    mov rdx, [rbx + Vec.element_size]
    call memcopy
    mov rax, [rbx + Vec.length]         ; its index
    inc qword [rbx + Vec.length]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; vec_pop
;   Remove the last element, copied to out_ptr
;   IN:  rdi = vec, rsi = out_ptr
;   OUT: rax = 0 OK, -EINVAL if empty
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
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.empty:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vec_get
;   IN:  rdi = vec, rsi = index
;   OUT: rax = element_ptr, 0 if out of range
; ---------------------------------------------------------------------------
global vec_get
vec_get:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, [rdi + Vec.length]
    jae .oob
    imul rsi, [rdi + Vec.element_size]
    mov rax, [rdi + Vec.data]
    add rax, rsi
    leave
    ret
.oob:
    xor eax, eax
    leave
    ret

; ---------------------------------------------------------------------------
; vec_set
;   Set element at index
;   IN:  rdi = vec, rsi = index, rdx = element_ptr
;   OUT: rax = 0 OK, -EINVAL if out of range
; ---------------------------------------------------------------------------
global vec_set
vec_set:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    cmp r12, [rbx + Vec.length]
    jae .oob
    imul r12, [rbx + Vec.element_size]
    mov rdi, [rbx + Vec.data]
    add rdi, r12
    mov rsi, rdx
    mov rdx, [rbx + Vec.element_size]
    call memcopy
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.oob:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vec_length / vec_clear
; ---------------------------------------------------------------------------
global vec_length
vec_length:
    mov rax, [rdi + Vec.length]
    ret

global vec_clear
vec_clear:
    mov qword [rdi + Vec.length], 0
    xor eax, eax
    ret

section .data
global vec_version
vec_version: dq 0x010100
