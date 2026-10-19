; VP8 fixed-point inverse transforms and pixel reconstruction.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; Internal 4-point inverse DCT. edi,esi,edx,ecx -> eax,edx,r8d,r9d.
vp8_idct_1d:
    mov r10d,edx
    mov r11d,ecx
    mov r8d,edi
    add r8d,r10d                      ; a
    mov r9d,edi
    sub r9d,r10d                      ; b
    mov eax,esi
    imul eax,35468
    sar eax,16
    mov edx,r11d
    imul edx,20091
    sar edx,16
    add edx,r11d
    sub eax,edx                       ; c
    mov r10d,eax
    mov eax,esi
    imul eax,20091
    sar eax,16
    add eax,esi
    mov edx,r11d
    imul edx,35468
    sar edx,16
    add eax,edx                       ; d
    mov edx,r9d
    add edx,r10d                      ; out1
    mov r11d,r8d
    sub r11d,eax                      ; out3
    add eax,r8d                       ; out0
    ; out2 is b-c; c is out1-b.
    mov r8d,r9d
    add r8d,r9d
    sub r8d,edx
    mov r9d,r11d
    ret

; input[16] int16,output[16] int16.
global webp_vp8_idct4x4
webp_vp8_idct4x4:
    PROLOGUE_SAVE rbx,r12,r13,r14
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .idct_bad
    test r12,r12
    jz .idct_bad
    xor r13d,r13d
.idct_column:
    movsx edi,word [rbx+r13*2]
    movsx esi,word [rbx+r13*2+8]
    movsx edx,word [rbx+r13*2+16]
    movsx ecx,word [rbx+r13*2+24]
    call vp8_idct_1d
    mov [rsp+r13*2],ax
    mov [rsp+r13*2+8],dx
    mov [rsp+r13*2+16],r8w
    mov [rsp+r13*2+24],r9w
    inc r13d
    cmp r13d,4
    jb .idct_column
    xor r13d,r13d
.idct_row:
    lea r14,[rsp+r13*8]
    movsx edi,word [r14]
    movsx esi,word [r14+2]
    movsx edx,word [r14+4]
    movsx ecx,word [r14+6]
    call vp8_idct_1d
    add eax,4
    sar eax,3
    add edx,4
    sar edx,3
    add r8d,4
    sar r8d,3
    add r9d,4
    sar r9d,3
    mov [r12+r13*8],ax
    mov [r12+r13*8+2],dx
    mov [r12+r13*8+4],r8w
    mov [r12+r13*8+6],r9w
    inc r13d
    cmp r13d,4
    jb .idct_row
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14
.idct_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14

; Internal WHT: edi,esi,edx,ecx -> eax,edx,r8d,r9d.
vp8_wht_1d:
    mov r8d,edi
    add r8d,ecx                       ; a
    mov r9d,esi
    add r9d,edx                       ; b
    mov r10d,esi
    sub r10d,edx                      ; c
    sub edi,ecx                       ; d
    mov eax,r8d
    add eax,r9d
    mov edx,r10d
    add edx,edi
    sub r8d,r9d
    sub edi,r10d
    mov r9d,edi
    ret

; input[16] int16,output[16] int16.
global webp_vp8_iwht4x4
webp_vp8_iwht4x4:
    PROLOGUE_SAVE rbx,r12,r13,r14
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .wht_bad
    test r12,r12
    jz .wht_bad
    xor r13d,r13d
.wht_column:
    movsx edi,word [rbx+r13*2]
    movsx esi,word [rbx+r13*2+8]
    movsx edx,word [rbx+r13*2+16]
    movsx ecx,word [rbx+r13*2+24]
    call vp8_wht_1d
    mov [rsp+r13*2],ax
    mov [rsp+r13*2+8],dx
    mov [rsp+r13*2+16],r8w
    mov [rsp+r13*2+24],r9w
    inc r13d
    cmp r13d,4
    jb .wht_column
    xor r13d,r13d
.wht_row:
    lea r14,[rsp+r13*8]
    movsx edi,word [r14]
    movsx esi,word [r14+2]
    movsx edx,word [r14+4]
    movsx ecx,word [r14+6]
    call vp8_wht_1d
    add eax,3
    sar eax,3
    add edx,3
    sar edx,3
    add r8d,3
    sar r8d,3
    add r9d,3
    sar r9d,3
    mov [r12+r13*8],ax
    mov [r12+r13*8+2],dx
    mov [r12+r13*8+4],r8w
    mov [r12+r13*8+6],r9w
    inc r13d
    cmp r13d,4
    jb .wht_row
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14
.wht_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14

; dst,stride,predict,predict_stride,residual[16] -> 0/-EINVAL.
global webp_vp8_add_block
webp_vp8_add_block:
    test rdi,rdi
    jz .add_bad
    test rdx,rdx
    jz .add_bad
    test r8,r8
    jz .add_bad
    mov r11,rcx
    xor r9d,r9d
.add_row:
    xor r10d,r10d
.add_pixel:
    movzx eax,byte [rdx+r10]
    movsx ecx,word [r8+r10*2]
    add eax,ecx
    xor ecx,ecx
    test eax,eax
    cmovs eax,ecx
    mov ecx,255
    cmp eax,ecx
    cmova eax,ecx
    mov [rdi+r10],al
    inc r10d
    cmp r10d,4
    jb .add_pixel
    add rdi,rsi
    add rdx,r11
    add r8,8
    inc r9d
    cmp r9d,4
    jb .add_row
    xor eax,eax
    ret
.add_bad:
    mov rax,-EINVAL
    ret

; WebPYUVState* -> 0/-EINVAL. Converts limited-range BT.601 YUV420.
global webp_vp8_yuv420_to_bgra
webp_vp8_yuv420_to_bgra:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    test rbx,rbx
    jz .yuv_bad
    mov r12,[rbx+WebPYUVState.y]
    mov r13,[rbx+WebPYUVState.u]
    mov r14,[rbx+WebPYUVState.v]
    mov r15,[rbx+WebPYUVState.output]
    test r12,r12
    jz .yuv_bad
    test r13,r13
    jz .yuv_bad
    test r14,r14
    jz .yuv_bad
    test r15,r15
    jz .yuv_bad
    cmp dword [rbx+WebPYUVState.width],0
    je .yuv_bad
    cmp dword [rbx+WebPYUVState.height],0
    je .yuv_bad
    mov dword [rsp],0
.yuv_row:
    mov eax,[rsp]
    cmp eax,[rbx+WebPYUVState.height]
    jae .yuv_done
    mov dword [rsp+4],0
.yuv_pixel:
    mov eax,[rsp+4]
    cmp eax,[rbx+WebPYUVState.width]
    jae .yuv_next_row
    mov edx,[rsp]
    imul edx,[rbx+WebPYUVState.y_stride]
    add edx,eax
    movzx ecx,byte [r12+rdx]
    sub ecx,16                         ; C
    jns .c_ready
    xor ecx,ecx
.c_ready:
    mov edx,[rsp]
    shr edx,1
    imul edx,[rbx+WebPYUVState.uv_stride]
    mov eax,[rsp+4]
    shr eax,1
    add edx,eax
    movzx eax,byte [r13+rdx]
    sub eax,128                        ; D
    mov [rsp+8],eax
    movzx edx,byte [r14+rdx]
    sub edx,128                        ; E
    mov [rsp+12],edx
    imul ecx,298
    mov eax,[rsp+12]
    imul eax,409
    lea eax,[rcx+rax+128]
    sar eax,8
    call .clamp
    mov r8d,eax                        ; R
    mov eax,[rsp+8]
    imul eax,-100
    mov edx,[rsp+12]
    imul edx,-208
    add eax,edx
    lea eax,[rcx+rax+128]
    sar eax,8
    call .clamp
    mov r9d,eax                        ; G
    mov eax,[rsp+8]
    imul eax,516
    lea eax,[rcx+rax+128]
    sar eax,8
    call .clamp
    mov edx,[rsp]
    imul edx,[rbx+WebPYUVState.output_stride]
    mov ecx,[rsp+4]
    lea rdx,[r15+rdx]
    shl ecx,2
    mov byte [rdx+rcx],al
    mov byte [rdx+rcx+1],r9b
    mov byte [rdx+rcx+2],r8b
    mov byte [rdx+rcx+3],0xff
    inc dword [rsp+4]
    jmp .yuv_pixel
.yuv_next_row:
    inc dword [rsp]
    jmp .yuv_row
.yuv_done:
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.yuv_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.clamp:
    test eax,eax
    jns .clamp_high
    xor eax,eax
    ret
.clamp_high:
    cmp eax,255
    jbe .clamp_done
    mov eax,255
.clamp_done:
    ret

section .data
global webp_vp8_recon_version
webp_vp8_recon_version: dq 0x010000
