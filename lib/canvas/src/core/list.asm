; ============================================================================
; Intrusive Doubly-Linked List
; O(1) insert/remove, no allocation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

; struct offsets (hoisted above use)
%define ListNode_prev  0
%define ListNode_next  8
%define ListNode_size  16
%define List_head      0
%define List_tail      8
%define List_count     16
%define List_size      24

section .text



; ---------------------------------------------------------------------------
; list_init
;   Initialize empty list
;   IN:  rdi = List*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global list_init
list_init:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + List_head], 0
    mov qword [rdi + List_tail], 0
    mov qword [rdi + List_count], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; list_push_back
;   Add node to end
;   IN:  rdi = List*, rsi = node*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global list_push_back
list_push_back:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi

    mov rax, [rbx + List_tail]
    test rax, rax
    jz .empty

    mov [rax + ListNode_next], rsi
    mov [rsi + ListNode_prev], rax
    mov [rsi + ListNode_next], 0
    mov [rbx + List_tail], rsi
    inc qword [rbx + List_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.empty:
    mov [rbx + List_head], rsi
    mov [rbx + List_tail], rsi
    mov [rsi + ListNode_prev], 0
    mov [rsi + ListNode_next], 0
    mov qword [rbx + List_count], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; list_push_front
;   Add node to front
;   IN:  rdi = List*, rsi = node*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global list_push_front
list_push_front:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi

    mov rax, [rbx + List_head]
    test rax, rax
    jz .empty

    mov [rax + ListNode_prev], rsi
    mov [rsi + ListNode_next], rax
    mov [rsi + ListNode_prev], 0
    mov [rbx + List_head], rsi
    inc qword [rbx + List_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.empty:
    mov [rbx + List_head], rsi
    mov [rbx + List_tail], rsi
    mov [rsi + ListNode_prev], 0
    mov [rsi + ListNode_next], 0
    mov qword [rbx + List_count], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; list_remove
;   Remove node from list
;   IN:  rdi = List*, rsi = node*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global list_remove
list_remove:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi

    mov rax, [rsi + ListNode_prev]
    mov rcx, [rsi + ListNode_next]

    test rax, rax
    jz .head
    mov [rax + ListNode_next], rcx
    jmp .check_tail

.head:
    mov [rbx + List_head], rcx

.check_tail:
    test rcx, rcx
    jz .tail
    mov [rcx + ListNode_prev], rax
    jmp .done

.tail:
    mov [rbx + List_tail], rax

.done:
    dec qword [rbx + List_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; list_pop_front
;   Remove and return first node
;   IN:  rdi = List*
;   OUT: rax = node*, 0 if empty
; ---------------------------------------------------------------------------
global list_pop_front
list_pop_front:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + List_head]
    test rax, rax
    jz .empty

    mov rcx, [rax + ListNode_next]
    mov [rbx + List_head], rcx
    test rcx, rcx
    jz .was_last
    mov [rcx + ListNode_prev], 0
    jmp .done

.was_last:
    mov [rbx + List_tail], 0

.done:
    dec qword [rbx + List_count]
    mov [rax + ListNode_prev], 0
    mov [rax + ListNode_next], 0
    EPILOGUE_RESTORE rbx
    ret

.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; list_pop_back
;   Remove and return last node
; ---------------------------------------------------------------------------
global list_pop_back
list_pop_back:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + List_tail]
    test rax, rax
    jz .empty

    mov rcx, [rax + ListNode_prev]
    mov [rbx + List_tail], rcx
    test rcx, rcx
    jz .was_last
    mov [rcx + ListNode_next], 0
    jmp .done

.was_last:
    mov [rbx + List_head], 0

.done:
    dec qword [rbx + List_count]
    mov [rax + ListNode_prev], 0
    mov [rax + ListNode_next], 0
    EPILOGUE_RESTORE rbx
    ret

.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; list_count
;   Get list length
;   IN:  rdi = List*
;   OUT: rax = count
; ---------------------------------------------------------------------------
global list_count
list_count:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + List_count]
    leave
    ret

; ---------------------------------------------------------------------------
; list_empty
;   Check if list is empty
;   IN:  rdi = List*
;   OUT: rax = 1 if empty, 0 if not
; ---------------------------------------------------------------------------
global list_empty
list_empty:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + List_count]
    test rax, rax
    jz .empty
    xor rax, rax
    leave
    ret
.empty:
    mov rax, 1
    leave
    ret

section .data

global list_version
list_version: dq 0x010000
