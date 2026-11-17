; ============================================================================
; Nine-Patch — an Image Stretched Around Its Fixed Corners
; ============================================================================
; G2D-11. A source image is cut by four insets (left, top, right, bottom)
; into nine cells. Drawn into a rectangle of the destination: the corners
; at their own size, the top and bottom edges stretched across, the left
; and right edges stretched down, the middle stretched both ways. A
; rectangle narrower (or shorter) than its two corners together shrinks
; them in proportion and has no middle. Each cell is a nearest-neighbour
; scale (scale_nearest_rect); pixels are copied, not blended.

%include "ugfx.inc"

extern scale_nearest_rect

section .text

; ---------------------------------------------------------------------------
; ninepatch_draw
;   IN:  rdi = UgfxNine job
;   OUT: rax = 0, -EINVAL if the insets do not fit in the source
; ---------------------------------------------------------------------------
%define N_CELL      0                   ; a cell's scale job
%define N_DX        (UgfxScale_SIZE)    ; the three columns of the
%define N_DW        (N_DX + 12)         ; destination: x, width
%define N_DY        (N_DW + 12)         ; and rows: y, height
%define N_DH        (N_DY + 12)
%define N_SX        (N_DH + 12)         ; the same in the source
%define N_SW        (N_SX + 12)
%define N_SY        (N_SW + 12)
%define N_SH        (N_SY + 12)
%define N_FRAME     (N_SH + 12 + 8)     ; 16-byte aligned
global ninepatch_draw
ninepatch_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, N_FRAME
    mov rbx, rdi
    mov rax, -(EINVAL)
    mov ecx, [rbx + UgfxNine_left]
    add ecx, [rbx + UgfxNine_right]
    jc .out
    cmp ecx, [rbx + UgfxNine_src_w]
    ja .out
    mov ecx, [rbx + UgfxNine_top]
    add ecx, [rbx + UgfxNine_bottom]
    jc .out
    cmp ecx, [rbx + UgfxNine_src_h]
    ja .out

    ; The columns, then the rows: places and sizes on both sides
%macro SPLIT 7      ; size, inset 1, inset 2, source size, dst x, dst w, src
    mov eax, [rbx + UgfxNine_%2]        ; the corners as they are, or
    mov ecx, [rbx + UgfxNine_%3]        ; shrunk to fit
    mov edx, [rbx + UgfxNine_%1]
    lea r8d, [rax + rcx]
    cmp r8d, edx
    jbe %%fits
    imul eax, edx                       ; first = inset 1 x size / both
    push rdx
    xor edx, edx
    div r8d
    pop rdx
    mov ecx, edx
    sub ecx, eax
%%fits:
    mov dword [rsp + %5], 0             ; destination: 0, first, size - second
    mov [rsp + %6], eax
    mov [rsp + %5 + 4], eax
    mov r8d, edx
    sub r8d, eax
    sub r8d, ecx
    mov [rsp + %6 + 4], r8d
    add r8d, eax
    mov [rsp + %5 + 8], r8d
    mov [rsp + %6 + 8], ecx
    mov eax, [rbx + UgfxNine_%2]        ; source: as the insets say
    mov ecx, [rbx + UgfxNine_%3]
    mov edx, [rbx + UgfxNine_%4]
    mov dword [rsp + %7], 0
    mov [rsp + %7 + 12], eax
    mov [rsp + %7 + 4], eax
    mov r8d, edx
    sub r8d, eax
    sub r8d, ecx
    mov [rsp + %7 + 16], r8d
    add r8d, eax
    mov [rsp + %7 + 8], r8d
    mov [rsp + %7 + 20], ecx
%endmacro
    SPLIT w, left, right, src_w, N_DX, N_DW, N_SX
    SPLIT h, top, bottom, src_h, N_DY, N_DH, N_SY

    ; Each cell
    mov rax, [rbx + UgfxNine_dst_stride]
    mov [rsp + N_CELL + UgfxScale_dst_stride], rax
    mov rax, [rbx + UgfxNine_src_stride]
    mov [rsp + N_CELL + UgfxScale_src_stride], rax
    mov dword [rsp + N_CELL + UgfxScale_x], 0
    mov dword [rsp + N_CELL + UgfxScale_y], 0
    xor r12d, r12d                      ; the row
.row:
    xor r13d, r13d                      ; the column
.cell:
    mov eax, [rsp + N_DW + r13 * 4]
    mov ecx, [rsp + N_DH + r12 * 4]
    mov edx, [rsp + N_SW + r13 * 4]
    mov r8d, [rsp + N_SH + r12 * 4]
    test eax, eax
    jz .next
    test ecx, ecx
    jz .next
    test edx, edx
    jz .next
    test r8d, r8d
    jz .next
    mov [rsp + N_CELL + UgfxScale_dst_w], eax
    mov [rsp + N_CELL + UgfxScale_w], eax
    mov [rsp + N_CELL + UgfxScale_dst_h], ecx
    mov [rsp + N_CELL + UgfxScale_h], ecx
    mov [rsp + N_CELL + UgfxScale_src_w], edx
    mov [rsp + N_CELL + UgfxScale_src_h], r8d
    mov eax, [rbx + UgfxNine_y]         ; its first pixel in the destination
    add eax, [rsp + N_DY + r12 * 4]
    imul rax, [rbx + UgfxNine_dst_stride]
    mov ecx, [rbx + UgfxNine_x]
    add ecx, [rsp + N_DX + r13 * 4]
    lea rax, [rax + rcx * 4]
    add rax, [rbx + UgfxNine_dst]
    mov [rsp + N_CELL + UgfxScale_dst], rax
    mov eax, [rsp + N_SY + r12 * 4]     ; and in the source
    imul rax, [rbx + UgfxNine_src_stride]
    mov ecx, [rsp + N_SX + r13 * 4]
    lea rax, [rax + rcx * 4]
    add rax, [rbx + UgfxNine_src]
    mov [rsp + N_CELL + UgfxScale_src], rax
    lea rdi, [rsp + N_CELL]
    call scale_nearest_rect
.next:
    inc r13d
    cmp r13d, 3
    jb .cell
    inc r12d
    cmp r12d, 3
    jb .row
    xor eax, eax
.out:
    add rsp, N_FRAME
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global ninepatch_version
ninepatch_version: dq 0x010000
