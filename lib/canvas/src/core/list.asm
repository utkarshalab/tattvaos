; ============================================================================
; Intrusive Doubly-Linked List
; O(1) insert/remove, no allocation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/struct_offsets.inc"

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
    mov qword [rdi + List.head], 0
    mov qword [rdi + List.tail], 0
    mov qword [rdi + List.count], 0
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

    mov rax, [rbx + List.tail]
    test rax, rax
    jz .empty

    mov [rax + ListNode.next], rsi
    mov [rsi + ListNode.prev], rax
    mov qword [rsi + ListNode.next], 0
    mov [rbx + List.tail], rsi
    inc qword [rbx + List.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.empty:
    mov [rbx + List.head], rsi
    mov [rbx + List.tail], rsi
    mov qword [rsi + ListNode.prev], 0
    mov qword [rsi + ListNode.next], 0
    mov qword [rbx + List.count], 1
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

    mov rax, [rbx + List.head]
    test rax, rax
    jz .empty

    mov [rax + ListNode.prev], rsi
    mov [rsi + ListNode.next], rax
    mov qword [rsi + ListNode.prev], 0
    mov [rbx + List.head], rsi
    inc qword [rbx + List.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.empty:
    mov [rbx + List.head], rsi
    mov [rbx + List.tail], rsi
    mov qword [rsi + ListNode.prev], 0
    mov qword [rsi + ListNode.next], 0
    mov qword [rbx + List.count], 1
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

    mov rax, [rsi + ListNode.prev]
    mov rcx, [rsi + ListNode.next]

    test rax, rax
    jz .head
    mov [rax + ListNode.next], rcx
    jmp .check_tail

.head:
    mov [rbx + List.head], rcx

.check_tail:
    test rcx, rcx
    jz .tail
    mov [rcx + ListNode.prev], rax
    jmp .done

.tail:
    mov [rbx + List.tail], rax

.done:
    dec qword [rbx + List.count]
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

    mov rax, [rbx + List.head]
    test rax, rax
    jz .empty

    mov rcx, [rax + ListNode.next]
    mov [rbx + List.head], rcx
    test rcx, rcx
    jz .was_last
    mov qword [rcx + ListNode.prev], 0
    jmp .done

.was_last:
    mov qword [rbx + List.tail], 0

.done:
    dec qword [rbx + List.count]
    mov qword [rax + ListNode.prev], 0
    mov qword [rax + ListNode.next], 0
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

    mov rax, [rbx + List.tail]
    test rax, rax
    jz .empty

    mov rcx, [rax + ListNode.prev]
    mov [rbx + List.tail], rcx
    test rcx, rcx
    jz .was_last
    mov qword [rcx + ListNode.next], 0
    jmp .done

.was_last:
    mov qword [rbx + List.head], 0

.done:
    dec qword [rbx + List.count]
    mov qword [rax + ListNode.prev], 0
    mov qword [rax + ListNode.next], 0
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
    mov rax, [rdi + List.count]
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
    mov rax, [rdi + List.count]
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
