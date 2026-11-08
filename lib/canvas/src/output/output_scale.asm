; ============================================================================
; Output Scale — The Logical Layout (decision 0012, step 3)
; ============================================================================
; The layout is in logical units: an output at scale s spans its pixel size
; divided by s there (Output.width and height), so screens of different
; densities line up and a window is the same size on each.
;
; An output at a scale other than 1 composes its part at that logical size,
; into a frame of its own (Output.framebuffer), and output_present scales
; what was drawn into its pixels (Output.pixel_fb, bilinear, the damage
; mapped outwards) before the backend shows it. At scale 1 the frame is the
; pixels and nothing is scaled. Composing straight at the output's pixels,
; sharper on a dense panel, is a later step (the decision's revisit
; criteria).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "ugfx.inc"

extern compositor_damage_all
extern input_keep_pointer
extern output_announce
extern region_add_rect
extern region_clear
extern region_init
extern scale_bilinear_rect

%define SCALE_MIN   120                 ; 1
%define SCALE_MAX   480                 ; 4

section .text

; ---------------------------------------------------------------------------
; output_set_scale
;   An output's scale: its logical size becomes its pixel size divided by
;   it, rounded; the outputs to its right move with its new width; every
;   output is redrawn, the pointer kept on the layout and the clients
;   watching told (a mirror is no part of the layout: not told)
;   IN:  rdi = server*, rsi = Output*, edx = scale in 120ths (120 to 480;
;        0 is 120)
;   OUT: rax = 0, -EINVAL out of range, -ENOMEM
; ---------------------------------------------------------------------------
%define S_OLD_W     0
%define S_LW        4
%define S_LH        8
%define S_BASE      16
%define S_REGION    24
global output_set_scale
output_set_scale:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40                         ; locals; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    test r13d, r13d
    jnz .given
    mov r13d, SCALE_MIN
.given:
    mov rax, -(EINVAL)
    cmp r13d, SCALE_MIN
    jb .out
    cmp r13d, SCALE_MAX
    ja .out
    mov r14d, [r12 + Output.width]      ; its pixels
    mov r15d, [r12 + Output.height]
    cmp qword [r12 + Output.pixel_fb], 0
    je .pixels
    mov r14d, [r12 + Output.pixel_width]
    mov r15d, [r12 + Output.pixel_height]
.pixels:
    mov eax, [r12 + Output.width]
    mov [rsp + S_OLD_W], eax
    cmp r13d, SCALE_MIN
    jne .scaled

    cmp qword [r12 + Output.pixel_fb], 0    ; 1: the pixels are the frame
    je .sized
    mov rdi, [r12 + Output.fb_region]
    test rdi, rdi
    jz .unframed
    call ut_mem_free
.unframed:
    mov rax, [r12 + Output.pixel_fb]
    mov [r12 + Output.framebuffer], rax
    mov rax, [r12 + Output.pixel_stride]
    mov [r12 + Output.stride], rax
    mov rax, [r12 + Output.pixel_region]
    mov [r12 + Output.fb_region], rax
    mov [r12 + Output.width], r14d
    mov [r12 + Output.height], r15d
    mov qword [r12 + Output.pixel_fb], 0
    mov qword [r12 + Output.pixel_region], 0
    jmp .sized

.scaled:
    mov eax, r14d                       ; the logical size, rounded
    imul eax, eax, 120
    mov ecx, r13d
    shr ecx, 1
    add eax, ecx
    xor edx, edx
    div r13d
    mov [rsp + S_LW], eax
    mov eax, r15d
    imul eax, eax, 120
    mov ecx, r13d
    shr ecx, 1
    add eax, ecx
    xor edx, edx
    div r13d
    mov [rsp + S_LH], eax
    mov edi, [rsp + S_LW]               ; a frame that size
    shl rdi, 2
    mov eax, [rsp + S_LH]
    imul rdi, rax
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .oom
    mov [rsp + S_BASE], rax
    mov [rsp + S_REGION], r8
    cmp qword [r12 + Output.pixel_damage], 0
    jne .have_damage
    mov rdi, [r12 + Output.backend]
    mov rdi, [rdi + Backend.arena]
    call region_init
    test rax, rax
    jz .no_damage
    mov [r12 + Output.pixel_damage], rax
.have_damage:
    cmp qword [r12 + Output.pixel_fb], 0
    jne .reframe
    mov rax, [r12 + Output.framebuffer] ; the first time: the pixels aside
    mov [r12 + Output.pixel_fb], rax
    mov rax, [r12 + Output.stride]
    mov [r12 + Output.pixel_stride], rax
    mov rax, [r12 + Output.fb_region]
    mov [r12 + Output.pixel_region], rax
    mov [r12 + Output.pixel_width], r14d
    mov [r12 + Output.pixel_height], r15d
    jmp .framed
.reframe:
    mov rdi, [r12 + Output.fb_region]   ; the old logical frame goes
    test rdi, rdi
    jz .framed
    call ut_mem_free
.framed:
    mov rax, [rsp + S_BASE]
    mov [r12 + Output.framebuffer], rax
    mov rax, [rsp + S_REGION]
    mov [r12 + Output.fb_region], rax
    mov eax, [rsp + S_LW]
    mov [r12 + Output.width], eax
    shl eax, 2
    mov [r12 + Output.stride], rax
    mov eax, [rsp + S_LH]
    mov [r12 + Output.height], eax

.sized:
    mov eax, r13d                       ; 16.16
    shl rax, 16
    xor edx, edx
    mov ecx, 120
    div rcx
    mov [r12 + Output.scale], rax
    mov rdi, [r12 + Output.magnify_region]  ; the magnifier's frame was for
    test rdi, rdi                           ; the old size: made again
    jz .relayout
    call ut_mem_free
    mov qword [r12 + Output.magnify_region], 0
    mov qword [r12 + Output.magnify_buf], 0
.relayout:
    cmp qword [r12 + Output.mirror_of], 0
    jne .redraw                         ; no part of the layout
    mov eax, [r12 + Output.width]       ; the ones right of it move
    sub eax, [rsp + S_OLD_W]
    jz .redraw
    movsxd r8, eax
    mov r9d, [r12 + Output.x]
    add r9d, [rsp + S_OLD_W]            ; its old right edge
    mov rcx, [rbx + Server.outputs]
.right:
    test rcx, rcx
    jz .redraw
    cmp rcx, r12
    je .next
    cmp qword [rcx + Output.mirror_of], 0
    jne .next
    cmp [rcx + Output.x], r9d
    jl .next
    add [rcx + Output.x], r8
.next:
    mov rcx, [rcx + Output.next]
    jmp .right
.redraw:
    mov rdi, rbx
    call input_keep_pointer
    mov rdi, rbx
    call compositor_damage_all
    cmp qword [r12 + Output.mirror_of], 0
    jne .done
    mov rdi, rbx                        ; its new size and scale
    mov rsi, r12
    call output_announce
    mov rcx, [rbx + Server.outputs]     ; and the places of those that moved
.tell:
    test rcx, rcx
    jz .done
    cmp rcx, r12
    je .told
    cmp qword [rcx + Output.mirror_of], 0
    jne .told
    mov r9d, [rcx + Output.x]
    cmp r9d, [r12 + Output.x]
    jle .told
    push rcx
    push rcx                            ; 16-byte aligned
    mov rdi, rbx
    mov rsi, rcx
    call output_announce
    pop rcx
    pop rcx
.told:
    mov rcx, [rcx + Output.next]
    jmp .tell
.done:
    xor eax, eax
.out:
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.no_damage:
    mov rdi, [rsp + S_REGION]
    call ut_mem_free
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; output_present
;   What was drawn into an output's frame, to its screen: scaled into its
;   pixels first when it has a scale (each damaged rectangle mapped outwards,
;   then wider by what one logical unit spans and two more, for the pixels
;   that blend it in), then to the backend's flip, if it has one
;   IN:  rdi = Output*, rsi = its damage (the layout's)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
%define P_JOB       0
%define P_RECT      UgfxScale_SIZE      ; x0, y0, x1, y1 in the frame, then
                                        ; x, y, w, h in the pixels
%define P_VIEW      (UgfxScale_SIZE + 16)   ; x, y, framebuffer, stride
%define P_VIEW_WH   (UgfxScale_SIZE + 48)   ; width, height
global output_present
output_present:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, UgfxScale_SIZE + 56        ; the job, a rect, the view; aligned
    mov rbx, rdi
    mov r12, rsi
    cmp qword [rbx + Output.pixel_fb], 0
    jne .scaled
    mov rdi, [rbx + Output.backend]     ; the frame is the pixels
    mov rax, [rdi + Backend.flip]
    test rax, rax
    jz .done
    mov rsi, rbx
    mov rdx, r12
    xor ecx, ecx
    call rax
    jmp .done

.scaled:
    mov rdi, [rbx + Output.pixel_damage]
    call region_clear
    mov rax, [rbx + Output.pixel_fb]
    mov [rsp + P_JOB + UgfxScale_dst], rax
    mov rax, [rbx + Output.pixel_stride]
    mov [rsp + P_JOB + UgfxScale_dst_stride], rax
    mov eax, [rbx + Output.pixel_width]
    mov [rsp + P_JOB + UgfxScale_dst_w], eax
    mov eax, [rbx + Output.pixel_height]
    mov [rsp + P_JOB + UgfxScale_dst_h], eax
    mov rax, [rbx + Output.framebuffer]
    mov [rsp + P_JOB + UgfxScale_src], rax
    mov rax, [rbx + Output.stride]
    mov [rsp + P_JOB + UgfxScale_src_stride], rax
    mov eax, [rbx + Output.width]
    mov [rsp + P_JOB + UgfxScale_src_w], eax
    mov eax, [rbx + Output.height]
    mov [rsp + P_JOB + UgfxScale_src_h], eax
    xor r13d, r13d
.rect:
    cmp r13, [r12 + Region.count]
    jae .flip
    mov rax, r13
    shl rax, 4
    add rax, [r12 + Region.rects]
    mov ecx, [rax]                      ; in the frame, inside it
    sub ecx, [rbx + Output.x]
    mov edx, [rax + 4]
    sub edx, [rbx + Output.y]
    mov r8d, ecx
    add r8d, [rax + 8]
    mov r9d, edx
    add r9d, [rax + 12]
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    cmp edx, eax
    cmovl edx, eax
    cmp r8d, [rbx + Output.width]
    cmovg r8d, [rbx + Output.width]
    cmp r9d, [rbx + Output.height]
    cmovg r9d, [rbx + Output.height]
    cmp r8d, ecx
    jle .next_rect
    cmp r9d, edx
    jle .next_rect
    mov [rsp + P_RECT], ecx
    mov [rsp + P_RECT + 4], edx
    mov [rsp + P_RECT + 8], r8d
    mov [rsp + P_RECT + 12], r9d
%macro P_MAP 4                          ; slot, pixel size, frame size, 1: up
    mov eax, [rsp + P_RECT + %1]
    mul dword [rbx + Output.%2]
  %if %4
    mov ecx, [rbx + Output.%3]
    dec ecx
    add eax, ecx
    adc edx, 0
  %endif
    div dword [rbx + Output.%3]
    mov [rsp + P_RECT + %1], eax
%endmacro
    P_MAP 0, pixel_width, width, 0
    P_MAP 4, pixel_height, height, 0
    P_MAP 8, pixel_width, width, 1
    P_MAP 12, pixel_height, height, 1
%macro P_WIDEN 4                        ; start's slot, end's, pixel size, frame's
    mov eax, [rbx + Output.%3]
    xor edx, edx
    div dword [rbx + Output.%4]
    add eax, 2
    mov ecx, [rsp + P_RECT + %1]
    sub ecx, eax
    xor edx, edx
    cmp ecx, edx
    cmovl ecx, edx
    mov [rsp + P_RECT + %1], ecx
    mov ecx, [rsp + P_RECT + %2]
    add ecx, eax
    cmp ecx, [rbx + Output.%3]
    cmovg ecx, [rbx + Output.%3]
    mov [rsp + P_RECT + %2], ecx
%endmacro
    P_WIDEN 0, 8, pixel_width, width
    P_WIDEN 4, 12, pixel_height, height
    mov eax, [rsp + P_RECT]
    mov [rsp + P_JOB + UgfxScale_x], eax
    mov ecx, [rsp + P_RECT + 8]
    sub ecx, eax
    jle .next_rect
    mov [rsp + P_JOB + UgfxScale_w], ecx
    mov [rsp + P_RECT + 8], ecx
    mov eax, [rsp + P_RECT + 4]
    mov [rsp + P_JOB + UgfxScale_y], eax
    mov ecx, [rsp + P_RECT + 12]
    sub ecx, eax
    jle .next_rect
    mov [rsp + P_JOB + UgfxScale_h], ecx
    mov [rsp + P_RECT + 12], ecx
    lea rdi, [rsp + P_JOB]
    call scale_bilinear_rect
    mov rdi, [rbx + Output.pixel_damage]    ; in the pixels, from 0, 0
    lea rsi, [rsp + P_RECT]
    call region_add_rect
.next_rect:
    inc r13
    jmp .rect

.flip:
    mov rdi, [rbx + Output.backend]     ; the backend sees the pixels as the
    mov r14, [rdi + Backend.flip]       ; output, at 0, 0, while it flips
    test r14, r14
    jz .done
    mov rax, [rbx + Output.x]
    mov [rsp + P_VIEW], rax
    mov rax, [rbx + Output.y]
    mov [rsp + P_VIEW + 8], rax
    mov rax, [rbx + Output.framebuffer]
    mov [rsp + P_VIEW + 16], rax
    mov rax, [rbx + Output.stride]
    mov [rsp + P_VIEW + 24], rax
    mov eax, [rbx + Output.width]
    mov [rsp + P_VIEW_WH], eax
    mov eax, [rbx + Output.height]
    mov [rsp + P_VIEW_WH + 4], eax
    mov qword [rbx + Output.x], 0
    mov qword [rbx + Output.y], 0
    mov rax, [rbx + Output.pixel_fb]
    mov [rbx + Output.framebuffer], rax
    mov rax, [rbx + Output.pixel_stride]
    mov [rbx + Output.stride], rax
    mov eax, [rbx + Output.pixel_width]
    mov [rbx + Output.width], eax
    mov eax, [rbx + Output.pixel_height]
    mov [rbx + Output.height], eax
    mov rsi, rbx
    mov rdx, [rbx + Output.pixel_damage]
    xor ecx, ecx
    call r14
    mov rax, [rsp + P_VIEW]             ; the output as it was
    mov [rbx + Output.x], rax
    mov rax, [rsp + P_VIEW + 8]
    mov [rbx + Output.y], rax
    mov rax, [rsp + P_VIEW + 16]
    mov [rbx + Output.framebuffer], rax
    mov rax, [rsp + P_VIEW + 24]
    mov [rbx + Output.stride], rax
    mov eax, [rsp + P_VIEW_WH]
    mov [rbx + Output.width], eax
    mov eax, [rsp + P_VIEW_WH + 4]
    mov [rbx + Output.height], eax
.done:
    xor eax, eax
    add rsp, UgfxScale_SIZE + 56
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global output_scale_version
output_scale_version: dq 0x010000
