; ============================================================================
; Constraints — Pointer Lock and Confine
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/rect.inc"

section .text

struc Constraints {
    .confined:      resb 1
    .confine_rect:  resb Rect_size
    .locked:        resb 1
    .lock_x:        resd 1
    .lock_y:        resd 1
}
%define Constraints_size    32

; ---------------------------------------------------------------------------
; constraints_create
; ---------------------------------------------------------------------------
global constraints_create
constraints_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, Constraints_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov byte [rax + Constraints.confined], 0
    mov byte [rax + Constraints.locked], 0
    mov dword [rax + Constraints.lock_x], 0
    mov dword [rax + Constraints.lock_y], 0
    ; rect zeroed by arena_alloc

    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; constraints_confine
;   Confine pointer to rectangle
;   IN:  rdi = constraints*, rsi = rect* (0 to disable)
; ---------------------------------------------------------------------------
global constraints_confine
constraints_confine:
    PROLOGUE
    ASSERT_PTR rdi

    test rsi, rsi
    jz .disable

    mov byte [rdi + Constraints.confined], 1
    mov rdi, [rdi + Constraints.confine_rect]
    call rect_copy
    ret

.disable:
    mov byte [rdi + Constraints.confined], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; constraints_lock
;   Lock pointer to position
;   IN:  rdi = constraints*, rsi = lock (1=lock, 0=unlock), rdx = x, rcx = y
; ---------------------------------------------------------------------------
global constraints_lock
constraints_lock:
    PROLOGUE
    ASSERT_PTR rdi

    test rsi, rsi
    jz .unlock

    mov byte [rdi + Constraints.locked], 1
    mov dword [rdi + Constraints.lock_x], edx
    mov dword [rdi + Constraints.lock_y], ecx
    ret

.unlock:
    mov byte [rdi + Constraints.locked], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; constraints_apply
;   Apply constraints to pointer position
;   IN:  rdi = constraints*, rsi = x*, rdx = y*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global constraints_apply
constraints_apply:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Lock takes priority
    cmp byte [rbx + Constraints.locked], 0
    je .check_confine

    mov eax, [rbx + Constraints.lock_x]
    mov [r12], eax
    mov eax, [rbx + Constraints.lock_y]
    mov [r13], eax
    xor rax, rax
    ret

.check_confine:
    cmp byte [rbx + Constraints.confined], 0
    je .done

    ; Clamp to confine rect
    mov eax, [r12]
    mov edx, [rbx + Constraints.confine_rect + Rect_x1]
    cmp eax, edx
    cmovl eax, edx
    mov edx, [rbx + Constraints.confine_rect + Rect_x2]
    cmp eax, edx
    cmovg eax, edx
    mov [r12], eax

    mov eax, [r13]
    mov edx, [rbx + Constraints.confine_rect + Rect_y1]
    cmp eax, edx
    cmovl eax, edx
    mov edx, [rbx + Constraints.confine_rect + Rect_y2]
    cmp eax, edx
    cmovg eax, edx
    mov [r13], eax

.done:
    xor rax, rax
    ret

section .data
global constraints_version
constraints_version: dq 0x010000