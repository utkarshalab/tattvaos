; ============================================================================
; Scale — Nearest Neighbor and Bilinear Scaling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/color.inc"

section .text

; ---------------------------------------------------------------------------
; scale_nearest
;   Nearest neighbor scaling
;   IN:  rdi = dst, rsi = src, rdx = src_w, rcx = src_h, r8 = src_stride
;        r9 = dst_w, r10 = dst_h, r11 = dst_stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_nearest
scale_nearest:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Compute scale factors (fixed point 16.16)
    mov rax, r13
    shl rax, 16
    div r9
    mov r13, rax          ; x_scale

    mov rax, r14
    shl rax, 16
    div r10
    mov r14, rax          ; y_scale

    test r9, r9
    jz .done
    test r10, r10
    jz .done

.row_loop:
    push r10
    push rbx
    push r12
    mov r10, r9

    ; Compute src_y
    mov rax, r15
    mul r14
    shr rax, 16
    mov rsi, [rsp + 24]   ; src base
    imul rax, [rsp + 32]  ; src_stride
    add rsi, rax

.pixel_loop:
    ; Compute src_x
    mov rax, r10
    mul r13
    shr rax, 16
    mov ecx, [rsi + rax * 4]
    mov [rbx], ecx
    add rbx, 4
    dec r10
    jnz .pixel_loop

    pop r12
    pop rbx
    pop r10
    add rbx, r11
    dec r15
    jnz .row_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

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
