; ============================================================================
; Magnifier — The Screen Zoomed Round the Pointer (A11Y-06)
; ============================================================================
; Server.magnify is 0 (off), 2 or 4. While it is on, each output draws its
; whole frame as ever, then magnify_output scales the part round the pointer
; (1/zoom of it each way, kept inside the output; the output's middle when
; the pointer is on another) over all of it, nearest neighbour, through a
; scratch frame of its own (Output.magnify_buf). So the framebuffer holds the
; zoomed picture, and every frame while zoomed is drawn whole again
; (magnify_frame), and a move of the pointer is a frame (magnify_moved).
; Super+Shift+M goes off, 2x, 4x, off (input), on the login screen too.
;
; The view follows the keyboard too (magnify_focus): a surface given the
; keyboard other than by a click on it is shown from its top-left corner
; (its middle, if it is smaller than the view) until the pointer moves; one
; given it by a click (the pointer on it or its title bar) is not.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "ugfx.inc"

extern compositor_damage_all
extern handle_resolve
extern titlebar_part
extern surface_logical_size
extern memcopy
extern region_add_rect
extern scale_nearest_rect

section .text

; ---------------------------------------------------------------------------
; server_set_magnifier
;   The zoom: 0 (or 1) off, 2, 4; off, the scratch frames go
;   IN:  rdi = server*, esi = zoom
;   OUT: rax = 0, -EINVAL for another
; ---------------------------------------------------------------------------
global server_set_magnifier
server_set_magnifier:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, -(EINVAL)
    cmp esi, 1
    jbe .off
    cmp esi, 2
    je .set
    cmp esi, 4
    jne .out
    jmp .set
.off:
    mov qword [rbx + Server.magnify], 0
    mov r12, [rbx + Server.outputs]     ; the scratch frames go
.free:
    test r12, r12
    jz .redraw
    mov rdi, [r12 + Output.magnify_region]
    test rdi, rdi
    jz .next
    call ut_mem_free
    mov qword [r12 + Output.magnify_region], 0
    mov qword [r12 + Output.magnify_buf], 0
.next:
    mov r12, [r12 + Output.next]
    jmp .free
.set:
    mov [rbx + Server.magnify], rsi
.redraw:
    mov rdi, rbx
    call compositor_damage_all
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; magnify_moved
;   The pointer moved: while zoomed, the view goes with it
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global magnify_moved
magnify_moved:
    mov qword [rdi + Server.magnify_follow], 0  ; the pointer leads again
    cmp qword [rdi + Server.magnify], 0
    je .done
    jmp compositor_damage_all
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; magnify_focus
;   The keyboard went to a surface: the view goes to it (and is redrawn,
;   while zoomed), unless the pointer is on it, as after a click
;   IN:  rdi = server*, rsi = Surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global magnify_focus
magnify_focus:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; its rect; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .done
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .done                            ; nothing drawn: nowhere to go
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .done
    mov rdi, r12                        ; its size on the screen
    mov rsi, rax
    call surface_logical_size
    mov ecx, [r12 + Surface.current + SurfaceState.buf_x]
    mov r8d, [r12 + Surface.current + SurfaceState.buf_y]
    mov [rsp], ecx
    mov [rsp + 4], r8d
    mov [rsp + 8], eax
    mov [rsp + 12], edx
    mov r9, [rbx + Server.input_seat]   ; the pointer on it or its title
    test r9, r9                         ; bar: it leads
    jz .take
    mov r10d, [r9 + InputSeat.x]
    sub r10d, ecx
    js .bar
    cmp r10d, eax
    jge .bar
    mov r10d, [r9 + InputSeat.y]
    sub r10d, r8d
    js .bar
    cmp r10d, edx
    jl .done
.bar:
    mov rdi, r12
    mov esi, [r9 + InputSeat.x]
    mov edx, [r9 + InputSeat.y]
    call titlebar_part
    test rax, rax
    jnz .done
.take:
    mov eax, [rsp]
    mov [rbx + Server.magnify_rect], eax
    mov eax, [rsp + 4]
    mov [rbx + Server.magnify_rect + 4], eax
    mov eax, [rsp + 8]
    mov [rbx + Server.magnify_rect + 8], eax
    mov eax, [rsp + 12]
    mov [rbx + Server.magnify_rect + 12], eax
    mov qword [rbx + Server.magnify_follow], 1
    cmp qword [rbx + Server.magnify], 0
    je .done
    mov rdi, rbx
    call compositor_damage_all
.done:
    xor eax, eax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; magnify_frame
;   A frame about to be drawn: while zoomed, all of the output
;   IN:  rdi = server*, rsi = the output's damage, rdx = its bounds rect*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global magnify_frame
magnify_frame:
    cmp qword [rdi + Server.magnify], 0
    je .done
    mov rdi, rsi
    mov rsi, rdx
    jmp region_add_rect
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; magnify_output
;   An output just drawn: while zoomed, the part round the pointer over all
;   of it
;   IN:  rdi = server*, rsi = Output*
;   OUT: rax = 0, -ENOMEM without room for the scratch frame (left unzoomed)
; ---------------------------------------------------------------------------
global magnify_output
magnify_output:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, UgfxScale_SIZE             ; the job; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + Server.magnify]
    test r13, r13
    jz .done
    cmp qword [r12 + Output.magnify_buf], 0
    jne .have
    mov edi, [r12 + Output.width]       ; its scratch frame, once
    imul edi, [r12 + Output.height]
    shl rdi, 2
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .oom
    mov [r12 + Output.magnify_buf], rax
    mov [r12 + Output.magnify_region], r8
.have:
    mov eax, [r12 + Output.width]       ; the view: 1/zoom of it each way
    xor edx, edx
    div r13d
    mov [rsp + UgfxScale_src_w], eax
    mov eax, [r12 + Output.height]
    xor edx, edx
    div r13d
    mov [rsp + UgfxScale_src_h], eax
    mov ecx, [r12 + Output.width]       ; round the pointer or the focus,
    shr ecx, 1                          ; in its pixels
    mov edx, [r12 + Output.height]
    shr edx, 1
    cmp qword [rbx + Server.magnify_follow], 0
    je .pointer
    mov r8d, [rbx + Server.magnify_rect + 8]    ; the focus: its corner
    cmp r8d, [rsp + UgfxScale_src_w]            ; and a view's width on,
    cmovg r8d, [rsp + UgfxScale_src_w]          ; or its middle
    shr r8d, 1
    add r8d, [rbx + Server.magnify_rect]
    mov r9d, [rbx + Server.magnify_rect + 12]
    cmp r9d, [rsp + UgfxScale_src_h]
    cmovg r9d, [rsp + UgfxScale_src_h]
    shr r9d, 1
    add r9d, [rbx + Server.magnify_rect + 4]
    jmp .point
.pointer:
    mov rax, [rbx + Server.input_seat]
    test rax, rax
    jz .centred
    mov r8d, [rax + InputSeat.x]
    mov r9d, [rax + InputSeat.y]
.point:
    sub r8d, [r12 + Output.x]
    js .centred
    cmp r8d, [r12 + Output.width]
    jge .centred
    sub r9d, [r12 + Output.y]
    js .centred
    cmp r9d, [r12 + Output.height]
    jge .centred
    mov ecx, r8d
    mov edx, r9d
.centred:
    mov eax, [rsp + UgfxScale_src_w]    ; its corner, kept inside
    shr eax, 1
    sub ecx, eax
    mov eax, [r12 + Output.width]
    sub eax, [rsp + UgfxScale_src_w]
    cmp ecx, eax
    cmovg ecx, eax
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    mov eax, [rsp + UgfxScale_src_h]
    shr eax, 1
    sub edx, eax
    mov eax, [r12 + Output.height]
    sub eax, [rsp + UgfxScale_src_h]
    cmp edx, eax
    cmovg edx, eax
    xor eax, eax
    cmp edx, eax
    cmovl edx, eax
    mov rax, [r12 + Output.stride]      ; the view's first pixel
    mov [rsp + UgfxScale_src_stride], rax
    imul rax, rdx
    lea rax, [rax + rcx * 4]
    add rax, [r12 + Output.framebuffer]
    mov [rsp + UgfxScale_src], rax
    mov rax, [r12 + Output.magnify_buf] ; over all of the scratch frame
    mov [rsp + UgfxScale_dst], rax
    mov eax, [r12 + Output.width]
    mov [rsp + UgfxScale_dst_w], eax
    mov [rsp + UgfxScale_w], eax
    shl rax, 2
    mov [rsp + UgfxScale_dst_stride], rax
    mov eax, [r12 + Output.height]
    mov [rsp + UgfxScale_dst_h], eax
    mov [rsp + UgfxScale_h], eax
    mov dword [rsp + UgfxScale_x], 0
    mov dword [rsp + UgfxScale_y], 0
    mov rdi, rsp
    call scale_nearest_rect
    mov r13, [r12 + Output.framebuffer] ; then back into the framebuffer
    mov r14, [r12 + Output.magnify_buf]
    mov ebx, [r12 + Output.height]
.row:
    test ebx, ebx
    jz .done
    mov rdi, r13
    mov rsi, r14
    mov edx, [r12 + Output.width]
    shl rdx, 2
    call memcopy
    add r13, [r12 + Output.stride]
    mov eax, [r12 + Output.width]
    lea r14, [r14 + rax * 4]
    dec ebx
    jmp .row
.done:
    xor eax, eax
.out:
    add rsp, UgfxScale_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14
.oom:
    mov rax, -(ENOMEM)
    jmp .out

section .data
global magnifier_version
magnifier_version: dq 0x020000
