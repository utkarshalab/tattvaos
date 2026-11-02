; ============================================================================
; Unit Test — Field Access Regressions and the Linear Framebuffer
; ============================================================================
; test_fields_suite -> eax = failed cases (each case returns 0 / 1).
; Code that once read or wrote past a field: sensor white balance, the cursor
; position, the decoration hit test (which also lost its coordinates), the
; pointer confine rectangle. And fb_linear, whose real framebuffer has longer
; rows than the output: frames arrive in it, only damage is copied, and the
; bytes past each row stay untouched.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/backend.inc"
%include "inc/shell.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern compositor_init
extern compositor_composite
extern constraints_apply
extern constraints_confine
extern decoration_hit_test
extern fb_linear_create_output
extern fb_linear_init
extern region_add_rect
extern server_init
extern server_poll
extern surface_set_cursor

%define HEAP_SIZE (1024 * 1024)
%define FB_W 16
%define FB_H 8
%define FB_STRIDE 128                   ; longer than the 64 of its pixels
%define POISON 0x5A5A5A5A
%define BG 0xFF202030

section .text

global test_fields_suite
global test_fields_main
test_fields_suite:
test_fields_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tf_cursor_keeps_neighbour
    CASE tf_hit_test
    CASE tf_confine
    CASE tf_fb_refused
    CASE tf_fb_frame
    CASE tf_fb_only_damage
    CASE tf_server_on_fb
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; surface_set_cursor stores two i32s: Pointer.buttons, next to them, survives
tf_cursor_keeps_neighbour:
    sub rsp, 8
    mov dword [rel pointer + Pointer.buttons], 0x1234
    lea rdi, [rel pointer]
    mov rsi, -1
    mov rdx, -1
    call surface_set_cursor
    cmp dword [rel pointer + Pointer.buttons], 0x1234
    jne .fail
    cmp dword [rel pointer + Pointer.y], -1
    jne .fail
    PASS

; a 100x80 decoration: titlebar 20, border 4, one button at (70, 2) 16x16
%macro HIT 3                            ; x, y -> expected
    lea rdi, [rel decoration]
    mov esi, %1
    mov edx, %2
    call decoration_hit_test
    cmp rax, %3
    jne .fail
%endmacro

tf_hit_test:
    sub rsp, 8
    lea rax, [rel toplevel]
    mov [rel decoration + Decoration.toplevel], rax
    mov dword [rel toplevel + Toplevel.width], 100
    mov dword [rel toplevel + Toplevel.height], 80
    mov dword [rel decoration + Decoration.titlebar_h], 20
    mov dword [rel decoration + Decoration.border_w], 4
    lea rax, [rel button]
    mov [rel decoration + Decoration.buttons], rax
    mov dword [rel decoration + Decoration.button_count], 1
    mov dword [rel button + DECOR_BTN_RECT], 70
    mov dword [rel button + DECOR_BTN_RECT + 4], 2
    mov dword [rel button + DECOR_BTN_RECT + 8], 16
    mov dword [rel button + DECOR_BTN_RECT + 12], 16
    mov byte [rel button + DECOR_BTN_TYPE], 7
    mov qword [rel button + DECOR_BTN_NEXT], 0
    HIT 75, 5, 7                        ; the button
    HIT 20, 5, 100                      ; titlebar
    HIT 69, 5, 100                      ; just left of the button
    HIT 2, 40, 200                      ; left border
    HIT 98, 40, 201                     ; right
    HIT 50, 22, 202                     ; top, under the titlebar
    HIT 50, 78, 203                     ; bottom
    HIT 50, 40, 0                       ; client area
    PASS

; a pointer past the confine rectangle comes back to it
tf_confine:
    sub rsp, 8
    mov dword [rel corners], 10
    mov dword [rel corners + 4], 20
    mov dword [rel corners + 8], 30
    mov dword [rel corners + 12], 40
    lea rdi, [rel constraints]
    lea rsi, [rel corners]
    call constraints_confine
    mov dword [rel px], 50
    mov dword [rel py], 5
    lea rdi, [rel constraints]
    lea rsi, [rel px]
    lea rdx, [rel py]
    call constraints_apply
    cmp dword [rel px], 30
    jne .fail
    cmp dword [rel py], 20
    jne .fail
    PASS

; a server with a fake framebuffer, every byte of it poisoned
fb_server:
    sub rsp, 8
    lea rdi, [rel hw]
    mov eax, POISON
    mov ecx, FB_STRIDE * FB_H / 4
    rep stosd
    lea rdi, [rel server]
    xor eax, eax
    mov ecx, Server_size
    rep stosb
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rax, [rel arena]
    mov [rel server + Server.arena], rax
    mov [rel backend + Backend.arena], rax
    lea rax, [rel server]
    mov [rel backend + Backend.server], rax
    lea rax, [rel backend]
    mov [rel server + Server.backend], rax
    lea rax, [rel hw]
    mov [rel config + Config.fb_base], rax
    mov dword [rel config + Config.fb_width], FB_W
    mov dword [rel config + Config.fb_height], FB_H
    mov dword [rel config + Config.fb_stride], FB_STRIDE
    lea rdi, [rel backend]
    lea rsi, [rel config]
    call fb_linear_init
    test rax, rax
    jnz .out
    lea rdi, [rel backend]
    call fb_linear_create_output
    mov [rel output], rax
    lea rdi, [rel compositor]
    xor eax, eax
    mov ecx, Compositor_size
    rep stosb
    lea rdi, [rel compositor]
    lea rsi, [rel server]
    lea rdx, [rel arena]
    call compositor_init
.out:
    add rsp, 8
    ret

; framebuffer pixel (%1, %2) equals %3 -> jump .fail if not
%macro HW_IS 3
    cmp dword [rel hw + (%2) * FB_STRIDE + (%1) * 4], %3
    jne .fail
%endmacro

tf_fb_refused:
    sub rsp, 8
    call fb_server
    mov dword [rel config + Config.fb_stride], FB_W * 4 - 1
    lea rdi, [rel backend]
    lea rsi, [rel config]
    call fb_linear_init
    cmp rax, -(EINVAL)
    jne .fail
    PASS

tf_fb_frame:
    sub rsp, 8
    call fb_server
    test rax, rax
    jnz .fail
    lea rdi, [rel compositor]
    call compositor_composite
    test rax, rax
    jnz .fail
    HW_IS 0, 0, BG
    HW_IS FB_W - 1, 0, BG
    HW_IS 0, FB_H - 1, BG
    HW_IS FB_W - 1, FB_H - 1, BG
    HW_IS FB_W, 0, POISON               ; past the row: untouched
    HW_IS FB_W, FB_H - 1, POISON
    PASS

; started with a framebuffer, the server draws on it in its first turn
tf_server_on_fb:
    sub rsp, 8
    call fb_server
    lea rdi, [rel hw]
    mov eax, POISON
    mov ecx, FB_STRIDE * FB_H / 4
    rep stosd
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    xor edx, edx
    xor ecx, ecx
    lea r8, [rel config]
    call server_init
    test rax, rax
    jnz .fail
    lea rdi, [rel server]
    call server_poll
    test rax, rax
    jnz .fail
    HW_IS 0, 0, BG
    HW_IS FB_W - 1, FB_H - 1, BG
    HW_IS FB_W, 0, POISON
    PASS

tf_fb_only_damage:
    sub rsp, 8
    call fb_server
    lea rdi, [rel compositor]
    call compositor_composite
    lea rdi, [rel hw]                   ; poison the screen, then damage a little
    mov eax, POISON
    mov ecx, FB_STRIDE * FB_H / 4
    rep stosd
    mov dword [rel rect], 2
    mov dword [rel rect + 4], 1
    mov dword [rel rect + 8], 3
    mov dword [rel rect + 12], 2
    mov rax, [rel output]
    mov rdi, [rax + Output.damage]
    lea rsi, [rel rect]
    call region_add_rect
    lea rdi, [rel compositor]
    call compositor_composite
    HW_IS 2, 1, BG
    HW_IS 4, 2, BG
    HW_IS 1, 1, POISON                  ; beside it
    HW_IS 5, 1, POISON
    HW_IS 2, 0, POISON                  ; above and below
    HW_IS 2, 3, POISON
    PASS

section .bss
alignb 16
pointer:        resb Pointer_size
decoration:     resb Decoration_size
toplevel:       resb Toplevel_size
button:         resb 64
constraints:    resb 64
corners:        resd 4
px:             resd 1
py:             resd 1
rect:           resd 4
server:         resb Server_size
backend:        resb Backend_size
config:         resb Config_size
compositor:     resb Compositor_size
arena:          resb Arena_size
output:         resq 1
alignb 16
hw:             resb FB_STRIDE * FB_H
alignb 16
heap:           resb HEAP_SIZE
