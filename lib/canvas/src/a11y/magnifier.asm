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

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "ugfx.inc"

extern compositor_damage_all
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
    cmp qword [rdi + Server.magnify], 0
    je .done
    jmp compositor_damage_all
.done:
    xor eax, eax
    ret

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
    mov rax, [rbx + Server.input_seat]  ; round the pointer, in its pixels
    mov ecx, [r12 + Output.width]
    shr ecx, 1
    mov edx, [r12 + Output.height]
    shr edx, 1
    test rax, rax
    jz .centred
    mov r8d, [rax + InputSeat.x]
    sub r8d, [r12 + Output.x]
    js .centred
    cmp r8d, [r12 + Output.width]
    jge .centred
    mov r9d, [rax + InputSeat.y]
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
