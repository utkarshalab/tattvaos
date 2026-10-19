; ============================================================================
; Rectangle Operations — Intersection, Union, Containment, Translation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; Rect structure (in registers or memory):
;   x, y, w, h (each 32-bit)

; ---------------------------------------------------------------------------
; rect_init
;   Initialize rectangle
;   IN:  rdi = rect*, rsi = x, rdx = y, rcx = w, r8 = h
; ---------------------------------------------------------------------------
global rect_init
rect_init:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + 0], esi
    mov [rdi + 4], edx
    mov [rdi + 8], ecx
    mov [rdi + 12], r8d
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rect_is_empty
;   Check if rectangle has zero area
;   IN:  rdi = rect*
;   OUT: rax = 1 if empty, 0 if not
; ---------------------------------------------------------------------------
global rect_is_empty
rect_is_empty:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + 8]
    test eax, eax
    jle .empty
    mov eax, [rdi + 12]
    test eax, eax
    jle .empty
    xor rax, rax
    leave
    ret
.empty:
    mov rax, 1
    leave
    ret

; ---------------------------------------------------------------------------
; rect_intersect
;   Compute intersection of two rectangles
;   IN:  rdi = dest*, rsi = rect1*, rdx = rect2*
;   OUT: rax = 0 OK, 1 if no intersection (dest set to empty)
; ---------------------------------------------------------------------------
global rect_intersect
rect_intersect:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    ; max(x1, x2)
    mov eax, [r12 + 0]
    mov ecx, [r13 + 0]
    cmp eax, ecx
    cmovl eax, ecx
    mov [rbx + 0], eax
    
    ; max(y1, y2)
    mov eax, [r12 + 4]
    mov ecx, [r13 + 4]
    cmp eax, ecx
    cmovl eax, ecx
    mov [rbx + 4], eax
    
    ; min(x1+w1, x2+w2) - max(x1, x2)
    mov eax, [r12 + 0]
    add eax, [r12 + 8]
    mov ecx, [r13 + 0]
    add ecx, [r13 + 8]
    cmp eax, ecx
    cmovg eax, ecx
    sub eax, [rbx + 0]
    mov [rbx + 8], eax
    jle .empty
    
    ; min(y1+h1, y2+h2) - max(y1, y2)
    mov eax, [r12 + 4]
    add eax, [r12 + 12]
    mov ecx, [r13 + 4]
    add ecx, [r13 + 12]
    cmp eax, ecx
    cmovg eax, ecx
    sub eax, [rbx + 4]
    mov [rbx + 12], eax
    jle .empty
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
    
.empty:
    mov dword [rbx + 8], 0
    mov dword [rbx + 12], 0
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; rect_union
;   Compute union (bounding box) of two rectangles
;   IN:  rdi = dest*, rsi = rect1*, rdx = rect2*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global rect_union
rect_union:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    ; min(x1, x2)
    mov eax, [r12 + 0]
    mov ecx, [r13 + 0]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rbx + 0], eax
    
    ; min(y1, y2)
    mov eax, [r12 + 4]
    mov ecx, [r13 + 4]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rbx + 4], eax
    
    ; max(x1+w1, x2+w2) - min(x1, x2)
    mov eax, [r12 + 0]
    add eax, [r12 + 8]
    mov ecx, [r13 + 0]
    add ecx, [r13 + 8]
    cmp eax, ecx
    cmovl eax, ecx
    sub eax, [rbx + 0]
    mov [rbx + 8], eax
    
    ; max(y1+h1, y2+h2) - min(y1, y2)
    mov eax, [r12 + 4]
    add eax, [r12 + 12]
    mov ecx, [r13 + 4]
    add ecx, [r13 + 12]
    cmp eax, ecx
    cmovl eax, ecx
    sub eax, [rbx + 4]
    mov [rbx + 12], eax
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; rect_contains_point
;   Check if point is inside rectangle (inclusive)
;   IN:  rdi = rect*, rsi = x, rdx = y
;   OUT: rax = 1 if inside, 0 if outside
; ---------------------------------------------------------------------------
global rect_contains_point
rect_contains_point:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + 0]
    cmp esi, eax
    jl .outside
    mov eax, [rdi + 8]
    add eax, [rdi + 0]
    cmp esi, eax
    jge .outside
    mov eax, [rdi + 4]
    cmp edx, eax
    jl .outside
    mov eax, [rdi + 12]
    add eax, [rdi + 4]
    cmp edx, eax
    jge .outside
    mov rax, 1
    leave
    ret
.outside:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rect_contains_rect
;   Check if rect1 fully contains rect2
;   IN:  rdi = rect1*, rsi = rect2*
;   OUT: rax = 1 if contains, 0 if not
; ---------------------------------------------------------------------------
global rect_contains_rect
rect_contains_rect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov eax, [r12 + 0]
    cmp eax, [rbx + 0]
    jl .outside
    mov eax, [r12 + 4]
    cmp eax, [rbx + 4]
    jl .outside
    mov eax, [r12 + 0]
    add eax, [r12 + 8]
    mov ecx, [rbx + 0]
    add ecx, [rbx + 8]
    cmp eax, ecx
    jg .outside
    mov eax, [r12 + 4]
    add eax, [r12 + 12]
    mov ecx, [rbx + 4]
    add ecx, [rbx + 12]
    cmp eax, ecx
    jg .outside
    
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret
.outside:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rect_translate
;   Translate rectangle by (dx, dy)
;   IN:  rdi = rect*, rsi = dx, rdx = dy
; ---------------------------------------------------------------------------
global rect_translate
rect_translate:
    PROLOGUE
    ASSERT_PTR rdi
    add [rdi + 0], esi
    add [rdi + 4], edx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rect_clamp
;   Clamp rectangle to bounds
;   IN:  rdi = rect*, rsi = bounds*
; ---------------------------------------------------------------------------
global rect_clamp
rect_clamp:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; x >= bounds.x
    mov eax, [rbx + 0]
    cmp eax, [r12 + 0]
    cmovl eax, [r12 + 0]
    mov [rbx + 0], eax
    
    ; y >= bounds.y
    mov eax, [rbx + 4]
    cmp eax, [r12 + 4]
    cmovl eax, [r12 + 4]
    mov [rbx + 4], eax
    
    ; x+w <= bounds.x+bounds.w
    mov eax, [rbx + 0]
    add eax, [rbx + 8]
    mov ecx, [r12 + 0]
    add ecx, [r12 + 8]
    cmp eax, ecx
    cmovg eax, ecx
    sub eax, [rbx + 0]
    mov [rbx + 8], eax
    jle .empty
    
    ; y+h <= bounds.y+bounds.h
    mov eax, [rbx + 4]
    add eax, [rbx + 12]
    mov ecx, [r12 + 4]
    add ecx, [r12 + 12]
    cmp eax, ecx
    cmovg eax, ecx
    sub eax, [rbx + 4]
    mov [rbx + 12], eax
    jle .empty
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.empty:
    mov dword [rbx + 8], 0
    mov dword [rbx + 12], 0
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global rect_version
rect_version: dq 0x010000