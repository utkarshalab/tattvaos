; ============================================================================
; Rectangle — Integer Rectangle Operations
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

%define Rect_x1    0
%define Rect_y1    4
%define Rect_x2    8
%define Rect_y2    12
%define Rect_size  16

; ---------------------------------------------------------------------------
; rect_init
;   Initialize rectangle
;   IN:  rdi = Rect*, rsi = x1, rdx = y1, rcx = x2, r8 = y2
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global rect_init
rect_init:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Rect_x1], esi
    mov [rdi + Rect_y1], edx
    mov [rdi + Rect_x2], ecx
    mov [rdi + Rect_y2], r8d
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; rect_empty
;   Check if rectangle is empty
;   IN:  rdi = Rect*
;   OUT: rax = 1 if empty, 0 if not
; ---------------------------------------------------------------------------
global rect_empty
rect_empty:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Rect_x1]
    cmp eax, [rdi + Rect_x2]
    jae .empty
    mov eax, [rdi + Rect_y1]
    cmp eax, [rdi + Rect_y2]
    jae .empty
    xor rax, rax
    ret
.empty:
    mov rax, 1
    ret

; ---------------------------------------------------------------------------
; rect_width
;   Get rectangle width
;   IN:  rdi = Rect*
;   OUT: rax = width
; ---------------------------------------------------------------------------
global rect_width
rect_width:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Rect_x2]
    sub eax, [rdi + Rect_x1]
    ret

; ---------------------------------------------------------------------------
; rect_height
;   Get rectangle height
;   IN:  rdi = Rect*
;   OUT: rax = height
; ---------------------------------------------------------------------------
global rect_height
rect_height:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Rect_y2]
    sub eax, [rdi + Rect_y1]
    ret

; ---------------------------------------------------------------------------
; rect_area
;   Get rectangle area
;   IN:  rdi = Rect*
;   OUT: rax = area
; ---------------------------------------------------------------------------
global rect_area
rect_area:
    PROLOGUE
    ASSERT_PTR rdi
    call rect_width
    mov rdx, rax
    call rect_height
    imul rax, rdx
    ret

; ---------------------------------------------------------------------------
; rect_contains_point
;   Check if point is inside rectangle
;   IN:  rdi = Rect*, rsi = x, rdx = y
;   OUT: rax = 1 if inside, 0 if outside
; ---------------------------------------------------------------------------
global rect_contains_point
rect_contains_point:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Rect_x1]
    cmp esi, eax
    jl .outside
    mov eax, [rdi + Rect_x2]
    cmp esi, eax
    jge .outside
    mov eax, [rdi + Rect_y1]
    cmp edx, eax
    jl .outside
    mov eax, [rdi + Rect_y2]
    cmp edx, eax
    jge .outside
    mov rax, 1
    ret
.outside:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; rect_intersect
;   Compute intersection of two rectangles
;   IN:  rdi = dest Rect*, rsi = src1 Rect*, rdx = src2 Rect*
;   OUT: rax = 0 OK, dest = intersection (may be empty)
; ---------------------------------------------------------------------------
global rect_intersect
rect_intersect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR rdx

    ; x1 = max(src1.x1, src2.x1)
    mov eax, [r12 + Rect_x1]
    cmp eax, [rdx + Rect_x1]
    cmovl eax, [rdx + Rect_x1]
    mov [rbx + Rect_x1], eax

    ; y1 = max(src1.y1, src2.y1)
    mov eax, [r12 + Rect_y1]
    cmp eax, [rdx + Rect_y1]
    cmovl eax, [rdx + Rect_y1]
    mov [rbx + Rect_y1], eax

    ; x2 = min(src1.x2, src2.x2)
    mov eax, [r12 + Rect_x2]
    cmp eax, [rdx + Rect_x2]
    cmovg eax, [rdx + Rect_x2]
    mov [rbx + Rect_x2], eax

    ; y2 = min(src1.y2, src2.y2)
    mov eax, [r12 + Rect_y2]
    cmp eax, [rdx + Rect_y2]
    cmovg eax, [rdx + Rect_y2]
    mov [rbx + Rect_y2], eax

    ; Normalize empty
    mov eax, [rbx + Rect_x1]
    cmp eax, [rbx + Rect_x2]
    jl .ok
    mov [rbx + Rect_x2], eax
    mov [rbx + Rect_y2], eax
.ok:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; rect_union
;   Compute union of two rectangles
;   IN:  rdi = dest Rect*, rsi = src1 Rect*, rdx = src2 Rect*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global rect_union
rect_union:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR rdx

    ; x1 = min(src1.x1, src2.x1)
    mov eax, [r12 + Rect_x1]
    cmp eax, [rdx + Rect_x1]
    cmovg eax, [rdx + Rect_x1]
    mov [rbx + Rect_x1], eax

    ; y1 = min(src1.y1, src2.y1)
    mov eax, [r12 + Rect_y1]
    cmp eax, [rdx + Rect_y1]
    cmovg eax, [rdx + Rect_y1]
    mov [rbx + Rect_y1], eax

    ; x2 = max(src1.x2, src2.x2)
    mov eax, [r12 + Rect_x2]
    cmp eax, [rdx + Rect_x2]
    cmovl eax, [rdx + Rect_x2]
    mov [rbx + Rect_x2], eax

    ; y2 = max(src1.y2, src2.y2)
    mov eax, [r12 + Rect_y2]
    cmp eax, [rdx + Rect_y2]
    cmovl eax, [rdx + Rect_y2]
    mov [rbx + Rect_y2], eax

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; rect_translate
;   Translate rectangle by (dx, dy)
;   IN:  rdi = Rect*, rsi = dx, rdx = dy
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global rect_translate
rect_translate:
    PROLOGUE
    ASSERT_PTR rdi
    add dword [rdi + Rect_x1], esi
    add dword [rdi + Rect_x2], esi
    add dword [rdi + Rect_y1], edx
    add dword [rdi + Rect_y2], edx
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; rect_equals
;   Check if two rectangles are equal
;   IN:  rdi = Rect*, rsi = Rect*
;   OUT: rax = 1 if equal, 0 if not
; ---------------------------------------------------------------------------
global rect_equals
rect_equals:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov eax, [rdi + Rect_x1]
    cmp eax, [rsi + Rect_x1]
    jne .diff
    mov eax, [rdi + Rect_y1]
    cmp eax, [rsi + Rect_y1]
    jne .diff
    mov eax, [rdi + Rect_x2]
    cmp eax, [rsi + Rect_x2]
    jne .diff
    mov eax, [rdi + Rect_y2]
    cmp eax, [rsi + Rect_y2]
    jne .diff
    mov rax, 1
    ret
.diff:
    xor rax, rax
    ret

section .data

global rect_version
rect_version: dq 0x010000