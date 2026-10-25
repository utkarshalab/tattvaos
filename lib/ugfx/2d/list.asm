; =============================================================================
; Utkarsha OS — lib/ugfx/2d/list.asm
; =============================================================================
; Display lists: drawing recorded once, replayed onto a context any number
; of times (icons, cached UI, the command stream a GPU backend will take).
;
;   ugfx_list_init(list, arena), ugfx_list_reset(list)
;   ugfx_list_<call>(list, ...)    the same calls and arguments as
;                                  ugfx_ctx_<call>, recorded instead of drawn
;   ugfx_list_replay(list, ctx)    runs the records through the context
;
; Records are 8-byte aligned: u32 opcode, u32 payload bytes, payload.
; Transforms, colours, styles, rects and dash intervals are stored by
; value; paths are copied in (points, then verbs) and replayed as read-only
; views into the list; paints are copied by value, but a gradient's table
; and an image paint's or draw_image's PixBuf are referenced, so they must
; outlive the list. translate / scale / rotate are stored as the matrix
; they make. Recording errors (out of memory) are sticky; replay stops at
; the first error a context call returns.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern umath_affine2_identity
extern umath_affine2_translate
extern umath_affine2_scale
extern umath_affine2_rotate
extern ugfx_ctx_save
extern ugfx_ctx_restore
extern ugfx_ctx_set_transform
extern ugfx_ctx_transform
extern ugfx_ctx_set_fill_color
extern ugfx_ctx_set_stroke_color
extern ugfx_ctx_set_fill_paint
extern ugfx_ctx_set_stroke_paint
extern ugfx_ctx_set_stroke_style
extern ugfx_ctx_set_dash
extern ugfx_ctx_set_alpha
extern ugfx_ctx_set_fill_rule
extern ugfx_ctx_set_tolerance
extern ugfx_ctx_fill
extern ugfx_ctx_stroke
extern ugfx_ctx_clip
extern ugfx_ctx_fill_rect
extern ugfx_ctx_stroke_rect
extern ugfx_ctx_draw_image
extern ugfx_ctx_clear
extern ugfx_ctx_begin_layer
extern ugfx_ctx_end_layer
extern ugfx_ctx_clip_begin
extern ugfx_ctx_clip_add
extern ugfx_ctx_clip_end
extern ugfx_ctx_begin_mask
extern ugfx_ctx_end_mask
extern ugfx_ctx_clip_stroke
extern ugfx_ctx_filter

%define LIST_INITIAL    4096

; opcodes
%define LOP_SAVE            1
%define LOP_RESTORE         2
%define LOP_SET_TRANSFORM   3
%define LOP_TRANSFORM       4
%define LOP_FILL_COLOR      5
%define LOP_STROKE_COLOR    6
%define LOP_FILL_PAINT      7
%define LOP_STROKE_PAINT    8
%define LOP_STROKE_STYLE    9
%define LOP_DASH            10
%define LOP_ALPHA           11
%define LOP_RULE            12
%define LOP_TOLERANCE       13
%define LOP_FILL            14
%define LOP_STROKE          15
%define LOP_CLIP            16
%define LOP_FILL_RECT       17
%define LOP_STROKE_RECT     18
%define LOP_DRAW_IMAGE      19
%define LOP_CLEAR           20
%define LOP_BEGIN_LAYER     21
%define LOP_END_LAYER       22
%define LOP_CLIP_BEGIN      23
%define LOP_CLIP_ADD        24
%define LOP_CLIP_END        25
%define LOP_BEGIN_MASK      26
%define LOP_END_MASK        27
%define LOP_CLIP_STROKE     28
%define LOP_FILTER          29
%define LOP_LAST            29

section .text

; -----------------------------------------------------------------------------
; ugfx_list_init — rdi = UgfxList*, rsi = arena -> rax = 0, -EINVAL, -ENOMEM
; ugfx_list_reset — rdi = UgfxList*: empty, storage kept, error cleared
; -----------------------------------------------------------------------------
global ugfx_list_init
ugfx_list_init:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    push rdi
    mov [rdi + UgfxList_arena], rsi
    mov rdi, rsi
    mov esi, LIST_INITIAL
    call arena_alloc
    pop rdi
    test rax, rax
    jz .init_nomem
    mov [rdi + UgfxList_data], rax
    mov qword [rdi + UgfxList_cap], LIST_INITIAL
    jmp ugfx_list_reset
.init_nomem:
    mov qword [rdi + UgfxList_data], 0
    mov qword [rdi + UgfxList_cap], 0
    mov qword [rdi + UgfxList_size], 0
    mov dword [rdi + UgfxList_count], 0
    mov dword [rdi + UgfxList_error], -(ENOMEM)
    mov rax, -(ENOMEM)
    ret

global ugfx_list_reset
ugfx_list_reset:
    test rdi, rdi
    jz ls_bad
    mov qword [rdi + UgfxList_size], 0
    mov dword [rdi + UgfxList_count], 0
    mov dword [rdi + UgfxList_error], 0
    xor eax, eax
    ret

ls_bad:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; ls_begin — rdi = list, esi = opcode, edx = payload bytes -> rax = payload
;   (8-aligned, zero-padded tail), or 0 with the error recorded. Keeps rdi.
; -----------------------------------------------------------------------------
ls_begin:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    cmp dword [rbx + UgfxList_error], 0
    jne .lb_fail
    lea rax, [r13 + 7 + 8]
    and rax, -8                         ; header + padded payload
    add rax, [rbx + UgfxList_size]
    cmp rax, [rbx + UgfxList_cap]
    jbe .lb_room
    ; grow to max(2 cap, needed)
    mov rsi, [rbx + UgfxList_cap]
    add rsi, rsi
    cmp rsi, rax
    jae .lb_new_cap
    mov rsi, rax
.lb_new_cap:
    push rsi
    sub rsp, 8
    mov rdi, [rbx + UgfxList_arena]
    call arena_alloc
    add rsp, 8
    pop rsi
    test rax, rax
    jz .lb_nomem
    mov [rbx + UgfxList_cap], rsi
    mov rdi, rax
    mov rsi, [rbx + UgfxList_data]
    mov rcx, [rbx + UgfxList_size]
    rep movsb
    mov [rbx + UgfxList_data], rax
.lb_room:
    mov rax, [rbx + UgfxList_data]
    add rax, [rbx + UgfxList_size]
    mov [rax], r12d
    mov [rax + 4], r13d
    lea rcx, [r13 + 7]
    and rcx, -8                         ; padded payload
    test rcx, rcx
    jz .lb_tail_ok
    mov qword [rax + rcx], 0            ; zero the last payload qword (padding)
.lb_tail_ok:
    lea rdx, [rcx + 8]
    add [rbx + UgfxList_size], rdx
    inc dword [rbx + UgfxList_count]
    add rax, 8
    mov rdi, rbx
    pop r13
    pop r12
    pop rbx
    ret
.lb_nomem:
    mov dword [rbx + UgfxList_error], -(ENOMEM)
.lb_fail:
    xor eax, eax
    mov rdi, rbx
    pop r13
    pop r12
    pop rbx
    ret

; records with no payload / a u32 / bytes copied from memory
; (rdi = list; return 0 or the list's error)
ls_error:
    movsxd rax, dword [rdi + UgfxList_error]
    ret

ls_op0:                                 ; esi = opcode
    xor edx, edx
    sub rsp, 8
    call ls_begin
    add rsp, 8
    test rax, rax
    jz ls_error
    xor eax, eax
    ret

ls_op_u32:                              ; esi = opcode, ecx = value
    push rcx
    mov edx, 4
    call ls_begin
    pop rcx
    test rax, rax
    jz ls_error
    mov [rax], ecx
    xor eax, eax
    ret

ls_op_copy:                             ; esi = opcode, rdx = source, ecx = bytes
    push rdx
    push rcx
    mov edx, ecx
    sub rsp, 8
    call ls_begin
    add rsp, 8
    pop rcx
    pop rsi
    test rax, rax
    jz ls_error
    push rdi
    mov rdi, rax
    rep movsb
    pop rdi
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; Recording: rdi = UgfxList*, then the ugfx_ctx_* arguments -> rax = 0, -errno
; -----------------------------------------------------------------------------
global ugfx_list_save
ugfx_list_save:
    test rdi, rdi
    jz ls_bad
    mov esi, LOP_SAVE
    jmp ls_op0
global ugfx_list_restore
ugfx_list_restore:
    test rdi, rdi
    jz ls_bad
    mov esi, LOP_RESTORE
    jmp ls_op0
global ugfx_list_end_layer
ugfx_list_end_layer:
    test rdi, rdi
    jz ls_bad
    mov esi, LOP_END_LAYER
    jmp ls_op0
global ugfx_list_clip_begin
ugfx_list_clip_begin:
    test rdi, rdi
    jz ls_bad
    mov esi, LOP_CLIP_BEGIN
    jmp ls_op0
global ugfx_list_clip_end
ugfx_list_clip_end:
    test rdi, rdi
    jz ls_bad
    mov esi, LOP_CLIP_END
    jmp ls_op0
global ugfx_list_begin_mask
ugfx_list_begin_mask:
    test rdi, rdi
    jz ls_bad
    mov esi, LOP_BEGIN_MASK
    jmp ls_op0

global ugfx_list_set_fill_color
ugfx_list_set_fill_color:
    mov eax, LOP_FILL_COLOR
    jmp ls_u32_entry
global ugfx_list_set_stroke_color
ugfx_list_set_stroke_color:
    mov eax, LOP_STROKE_COLOR
    jmp ls_u32_entry
global ugfx_list_set_alpha
ugfx_list_set_alpha:
    mov eax, LOP_ALPHA
    jmp ls_u32_entry
global ugfx_list_set_fill_rule
ugfx_list_set_fill_rule:
    mov eax, LOP_RULE
    jmp ls_u32_entry
global ugfx_list_clear
ugfx_list_clear:
    mov eax, LOP_CLEAR
    jmp ls_u32_entry
; ugfx_list_filter — rdi = list, rsi = UgfxFilter*: recorded by reference
;   (it must outlive the list)
global ugfx_list_filter
ugfx_list_filter:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    push rbx
    mov rbx, rsi
    mov esi, LOP_FILTER
    mov edx, 8
    call ls_begin
    test rax, rax
    jz .lf_error
    mov [rax], rbx
    xor eax, eax
    pop rbx
    ret
.lf_error:
    movsxd rax, dword [rdi + UgfxList_error]
    pop rbx
    ret
global ugfx_list_end_mask
ugfx_list_end_mask:
    mov eax, LOP_END_MASK
    jmp ls_u32_entry
global ugfx_list_begin_layer
ugfx_list_begin_layer:
    mov eax, LOP_BEGIN_LAYER
ls_u32_entry:                           ; esi = value
    test rdi, rdi
    jz ls_bad
    mov ecx, esi
    mov esi, eax
    jmp ls_op_u32

global ugfx_list_set_tolerance
ugfx_list_set_tolerance:
    test rdi, rdi
    jz ls_bad
    sub rsp, 8
    movsd [rsp], xmm0
    mov esi, LOP_TOLERANCE
    mov rdx, rsp
    mov ecx, 8
    call ls_op_copy
    add rsp, 8
    ret

global ugfx_list_set_transform
ugfx_list_set_transform:
    mov eax, LOP_SET_TRANSFORM
    jmp ls_matrix_entry
global ugfx_list_transform
ugfx_list_transform:
    mov eax, LOP_TRANSFORM
ls_matrix_entry:                        ; rsi = m
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    mov rdx, rsi
    mov esi, eax
    mov ecx, 48
    jmp ls_op_copy

global ugfx_list_translate
ugfx_list_translate:
    lea rax, [rel umath_affine2_translate]
    jmp ls_built_transform
global ugfx_list_scale
ugfx_list_scale:
    lea rax, [rel umath_affine2_scale]
    jmp ls_built_transform
global ugfx_list_rotate
ugfx_list_rotate:
    lea rax, [rel umath_affine2_rotate]
ls_built_transform:                     ; the matrix the builder makes
    test rdi, rdi
    jz ls_bad
    push rdi
    sub rsp, 48
    mov rdi, rsp
    call rax
    mov rdi, [rsp + 48]
    mov esi, LOP_TRANSFORM
    mov rdx, rsp
    mov ecx, 48
    call ls_op_copy
    add rsp, 56
    ret

global ugfx_list_set_stroke_style
ugfx_list_set_stroke_style:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    mov rdx, rsi
    mov esi, LOP_STROKE_STYLE
    mov ecx, UgfxStroke_SIZE
    jmp ls_op_copy

global ugfx_list_fill_rect
ugfx_list_fill_rect:
    mov eax, LOP_FILL_RECT
    jmp ls_rect_entry
global ugfx_list_stroke_rect
ugfx_list_stroke_rect:
    mov eax, LOP_STROKE_RECT
ls_rect_entry:                          ; xmm0..xmm3
    test rdi, rdi
    jz ls_bad
    sub rsp, 40
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    mov esi, eax
    mov rdx, rsp
    mov ecx, 32
    call ls_op_copy
    add rsp, 40
    ret

; ugfx_list_draw_image — rdi = list, rsi = PixBuf* (referenced), xmm0..3
global ugfx_list_draw_image
ugfx_list_draw_image:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    sub rsp, 40
    mov [rsp], rsi
    movsd [rsp + 8], xmm0
    movsd [rsp + 16], xmm1
    movsd [rsp + 24], xmm2
    movsd [rsp + 32], xmm3
    mov esi, LOP_DRAW_IMAGE
    mov rdx, rsp
    mov ecx, 40
    call ls_op_copy
    add rsp, 40
    ret

; ugfx_list_set_fill_paint / _set_stroke_paint — rdi = list, rsi = paint,
;   rdx = paint -> user matrix or 0: the paint and the matrix by value
global ugfx_list_set_fill_paint
ugfx_list_set_fill_paint:
    mov eax, LOP_FILL_PAINT
    jmp ls_paint_entry
global ugfx_list_set_stroke_paint
ugfx_list_set_stroke_paint:
    mov eax, LOP_STROKE_PAINT
ls_paint_entry:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov esi, eax
    mov edx, UgfxPaint_SIZE + 48
    call ls_begin
    test rax, rax
    jz .pe_error
    mov rbx, rax
    push rdi
    mov rdi, rbx
    mov rsi, r12
    mov ecx, UgfxPaint_SIZE
    rep movsb
    test r13, r13
    jz .pe_identity
    mov rsi, r13
    mov ecx, 48
    rep movsb
    jmp .pe_done
.pe_identity:
    call umath_affine2_identity
.pe_done:
    pop rdi
    xor eax, eax
    jmp .pe_out
.pe_error:
    movsxd rax, dword [rdi + UgfxList_error]
.pe_out:
    pop r13
    pop r12
    pop rbx
    ret

; ugfx_list_set_dash — rdi = list, rsi = UgfxDash* or 0: offset, count and
;   the intervals copied
global ugfx_list_set_dash
ugfx_list_set_dash:
    test rdi, rdi
    jz ls_bad
    push rbx
    push r12
    sub rsp, 8
    mov r12, rsi
    xor eax, eax
    test rsi, rsi
    jz .sd_count
    cmp qword [rsi + UgfxDash_intervals], 0
    je .sd_none
    mov eax, [rsi + UgfxDash_count]
    jmp .sd_count
.sd_none:
    xor r12d, r12d
.sd_count:
    mov ebx, eax                        ; intervals copied
    lea edx, [rax * 8 + 16]
    mov esi, LOP_DASH
    call ls_begin
    test rax, rax
    jz .sd_error
    mov dword [rax + 8], ebx
    xorpd xmm0, xmm0
    test r12, r12
    jz .sd_offset
    movsd xmm0, [r12 + UgfxDash_offset]
.sd_offset:
    movsd [rax], xmm0
    test ebx, ebx
    jz .sd_done
    push rdi
    lea rdi, [rax + 16]
    mov rsi, [r12 + UgfxDash_intervals]
    mov ecx, ebx
    shl ecx, 3
    rep movsb
    pop rdi
.sd_done:
    xor eax, eax
    jmp .sd_out
.sd_error:
    movsxd rax, dword [rdi + UgfxList_error]
.sd_out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ugfx_list_fill / _stroke / _clip — rdi = list, rsi = UgfxPath*: copied as
;   u32 verbs, u32 points, f64 points[2 n], u8 verbs[]
global ugfx_list_fill
ugfx_list_fill:
    mov eax, LOP_FILL
    jmp ls_path_entry
global ugfx_list_stroke
ugfx_list_stroke:
    mov eax, LOP_STROKE
    jmp ls_path_entry
global ugfx_list_clip
ugfx_list_clip:
    mov eax, LOP_CLIP
    jmp ls_path_entry
global ugfx_list_clip_add
ugfx_list_clip_add:
    mov eax, LOP_CLIP_ADD
    jmp ls_path_entry
global ugfx_list_clip_stroke
ugfx_list_clip_stroke:
    mov eax, LOP_CLIP_STROKE
ls_path_entry:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    cmp dword [rsi + UgfxPath_error], 0
    jne .pa_nomem
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, eax
    mov edx, [r12 + UgfxPath_point_count]
    shl edx, 4
    add edx, [r12 + UgfxPath_verb_count]
    add edx, 8
    mov esi, r13d
    call ls_begin
    test rax, rax
    jz .pa_error
    mov ecx, [r12 + UgfxPath_verb_count]
    mov [rax], ecx
    mov ecx, [r12 + UgfxPath_point_count]
    mov [rax + 4], ecx
    push rdi
    lea rdi, [rax + 8]
    mov rsi, [r12 + UgfxPath_points]
    shl ecx, 4
    rep movsb
    mov rsi, [r12 + UgfxPath_verbs]
    mov ecx, [r12 + UgfxPath_verb_count]
    rep movsb
    pop rdi
    xor eax, eax
    jmp .pa_out
.pa_error:
    movsxd rax, dword [rdi + UgfxList_error]
.pa_out:
    pop r13
    pop r12
    pop rbx
    ret
.pa_nomem:
    mov rax, -(ENOMEM)
    ret

; -----------------------------------------------------------------------------
; ugfx_list_replay — rdi = const UgfxList*, rsi = UgfxContext*
;   -> rax = 0, the list's recording error, -EINVAL (corrupt record), or the
;   first error a context call returns
; -----------------------------------------------------------------------------
%define R_PATH      0                   ; UgfxPath view
%define R_DASH      UgfxPath_SIZE       ; UgfxDash
%define R_SIZE      (UgfxPath_SIZE + UgfxDash_SIZE + 8)

global ugfx_list_replay
ugfx_list_replay:
    test rdi, rdi
    jz ls_bad
    test rsi, rsi
    jz ls_bad
    movsxd rax, dword [rdi + UgfxList_error]
    test rax, rax
    jnz .rp_ret
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, R_SIZE
    mov rbx, rdi
    mov r12, rsi                        ; ctx
    mov r13, [rbx + UgfxList_data]      ; cursor
    mov r14, r13
    add r14, [rbx + UgfxList_size]      ; end
.rp_record:
    cmp r13, r14
    jae .rp_ok
    mov eax, [r13]                      ; opcode
    mov ecx, [r13 + 4]                  ; payload bytes
    lea r15, [r13 + 8]                  ; payload
    lea rdx, [rcx + 7]
    and rdx, -8
    lea r13, [r15 + rdx]                ; next record
    cmp r13, r14
    ja .rp_corrupt
    dec eax
    cmp eax, LOP_LAST - 1
    ja .rp_corrupt
    lea rdx, [rel replay_jumps]
    mov rdi, r12
    jmp [rdx + rax * 8]
.r_save:
    call ugfx_ctx_save
    jmp .rp_check
.r_restore:
    call ugfx_ctx_restore
    jmp .rp_check
.r_end_layer:
    call ugfx_ctx_end_layer
    jmp .rp_check
.r_clip_begin:
    call ugfx_ctx_clip_begin
    jmp .rp_check
.r_begin_mask:
    call ugfx_ctx_begin_mask
    jmp .rp_check
.r_end_mask:
    mov esi, [r15]
    call ugfx_ctx_end_mask
    jmp .rp_check
.r_clip_end:
    call ugfx_ctx_clip_end
    jmp .rp_check
.r_clip_add:
    lea rax, [rel ugfx_ctx_clip_add]
    jmp .r_path
.r_clip_stroke:
    lea rax, [rel ugfx_ctx_clip_stroke]
    jmp .r_path
.r_filter:
    mov rsi, [r15]
    call ugfx_ctx_filter
    jmp .rp_check
.r_set_transform:
    mov rsi, r15
    call ugfx_ctx_set_transform
    jmp .rp_check
.r_transform:
    mov rsi, r15
    call ugfx_ctx_transform
    jmp .rp_check
.r_fill_color:
    mov esi, [r15]
    call ugfx_ctx_set_fill_color
    jmp .rp_check
.r_stroke_color:
    mov esi, [r15]
    call ugfx_ctx_set_stroke_color
    jmp .rp_check
.r_alpha:
    mov esi, [r15]
    call ugfx_ctx_set_alpha
    jmp .rp_check
.r_rule:
    mov esi, [r15]
    call ugfx_ctx_set_fill_rule
    jmp .rp_check
.r_clear:
    mov esi, [r15]
    call ugfx_ctx_clear
    jmp .rp_check
.r_begin_layer:
    mov esi, [r15]
    call ugfx_ctx_begin_layer
    jmp .rp_check
.r_tolerance:
    movsd xmm0, [r15]
    call ugfx_ctx_set_tolerance
    jmp .rp_check
.r_fill_paint:
    mov rsi, r15
    lea rdx, [r15 + UgfxPaint_SIZE]
    call ugfx_ctx_set_fill_paint
    jmp .rp_check
.r_stroke_paint:
    mov rsi, r15
    lea rdx, [r15 + UgfxPaint_SIZE]
    call ugfx_ctx_set_stroke_paint
    jmp .rp_check
.r_stroke_style:
    mov rsi, r15
    call ugfx_ctx_set_stroke_style
    jmp .rp_check
.r_dash:
    mov ecx, [r15 + 8]
    test ecx, ecx
    jz .r_dash_off
    movsd xmm0, [r15]
    movsd [rsp + R_DASH + UgfxDash_offset], xmm0
    mov [rsp + R_DASH + UgfxDash_count], ecx
    lea rax, [r15 + 16]
    mov [rsp + R_DASH + UgfxDash_intervals], rax
    lea rsi, [rsp + R_DASH]
    call ugfx_ctx_set_dash
    jmp .rp_check
.r_dash_off:
    xor esi, esi
    call ugfx_ctx_set_dash
    jmp .rp_check
.r_fill_rect:
    call .r_rect_args
    call ugfx_ctx_fill_rect
    jmp .rp_check
.r_stroke_rect:
    call .r_rect_args
    call ugfx_ctx_stroke_rect
    jmp .rp_check
.r_draw_image:
    mov rsi, [r15]
    add r15, 8
    call .r_rect_args
    call ugfx_ctx_draw_image
    jmp .rp_check
.r_rect_args:
    movsd xmm0, [r15]
    movsd xmm1, [r15 + 8]
    movsd xmm2, [r15 + 16]
    movsd xmm3, [r15 + 24]
    ret
.r_fill:
    lea rax, [rel ugfx_ctx_fill]
    jmp .r_path
.r_stroke:
    lea rax, [rel ugfx_ctx_stroke]
    jmp .r_path
.r_clip:
    lea rax, [rel ugfx_ctx_clip]
.r_path:
    ; a read-only path view over the record
    mov ecx, [r15]                      ; verbs
    mov edx, [r15 + 4]                  ; points
    mov [rsp + R_PATH + UgfxPath_verb_count], ecx
    mov [rsp + R_PATH + UgfxPath_verb_cap], ecx
    mov [rsp + R_PATH + UgfxPath_point_count], edx
    mov [rsp + R_PATH + UgfxPath_point_cap], edx
    lea rsi, [r15 + 8]
    mov [rsp + R_PATH + UgfxPath_points], rsi
    shl rdx, 4
    add rsi, rdx
    mov [rsp + R_PATH + UgfxPath_verbs], rsi
    mov rsi, [rbx + UgfxList_arena]
    mov [rsp + R_PATH + UgfxPath_arena], rsi
    mov dword [rsp + R_PATH + UgfxPath_start], 0
    mov dword [rsp + R_PATH + UgfxPath_open], 0
    mov dword [rsp + R_PATH + UgfxPath_error], 0
    lea rsi, [rsp + R_PATH]
    call rax
.rp_check:
    test rax, rax
    jz .rp_record
    jmp .rp_out
.rp_corrupt:
    mov rax, -(EINVAL)
    jmp .rp_out
.rp_ok:
    xor eax, eax
.rp_out:
    add rsp, R_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.rp_ret:
    ret

section .data
align 8
replay_jumps:
    dq ugfx_list_replay.r_save, ugfx_list_replay.r_restore
    dq ugfx_list_replay.r_set_transform, ugfx_list_replay.r_transform
    dq ugfx_list_replay.r_fill_color, ugfx_list_replay.r_stroke_color
    dq ugfx_list_replay.r_fill_paint, ugfx_list_replay.r_stroke_paint
    dq ugfx_list_replay.r_stroke_style, ugfx_list_replay.r_dash
    dq ugfx_list_replay.r_alpha, ugfx_list_replay.r_rule
    dq ugfx_list_replay.r_tolerance, ugfx_list_replay.r_fill
    dq ugfx_list_replay.r_stroke, ugfx_list_replay.r_clip
    dq ugfx_list_replay.r_fill_rect, ugfx_list_replay.r_stroke_rect
    dq ugfx_list_replay.r_draw_image, ugfx_list_replay.r_clear
    dq ugfx_list_replay.r_begin_layer, ugfx_list_replay.r_end_layer
    dq ugfx_list_replay.r_clip_begin, ugfx_list_replay.r_clip_add
    dq ugfx_list_replay.r_clip_end
    dq ugfx_list_replay.r_begin_mask, ugfx_list_replay.r_end_mask
    dq ugfx_list_replay.r_clip_stroke, ugfx_list_replay.r_filter

global ugfx_list_version
ugfx_list_version: dq 0x010000
