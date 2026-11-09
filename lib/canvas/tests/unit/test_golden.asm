; ============================================================================
; Golden Frames — the Whole Path, Client Buffer to Framebuffer
; ============================================================================
; test_golden_suite -> eax = failed cases (each case returns 0 / 1).
; A client with two surfaces on a 64x48 headless output: A, 32x24 opaque at
; (8, 8), and over it B, 16x16 half-transparent at (24, 16). Frames are checked
; by Adler-32 of the framebuffer against values computed outside this code
; from the same scene (tests/golden/make_golden.py, a model of the
; compositor written apart from it, into tests/golden/expected/golden.inc),
; and by chosen pixels. More scenes: translucent surfaces stacked, an
; opaque BGRX buffer copied under a translucent one, surfaces over every
; edge and corner. Also: no damage means no frame,
; only damaged pixels change, frame callbacks wait for the frame, surfaces
; hanging over the output's edge clip, and leaving uncovers the background.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern adler32
extern arena_init
extern handle_resolve
extern client_init
extern client_accept
extern client_get
extern client_disconnect
extern presentation_init
extern surface_init
extern surface_create
extern surface_destroy
extern surface_damage
extern surface_frame_callback
extern buffer_init
extern buffer_create
extern buffer_attach
extern commit_surface
extern headless_init
extern headless_create_virtual_output
extern compositor_init
extern compositor_composite
extern compositor_add_surface

%define HEAP_SIZE (1024 * 1024)
%define W 64
%define H 48
%define BG 0xFF202030
%define B_PIXEL 0x80004000

%include "tests/golden/expected/golden.inc"
%define GOLDEN_PARTIAL 0x60A7DBB0

section .text

global test_golden_suite
global test_golden_main
test_golden_suite:
test_golden_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tg_first_frame
    CASE tg_pixels
    CASE tg_no_damage_no_frame
    CASE tg_only_damage_changes
    CASE tg_frame_callback
    CASE tg_surface_removed
    CASE tg_edge
    CASE tg_client_leaves
    CASE tg_stack
    CASE tg_opaque
    CASE tg_edges
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

; a server, a headless output and a client
fresh:
    sub rsp, 8
    lea rdi, [rel server]
    xor eax, eax
    mov ecx, Server_size
    rep stosb
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call client_init
    call presentation_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call surface_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call buffer_init
    lea rax, [rel arena]
    mov [rel backend + Backend.arena], rax
    lea rax, [rel server]
    mov [rel backend + Backend.server], rax
    lea rax, [rel backend]
    mov [rel server + Server.backend], rax
    lea rdi, [rel backend]
    lea rsi, [rel config]
    call headless_init
    lea rdi, [rel backend]
    mov esi, W
    mov edx, H
    mov ecx, DRM_FORMAT_BGRA8888
    call headless_create_virtual_output
    mov [rel output], rax
    lea rdi, [rel compositor]
    lea rsi, [rel server]
    lea rdx, [rel arena]
    call compositor_init
    lea rdi, [rel server]
    lea rsi, [rel pair]
    xor edx, edx
    call client_accept
    mov [rel client_id], rax
    lea rdi, [rel server]
    mov rsi, rax
    call client_get
    mov [rel client], rax
    add rsp, 8
    ret

; A surface w x h at (x, y) on the output, wholly damaged, not yet committed.
; IN: edi = w, esi = h, edx = x, ecx = y
; OUT: rax = surface*, rdx = pixels, r8 = surface handle
add_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov [rel params], edi
    mov [rel params + 4], esi
    mov eax, [rel surface_format]       ; BGRA unless a scene says
    test eax, eax
    jnz .format
    mov eax, DRM_FORMAT_BGRA8888
.format:
    mov [rel params + 8], eax
    lea rdi, [rel server]
    mov rsi, [rel client]
    lea rdx, [rel params]
    xor ecx, ecx
    call buffer_create
    mov [rsp], rax                      ; buffer handle
    lea rdi, [rel server]
    mov rsi, [rel client]
    xor edx, edx
    call surface_create
    mov [rel last_handle], rax
    mov rdi, [rel server + Server.surface_table]
    mov rsi, rax
    call handle_resolve
    mov rbx, rax
    lea rdi, [rel server]
    mov rsi, rbx
    mov rdx, [rsp]
    mov ecx, r14d
    mov r8d, r15d
    call buffer_attach
    lea rdi, [rel server]
    mov rsi, rbx
    xor edx, edx
    xor ecx, ecx
    mov r8d, r12d
    mov r9d, r13d
    call surface_damage
    mov rdi, [rel output]
    mov rsi, rbx
    call compositor_add_surface
    mov rdi, [rel server + Server.buffer_table]
    mov rsi, [rsp]
    call handle_resolve
    mov rdx, [rax + Buffer.base]
    mov rax, rbx
    mov r8, [rel last_handle]
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

%macro COMMIT 1
    lea rdi, [rel server]
    mov rsi, %1
    xor edx, edx
    call commit_surface
%endmacro
%macro COMPOSITE 0
    lea rdi, [rel compositor]
    call compositor_composite
%endmacro

; the scene: A in [surf_a] / [pix_a], B in [surf_b]; committed, not composited
scene:
    sub rsp, 8
    mov edi, 32
    mov esi, 24
    mov edx, 8
    mov ecx, 8
    call add_surface
    mov [rel surf_a], rax
    mov [rel pix_a], rdx
    mov rdi, rdx
    xor ecx, ecx                        ; y
.row:
    xor edx, edx                        ; x
.pixel:
    lea eax, [rcx * 8]                  ; 0xFF, x * 4, y * 8, 0x10
    and eax, 255
    shl eax, 8
    or eax, 0xFF000010
    lea r8d, [rdx * 4]
    and r8d, 255
    shl r8d, 16
    or eax, r8d
    mov [rdi], eax
    add rdi, 4
    inc edx
    cmp edx, 32
    jb .pixel
    inc ecx
    cmp ecx, 24
    jb .row
    mov edi, 16
    mov esi, 16
    mov edx, 24
    mov ecx, 16
    call add_surface
    mov [rel surf_b], rax
    mov [rel handle_b], r8
    mov rdi, rdx
    mov eax, B_PIXEL
    mov ecx, 16 * 16
    rep stosd
    COMMIT [rel surf_a]
    COMMIT [rel surf_b]
    add rsp, 8
    ret

; Adler-32 of the framebuffer -> rax
checksum:
    sub rsp, 8
    mov rax, [rel output]
    mov rdi, [rax + Output.framebuffer]
    mov esi, W * H * 4
    mov edx, 1
    call adler32
    add rsp, 8
    ret

; framebuffer pixel (%1, %2) equals %3 -> jump .fail if not
%macro PIXEL_IS 3
    mov rax, [rel output]
    mov rax, [rax + Output.framebuffer]
    cmp dword [rax + ((%2) * W + (%1)) * 4], %3
    jne .fail
%endmacro

tg_first_frame:
    sub rsp, 8
    call scene
    COMPOSITE
    test rax, rax
    jnz .fail
    cmp qword [rel compositor + Compositor.frame_seq], 1
    jne .fail
    call checksum
    cmp eax, GOLDEN_FIRST
    jne .fail
    PASS

tg_pixels:
    sub rsp, 8
    call scene
    COMPOSITE
    PIXEL_IS 0, 0, BG
    PIXEL_IS 7, 8, BG
    PIXEL_IS 8, 8, 0xFF000010           ; A's corner
    PIXEL_IS 23, 31, 0xFF3CB810         ; A's last row, uncovered
    PIXEL_IS 39, 31, 0xFF3E9C08         ; A's far corner, under B
    PIXEL_IS 40, 31, BG
    PIXEL_IS 24, 16, 0xFF206008         ; B over A
    PIXEL_IS 30, 20, 0xFF2C7008
    PASS

tg_no_damage_no_frame:
    sub rsp, 8
    call scene
    COMPOSITE
    COMPOSITE
    cmp qword [rel compositor + Compositor.frame_seq], 1
    jne .fail
    PASS

tg_only_damage_changes:
    sub rsp, 8
    call scene
    COMPOSITE
    mov rdi, [rel pix_a]
    mov eax, 0xFFFFFFFF
    xor ecx, ecx
.row:
    mov [rdi], eax                      ; a white 4x4
    mov [rdi + 4], eax
    mov [rdi + 8], eax
    mov [rdi + 12], eax
    add rdi, 32 * 4
    inc ecx
    cmp ecx, 4
    jb .row
    mov rdi, [rel pix_a]                ; changed, but never damaged
    mov dword [rdi + (20 * 32 + 20) * 4], 0xFF0000FF
    lea rdi, [rel server]
    mov rsi, [rel surf_a]
    xor edx, edx
    xor ecx, ecx
    mov r8d, 4
    mov r9d, 4
    call surface_damage
    COMMIT [rel surf_a]
    COMPOSITE
    cmp qword [rel compositor + Compositor.frame_seq], 2
    jne .fail
    call checksum
    cmp eax, GOLDEN_PARTIAL
    jne .fail
    PASS

frame_cb:
    inc qword [rel cb_count]
    ret

tg_frame_callback:
    sub rsp, 8
    call scene
    COMPOSITE
    mov qword [rel cb_count], 0
    lea rdi, [rel server]
    mov rsi, [rel surf_a]
    lea rdx, [rel frame_cb]
    xor ecx, ecx
    call surface_frame_callback
    lea rdi, [rel server]
    mov rsi, [rel surf_a]
    xor edx, edx
    xor ecx, ecx
    mov r8d, 1
    mov r9d, 1
    call surface_damage
    COMMIT [rel surf_a]
    cmp qword [rel cb_count], 0
    jne .fail                           ; the commit is not the frame
    COMPOSITE
    cmp qword [rel cb_count], 1
    jne .fail
    COMPOSITE                           ; no frame, nothing fires again
    cmp qword [rel cb_count], 1
    jne .fail
    PASS

tg_surface_removed:
    sub rsp, 8
    call scene
    COMPOSITE
    lea rdi, [rel server]
    mov rsi, [rel handle_b]
    call surface_destroy
    test rax, rax
    jnz .fail
    COMPOSITE
    PIXEL_IS 30, 20, 0xFF586010         ; A again: x 22 * 4, y 12 * 8
    PASS

tg_edge:
    sub rsp, 8
    mov edi, 8
    mov esi, 8
    mov edx, -4                         ; hangs off the top left
    mov ecx, -4
    call add_surface
    mov [rel surf_a], rax
    mov rdi, rdx
    mov eax, 0xFF112233
    mov ecx, 8 * 8
    rep stosd
    COMMIT [rel surf_a]
    mov edi, 8
    mov esi, 8
    mov edx, W - 4                      ; and off the bottom right
    mov ecx, H - 4
    call add_surface
    mov [rel surf_b], rax
    mov rdi, rdx
    mov eax, 0xFF445566
    mov ecx, 8 * 8
    rep stosd
    COMMIT [rel surf_b]
    COMPOSITE
    test rax, rax
    jnz .fail
    PIXEL_IS 0, 0, 0xFF112233
    PIXEL_IS 3, 3, 0xFF112233
    PIXEL_IS 4, 4, BG
    PIXEL_IS W - 4, H - 4, 0xFF445566
    PIXEL_IS W - 1, H - 1, 0xFF445566
    PIXEL_IS W - 5, H - 4, BG
    PASS

; A solid w x h surface at x, y, committed.
; edi = w, esi = h, edx = x, ecx = y, r8d = colour
solid:
    push rbx
    push r12
    push r13
    mov ebx, edi
    imul ebx, esi                       ; its pixels
    mov r12d, r8d
    call add_surface
    mov r13, rax
    mov rdi, rdx
    mov eax, r12d
    mov ecx, ebx
    rep stosd
    COMMIT r13
    pop r13
    pop r12
    pop rbx
    ret

; edi = w, esi = h, edx = x, ecx = y: a surface of scene A's gradient
; (0xFF, x * 4, y * 8, 0x10) in surface_format, committed
gradient_surface:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    call add_surface
    mov r13, rax
    mov rdi, rdx
    xor ecx, ecx                        ; y
.row:
    xor edx, edx                        ; x
.pixel:
    lea eax, [rcx * 8]
    and eax, 255
    shl eax, 8
    or eax, 0xFF000010
    lea r8d, [rdx * 4]
    and r8d, 255
    shl r8d, 16
    or eax, r8d
    mov [rdi], eax
    add rdi, 4
    inc edx
    cmp edx, ebx
    jb .pixel
    inc ecx
    cmp ecx, r12d
    jb .row
    COMMIT r13
    pop r13
    pop r12
    pop rbx
    ret

%macro SOLID 5                          ; w, h, x, y, colour
    mov edi, %1
    mov esi, %2
    mov edx, %3
    mov ecx, %4
    mov r8d, %5
    call solid
%endmacro

; Three translucent rectangles stacked, each over the last
tg_stack:
    sub rsp, 8
    SOLID 20, 20, 4, 4, 0x80800000
    SOLID 24, 18, 12, 10, 0x40004040
    SOLID 30, 14, 20, 6, 0xC0101060
    COMPOSITE
    call checksum
    cmp eax, GOLDEN_STACK
    jne .fail
    PASS

; An opaque BGRX buffer, copied rather than blended, a translucent one over
; it
tg_opaque:
    sub rsp, 8
    mov dword [rel surface_format], DRM_FORMAT_BGR8888
    mov edi, 30
    mov esi, 20
    mov edx, 10
    mov ecx, 10
    call gradient_surface
    mov dword [rel surface_format], 0
    SOLID 20, 20, 30, 20, 0x60202020
    COMPOSITE
    call checksum
    cmp eax, GOLDEN_OPAQUE
    jne .fail
    PASS

; One surface over each edge and corner, clipped
tg_edges:
    sub rsp, 8
    SOLID 16, 12, -6, -4, 0xFF0000FF
    SOLID 14, 14, 56, -5, 0x80008000
    SOLID 20, 12, -8, 40, 0xA0500000
    SOLID 10, 10, 58, 42, 0x40404040
    COMPOSITE
    call checksum
    cmp eax, GOLDEN_EDGES
    jne .fail
    PASS

tg_client_leaves:
    sub rsp, 8
    call scene
    COMPOSITE
    lea rdi, [rel server]
    mov rsi, [rel client_id]
    call client_disconnect
    test rax, rax
    jnz .fail
    COMPOSITE
    test rax, rax
    jnz .fail
    PIXEL_IS 10, 10, BG
    PIXEL_IS 30, 20, BG
    cmp qword [rel server + Server.stack], 0
    jne .fail
    PASS

section .bss
alignb 16
server:         resb Server_size
backend:        resb Backend_size
config:         resq 8
compositor:     resb Compositor_size
arena:          resb Arena_size
pair:           resb ChannelPair_size
params:         resb 24
surface_format: resd 1                  ; 0: BGRA
client_id:      resq 1
client:         resq 1
output:         resq 1
surf_a:         resq 1
surf_b:         resq 1
pix_a:          resq 1
handle_b:       resq 1
last_handle:    resq 1
cb_count:       resq 1
alignb 16
heap:           resb HEAP_SIZE
