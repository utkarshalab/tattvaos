; ============================================================================
; Clip — Rectangle Clipping Operations
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

%define Rect_x1    0
%define Rect_y1    4
%define Rect_x2    8
%define Rect_y2    12

; ---------------------------------------------------------------------------
; clip_rect
;   Clip rectangle to bounds
;   IN:  rdi = rect*, rsi = clip_x1, rdx = clip_y1, rcx = clip_x2, r8 = clip_y2
;   OUT: rax = 0 OK, rect modified in place
; ---------------------------------------------------------------------------
global clip_rect
clip_rect:
    PROLOGUE
    ASSERT_PTR rdi

    mov eax, [rdi + Rect_x1]
    cmp eax, esi
    cmovl eax, esi
    mov [rdi + Rect_x1], eax

    mov eax, [rdi + Rect_y1]
    cmp eax, edx
    cmovl eax, edx
    mov [rdi + Rect_y1], eax

    mov eax, [rdi + Rect_x2]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rdi + Rect_x2], eax

    mov eax, [rdi + Rect_y2]
    cmp eax, r8d
    cmovg eax, r8d
    mov [rdi + Rect_y2], eax

    ; Normalize empty
    mov eax, [rdi + Rect_x1]
    cmp eax, [rdi + Rect_x2]
    jl .ok
    mov [rdi + Rect_x2], eax
    mov eax, [rdi + Rect_y1]
    mov [rdi + Rect_y2], eax
.ok:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; clip_rect_intersect
;   Intersect two rectangles, result in rdi
;   IN:  rdi = dest rect*, rsi = src1 rect*, rdx = src2 rect*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global clip_rect_intersect
clip_rect_intersect:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rdx

    mov eax, [rsi + Rect_x1]
    cmp eax, [rdx + Rect_x1]
    cmovl eax, [rdx + Rect_x1]
    mov [rdi + Rect_x1], eax

    mov eax, [rsi + Rect_y1]
    cmp eax, [rdx + Rect_y1]
    cmovl eax, [rdx + Rect_y1]
    mov [rdi + Rect_y1], eax

    mov eax, [rsi + Rect_x2]
    cmp eax, [rdx + Rect_x2]
    cmovg eax, [rdx + Rect_x2]
    mov [rdi + Rect_x2], eax

    mov eax, [rsi + Rect_y2]
    cmp eax, [rdx + Rect_y2]
    cmovg eax, [rdx + Rect_y2]
    mov [rdi + Rect_y2], eax

    ; Normalize
    mov eax, [rdi + Rect_x1]
    cmp eax, [rdi + Rect_x2]
    jl .ok
    mov [rdi + Rect_x2], eax
    mov eax, [rdi + Rect_y1]
    mov [rdi + Rect_y2], eax
.ok:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; clip_point_in_rect
;   Check if point is inside rectangle
;   IN:  rdi = rect*, rsi = x, rdx = y
;   OUT: rax = 1 if inside, 0 if outside
; ---------------------------------------------------------------------------
global clip_point_in_rect
clip_point_in_rect:
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

section .data

global clip_version
clip_version: dq 0x010000