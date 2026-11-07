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
;   Bilinear scaling with per-channel 16.16 interpolation
; ---------------------------------------------------------------------------
global scale_bilinear
scale_bilinear:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,64
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    mov [rsp],r9
    mov [rsp+8],r10
    mov [rsp+16],r11
    test r9,r9
    jz .bdone
    test r10,r10
    jz .bdone
    xor r8d,r8d
.by:
    cmp r8,[rsp+8]
    jae .bdone
    mov rax,r8
    imul rax,r14
    shl rax,16
    xor edx,edx
    div qword [rsp+8]
    mov r9,rax
    shr rax,16
    cmp rax,r14
    jb .yok
    lea rax,[r14-1]
.yok:
    mov [rsp+24],rax
    mov rcx,rax
    inc rcx
    cmp rcx,r14
    cmovae rcx,rax
    mov [rsp+32],rcx
    and r9d,0xffff
    xor r10d,r10d
.bx:
    cmp r10,[rsp]
    jae .bynext
    mov rax,r10
    imul rax,r13
    shl rax,16
    xor edx,edx
    div qword [rsp]
    mov r11,rax
    shr rax,16
    cmp rax,r13
    jb .xok
    lea rax,[r13-1]
.xok:
    mov rcx,rax
    inc rcx
    cmp rcx,r13
    cmovae rcx,rax
    and r11d,0xffff
    mov rdx,[rsp+24]
    imul rdx,r15
    lea rsi,[r12+rdx]
    mov edx,[rsi+rax*4]
    mov esi,[rsi+rcx*4]
    ; Horizontal interpolation per packed byte using scalar channel loop.
    mov [rsp+40],edx
    mov [rsp+44],esi
    mov rax,[rsp+32]
    imul rax,r15
    lea rsi,[r12+rax]
    mov eax,[rsi+rcx*4]
    mov ecx,[rsi+rcx*4]
    mov [rsp+48],eax
    mov [rsp+52],ecx
    xor edx,edx
    xor esi,esi
.chan:
    movzx eax,byte [rsp+40+rsi]
    movzx ecx,byte [rsp+44+rsi]
    sub ecx,eax
    imul ecx,r11d
    sar ecx,16
    add eax,ecx
    mov ecx,eax
    movzx eax,byte [rsp+48+rsi]
    movzx edi,byte [rsp+52+rsi]
    sub edi,eax
    imul edi,r11d
    sar edi,16
    add eax,edi
    sub eax,ecx
    imul eax,r9d
    sar eax,16
    add eax,ecx
    mov [rsp+56+rsi],al
    inc esi
    cmp esi,4
    jb .chan
    mov rax,r8
    imul rax,[rsp+16]
    lea rdi,[rbx+rax]
    mov eax,[rsp+56]
    mov [rdi+r10*4],eax
    inc r10
    jmp .bx
.bynext:
    inc r8
    jmp .by
.bdone:
    xor eax,eax
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data

global scale_version
scale_version: dq 0x010000
