; ============================================================================
; Scale — Nearest Neighbor and Bilinear Scaling
; ============================================================================

%include "ugfx.inc"

section .text

; ---------------------------------------------------------------------------
; scale_nearest
;   Nearest neighbour scaling of a whole image
;   IN:  rdi = dst, rsi = src, rdx = src_w, rcx = src_h, r8 = src_stride
;        r9 = dst_w, r10 = dst_h, r11 = dst_stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_nearest
scale_nearest:
    sub rsp, UgfxScale_SIZE + 8         ; a job; 16-byte aligned
    mov [rsp + UgfxScale_dst], rdi
    mov [rsp + UgfxScale_dst_stride], r11
    mov [rsp + UgfxScale_dst_w], r9d
    mov [rsp + UgfxScale_dst_h], r10d
    mov [rsp + UgfxScale_src], rsi
    mov [rsp + UgfxScale_src_stride], r8
    mov [rsp + UgfxScale_src_w], edx
    mov [rsp + UgfxScale_src_h], ecx
    mov dword [rsp + UgfxScale_x], 0
    mov dword [rsp + UgfxScale_y], 0
    mov [rsp + UgfxScale_w], r9d
    mov [rsp + UgfxScale_h], r10d
    mov rdi, rsp
    call scale_nearest_rect
    add rsp, UgfxScale_SIZE + 8
    ret

; ---------------------------------------------------------------------------
; scale_nearest_rect
;   Part of a nearest neighbour scale: each destination pixel (x, y) of the
;   rectangle takes the source pixel (x * src_w / dst_w, y * src_h / dst_h),
;   in whole numbers, stepped by quotient and remainder so there is no
;   division per pixel. Nothing for an empty source or destination.
;   IN:  rdi = UgfxScale job
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_nearest_rect
scale_nearest_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40                         ; locals; 16-byte aligned
%define L_QX    0                       ; src_w / dst_w, and the remainder
%define L_RX    4
%define L_X0    8                       ; the first column's source x, and
%define L_EX0   12                      ; how far it is into the next
%define L_ROWS  16
    mov rbx, rdi
    mov ecx, [rbx + UgfxScale_dst_w]
    test ecx, ecx
    jz .done
    cmp dword [rbx + UgfxScale_dst_h], 0
    je .done
    cmp dword [rbx + UgfxScale_src_w], 0
    je .done
    cmp dword [rbx + UgfxScale_src_h], 0
    je .done
    mov eax, [rbx + UgfxScale_src_w]    ; along x
    xor edx, edx
    div ecx
    mov [rsp + L_QX], eax
    mov [rsp + L_RX], edx
    mov eax, [rbx + UgfxScale_x]        ; where the first column starts
    mul dword [rbx + UgfxScale_src_w]
    div dword [rbx + UgfxScale_dst_w]
    mov [rsp + L_X0], eax
    mov [rsp + L_EX0], edx
    mov eax, [rbx + UgfxScale_y]        ; and the first row: r12d = source y,
    mul dword [rbx + UgfxScale_src_h]   ; r13d how far into the next
    div dword [rbx + UgfxScale_dst_h]
    mov r12d, eax
    mov r13d, edx
    mov eax, [rbx + UgfxScale_h]
    mov [rsp + L_ROWS], eax
    movsxd r14, dword [rbx + UgfxScale_y]   ; the destination row
    imul r14, [rbx + UgfxScale_dst_stride]
    add r14, [rbx + UgfxScale_dst]
    movsxd rax, dword [rbx + UgfxScale_x]
    lea r14, [r14 + rax * 4]
.row:
    cmp dword [rsp + L_ROWS], 0
    jle .done
    mov eax, r12d                       ; the source row
    imul rax, [rbx + UgfxScale_src_stride]
    mov r15, [rbx + UgfxScale_src]
    add r15, rax
    mov rdi, r14
    mov ecx, [rbx + UgfxScale_w]
    mov esi, [rsp + L_X0]               ; source x, and its remainder
    mov edx, [rsp + L_EX0]
    mov r8d, [rsp + L_QX]
    mov r9d, [rsp + L_RX]
    mov r10d, [rbx + UgfxScale_dst_w]
.pixel:
    test ecx, ecx
    jle .row_done
    mov eax, [r15 + rsi * 4]
    mov [rdi], eax
    add rdi, 4
    add esi, r8d
    add edx, r9d
    cmp edx, r10d
    jb .no_carry
    sub edx, r10d
    inc esi
.no_carry:
    dec ecx
    jmp .pixel
.row_done:
    add r14, [rbx + UgfxScale_dst_stride]
    mov eax, [rbx + UgfxScale_src_h]    ; the next row's source y
    xor edx, edx
    div dword [rbx + UgfxScale_dst_h]
    add r12d, eax
    add r13d, edx
    cmp r13d, [rbx + UgfxScale_dst_h]
    jb .row_kept
    sub r13d, [rbx + UgfxScale_dst_h]
    inc r12d
.row_kept:
    dec dword [rsp + L_ROWS]
    jmp .row
.done:
    xor eax, eax
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; scale_bilinear
;   Bilinear scaling of a whole image
;   IN:  rdi = dst, rsi = src, rdx = src_w, rcx = src_h, r8 = src_stride
;        r9 = dst_w, r10 = dst_h, r11 = dst_stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_bilinear
scale_bilinear:
    sub rsp, UgfxScale_SIZE + 8         ; a job; 16-byte aligned
    mov [rsp + UgfxScale_dst], rdi
    mov [rsp + UgfxScale_dst_stride], r11
    mov [rsp + UgfxScale_dst_w], r9d
    mov [rsp + UgfxScale_dst_h], r10d
    mov [rsp + UgfxScale_src], rsi
    mov [rsp + UgfxScale_src_stride], r8
    mov [rsp + UgfxScale_src_w], edx
    mov [rsp + UgfxScale_src_h], ecx
    mov dword [rsp + UgfxScale_x], 0
    mov dword [rsp + UgfxScale_y], 0
    mov [rsp + UgfxScale_w], r9d
    mov [rsp + UgfxScale_h], r10d
    mov rdi, rsp
    call scale_bilinear_rect
    add rsp, UgfxScale_SIZE + 8
    ret

; %1 = p, made the blend; %2 = q; %3 = q's share of 256 (0-255).
; Two channels at a time in each half; uses ecx, edx, edi, esi.
%macro LERP 3
    mov edi, 256
    sub edi, %3
    mov ecx, %1
    and ecx, 0x00FF00FF
    imul ecx, edi
    mov edx, %2
    and edx, 0x00FF00FF
    imul edx, %3
    add ecx, edx
    shr ecx, 8
    and ecx, 0x00FF00FF
    mov edx, %1
    shr edx, 8
    and edx, 0x00FF00FF
    imul edx, edi
    mov esi, %2
    shr esi, 8
    and esi, 0x00FF00FF
    imul esi, %3
    add edx, esi
    and edx, 0xFF00FF00
    or ecx, edx
    mov %1, ecx
%endmacro

; ---------------------------------------------------------------------------
; scale_bilinear_rect
;   Part of a bilinear scale: each destination pixel of the rectangle blends
;   the four source pixels around its centre's place in the source (pixel
;   centres matched, edges held), with 8-bit weights, every channel alike.
;   The place steps by a 16.16 increment worked out once. Nothing for an
;   empty source or destination.
;   IN:  rdi = UgfxScale job
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_bilinear_rect
scale_bilinear_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 72                         ; locals; 16-byte aligned
%define B_SX    0                       ; source steps per destination pixel
%define B_SY    8
%define B_PX0   16                      ; the first column's place, 16.16
%define B_PY    24                      ; the row's place
%define B_DST   32                      ; the row's first pixel
%define B_ROWS  40
%define B_FY    44                      ; the row's weight
%define B_SWM1  48                      ; the last source column and row
%define B_SHM1  52
    mov rbx, rdi
    cmp dword [rbx + UgfxScale_dst_w], 0
    je .done
    cmp dword [rbx + UgfxScale_dst_h], 0
    je .done
    cmp dword [rbx + UgfxScale_src_w], 0
    je .done
    cmp dword [rbx + UgfxScale_src_h], 0
    je .done
    mov eax, [rbx + UgfxScale_src_w]
    dec eax
    mov [rsp + B_SWM1], eax
    mov eax, [rbx + UgfxScale_src_h]
    dec eax
    mov [rsp + B_SHM1], eax
%macro STEP 4                           ; local, source size, destination
    mov eax, [rbx + UgfxScale_%2]       ; size, the rectangle's start; the
    shl rax, 16                         ; start's place into %4
    xor edx, edx
    mov ecx, [rbx + UgfxScale_%3]
    div rcx
    mov [rsp + %1], rax
    movsxd rcx, dword [rbx + UgfxScale_%4]
    imul rcx, rax
    shr rax, 1
    add rax, rcx
    sub rax, 32768
%endmacro
    STEP B_SX, src_w, dst_w, x
    mov [rsp + B_PX0], rax
    STEP B_SY, src_h, dst_h, y
    mov [rsp + B_PY], rax
    movsxd rax, dword [rbx + UgfxScale_y]
    imul rax, [rbx + UgfxScale_dst_stride]
    add rax, [rbx + UgfxScale_dst]
    movsxd rcx, dword [rbx + UgfxScale_x]
    lea rax, [rax + rcx * 4]
    mov [rsp + B_DST], rax
    mov eax, [rbx + UgfxScale_h]
    mov [rsp + B_ROWS], eax
.row:
    cmp dword [rsp + B_ROWS], 0
    jle .done
    mov rax, [rsp + B_PY]               ; the two source rows, and the weight
    xor ecx, ecx
    test rax, rax
    cmovs rax, rcx
    mov rcx, rax
    shr rcx, 16
    shr eax, 8
    and eax, 0xFF
    mov edx, [rsp + B_SHM1]
    lea r8d, [rcx + 1]
    cmp ecx, edx
    jb .two_rows
    mov ecx, edx                        ; the last row: held
    mov r8d, edx
    xor eax, eax
.two_rows:
    mov [rsp + B_FY], eax
    mov r12, [rbx + UgfxScale_src]
    mov r13, r12
    imul rcx, [rbx + UgfxScale_src_stride]
    add r12, rcx
    imul r8, [rbx + UgfxScale_src_stride]
    add r13, r8
    mov r14, [rsp + B_DST]
    mov r15, [rsp + B_PX0]
    mov r9d, [rbx + UgfxScale_w]
    mov [rsp + 56], r9d                 ; columns left
.pixel:
    cmp dword [rsp + 56], 0
    jle .row_done
    mov rax, r15                        ; the two source columns, the weight
    xor ecx, ecx
    test rax, rax
    cmovs rax, rcx
    mov rcx, rax
    shr rcx, 16
    shr eax, 8
    and eax, 0xFF
    mov edx, [rsp + B_SWM1]
    lea esi, [rcx + 1]
    cmp ecx, edx
    jb .two_columns
    mov ecx, edx
    mov esi, edx
    xor eax, eax
.two_columns:
    mov r8d, [r12 + rcx * 4]
    mov r9d, [r12 + rsi * 4]
    mov r10d, [r13 + rcx * 4]
    mov r11d, [r13 + rsi * 4]
    LERP r8d, r9d, eax                  ; along the top row
    LERP r10d, r11d, eax                ; the bottom one
    mov eax, [rsp + B_FY]
    LERP r8d, r10d, eax                 ; between them
    mov [r14], r8d
    add r14, 4
    add r15, [rsp + B_SX]
    dec dword [rsp + 56]
    jmp .pixel
.row_done:
    mov rax, [rbx + UgfxScale_dst_stride]
    add [rsp + B_DST], rax
    mov rax, [rsp + B_SY]
    add [rsp + B_PY], rax
    dec dword [rsp + B_ROWS]
    jmp .row
.done:
    xor eax, eax
    add rsp, 72
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data

global scale_version
scale_version: dq 0x010000
