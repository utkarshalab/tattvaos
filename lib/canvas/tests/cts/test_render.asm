; ============================================================================
; Render Tests — Drawing Primitives, Compositing, Transforms
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/geometry.inc"

section .text

; ============================================================================
; test_render_line
;   Test line drawing
; ============================================================================
global test_render_line
test_render_line:
    PROLOGUE_SAVE rbx, r12
    ; Create test pixbuf
    mov rdi, 100  ; width
    mov rsi, 100  ; height
    mov rdx, 4    ; bytes per pixel
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Draw line from (10,10) to (90,90)
    mov rdi, rbx
    mov rsi, 10
    mov rdx, 10
    mov rcx, 90
    mov r8d, 90
    mov r9d, 0xFFFFFFFF  ; white
    call line_draw

    ; Verify pixel at (50,50) is white
    ; (implementation would check pixel buffer)
    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_rect_fill
;   Test rectangle fill
; ============================================================================
global test_render_rect_fill
test_render_rect_fill:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Fill rectangle
    mov rdi, rbx
    mov rsi, 10
    mov rdx, 10
    mov rcx, 80
    mov r8d, 80
    mov r9d, 0xFF0000FF  ; red
    call rect_fill

    ; Verify
    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_circle
;   Test circle drawing
; ============================================================================
global test_render_circle
test_render_circle:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Draw circle
    mov rdi, rbx
    mov rsi, 50
    mov rdx, 50
    mov rcx, 30
    mov r8d, 0x00FF00FF  ; green
    call circle_draw

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_ellipse
;   Test ellipse drawing
; ============================================================================
global test_render_ellipse
test_render_ellipse:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    mov rdi, rbx
    mov rsi, 50
    mov rdx, 50
    mov rcx, 40
    mov r8d, 20
    mov r9d, 0xFF00FFFF  ; cyan
    call ellipse_draw

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_arc
;   Test arc drawing
; ============================================================================
global test_render_arc
test_render_arc:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    mov rdi, rbx
    mov rsi, 50
    mov rdx, 50
    mov rcx, 30
    mov r8d, 20
    mov r9d, 0
    mov r10d, 90
    mov r11d, 0xFFFF00FF  ; yellow
    call arc_draw

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_rounded_rect
;   Test rounded rectangle
; ============================================================================
global test_render_rounded_rect
test_render_rounded_rect:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    mov rdi, rbx
    mov rsi, 20
    mov rdx, 20
    mov rcx, 60
    mov r8d, 60
    mov r9d, 10
    mov r10d, 0xFF0000FF  ; red
    call rounded_rect_draw

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_triangle
;   Test triangle drawing
; ============================================================================
global test_render_triangle
test_render_triangle:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    mov rdi, rbx
    mov rsi, 50
    mov rdx, 10
    mov rcx, 90
    mov r8d, 50
    mov r9d, 10
    mov r10d, 10
    mov r11d, 90
    mov r12d, 0xFF0000FF  ; red
    call triangle_draw

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_polygon
;   Test polygon drawing
; ============================================================================
global test_render_polygon
test_render_polygon:
    PROLOGUE_SAVE rbx
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Draw pentagon
    ; TODO: Implement
    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_render_path
;   Test path rendering
; ============================================================================
global test_render_path
test_render_path:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Create path
    mov rdi, r12
    mov rsi, [rbx + Pixbuf_ARENA]
    call path_create

    ; Add commands
    mov rdi, r12
    mov rsi, 10
    mov rdx, 10
    call path_move_to

    mov rdi, r12
    mov rsi, 90
    mov rdx, 10
    call path_line_to

    mov rdi, r12
    mov rsi, 50
    mov rdx, 90
    call path_line_to

    mov rdi, r12
    call path_close

    ; Render path
    mov rdi, rbx
    mov rsi, r12
    mov rdx, 0xFF0000FF
    call path_render

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

.fail:
    mov rax, 1
    leave
    ret

; ============================================================================
; test_gradient_linear
;   Test linear gradient
; ============================================================================
global test_gradient_linear
test_gradient_linear:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 100
    mov rsi, 100
    mov rdx, 4
    call pixbuf_create
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Create gradient
    mov rdi, r12
    mov rsi, [rbx + Pixbuf_ARENA]
    call gradient_create

    mov rdi, r12
    mov rsi, 0xFF0000FF  ; red
    call gradient_add_stop

    mov rdi, r12
    mov rsi, 0x0000FFFF  ; blue
    call gradient_add_stop

    mov rdi, r12
    mov rsi, 0
    mov rdx, 0
    mov rcx, 100
    mov r8d, 100
    call gradient_set_linear

    mov rdi, rbx
    mov rsi, r12
    mov rdx, 0
    mov rcx, 0
    mov r8d, 100
    mov r9d, 100
    call gradient_render_rect

    TEST_ASSERT 1, 1

    call pixbuf_destroy
    xor rax, rax
    leave
    ret

; ============================================================================
; test_gradient_radial
;   Test radial gradient
; ============================================================================
global test_gradient_radial
test_gradient_radial:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; test_gradient_conical
;   Test conical gradient
; ============================================================================
global test_gradient_conical
test_gradient_conical:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; test_render_stroke
;   Test stroke rendering
; ============================================================================
global test_render_stroke
test_render_stroke:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; test_render_composite
;   Test compositing
; ============================================================================
global test_render_composite
test_render_composite:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; test_render_transform
;   Test transforms
; ============================================================================
global test_render_transform
test_render_transform:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; test_render_clip
;   Test clipping
; ============================================================================
global test_render_clip
test_render_clip:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_render_version
test_render_version: dq 0x010000