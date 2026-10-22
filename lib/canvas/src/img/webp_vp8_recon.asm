; VP8 fixed-point inverse transforms and pixel reconstruction.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern arena_alloc
extern webp_vp8_quant_factors
extern webp_vp8_dequant_macroblock

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

; WebPVP8ReconstructState* -> 0/-EINVAL. Prediction must already be present.
global webp_vp8_reconstruct_macroblock
webp_vp8_reconstruct_macroblock:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,64
    mov rbx,rdi
    test rbx,rbx
    jz .mb_recon_bad
    mov r12,[rbx+WebPVP8ReconstructState.y]
    mov r13,[rbx+WebPVP8ReconstructState.u]
    mov r14,[rbx+WebPVP8ReconstructState.v]
    mov r15,[rbx+WebPVP8ReconstructState.coeffs]
    test r12,r12
    jz .mb_recon_bad
    test r13,r13
    jz .mb_recon_bad
    test r14,r14
    jz .mb_recon_bad
    test r15,r15
    jz .mb_recon_bad
    cmp dword [rbx+WebPVP8ReconstructState.y_stride],16
    jb .mb_recon_bad
    cmp dword [rbx+WebPVP8ReconstructState.uv_stride],8
    jb .mb_recon_bad
    mov dword [rsp+48],0
.mb_y:
    mov eax,[rsp+48]
    mov edx,eax
    and edx,3
    shl edx,2
    shr eax,2
    shl eax,2
    imul eax,[rbx+WebPVP8ReconstructState.y_stride]
    add eax,edx
    lea rdi,[r12+rax]
    mov esi,[rbx+WebPVP8ReconstructState.y_stride]
    mov eax,[rsp+48]
    shl eax,5
    lea rdx,[r15+rax]
    call .mb_one
    test eax,eax
    js .mb_recon_bad
    inc dword [rsp+48]
    cmp dword [rsp+48],16
    jb .mb_y
    mov dword [rsp+48],16
.mb_uv:
    mov eax,[rsp+48]
    mov ecx,eax
    sub ecx,16
    cmp ecx,4
    jb .mb_u_plane
    sub ecx,4
    mov rdi,r14
    jmp .mb_uv_pos
.mb_u_plane:
    mov rdi,r13
.mb_uv_pos:
    mov edx,ecx
    and edx,1
    shl edx,2
    shr ecx,1
    shl ecx,2
    imul ecx,[rbx+WebPVP8ReconstructState.uv_stride]
    add ecx,edx
    add rdi,rcx
    mov esi,[rbx+WebPVP8ReconstructState.uv_stride]
    shl eax,5
    lea rdx,[r15+rax]
    call .mb_one
    test eax,eax
    js .mb_recon_bad
    inc dword [rsp+48]
    cmp dword [rsp+48],24
    jb .mb_uv
    xor eax,eax
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.mb_recon_bad:
    mov rax,-EINVAL
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.mb_one:
    mov [rsp+48],rdi
    mov [rsp+44],esi
    mov rdi,rdx
    lea rsi,[rsp+8]
    call webp_vp8_idct4x4
    test eax,eax
    js .mb_one_done
    mov rdi,[rsp+48]
    mov esi,[rsp+44]
    mov rdx,rdi
    mov ecx,esi
    lea r8,[rsp+8]
    call webp_vp8_add_block
.mb_one_done:
    ret

; WebPVP8PredictMBState* -> 0/-EINVAL. Planes include a valid top/left border.
global webp_vp8_predict_macroblock
webp_vp8_predict_macroblock:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,48
    mov rbx,rdi
    test rbx,rbx
    jz .pmb_bad
    mov r12,[rbx+WebPVP8PredictMBState.y]
    mov r13,[rbx+WebPVP8PredictMBState.u]
    mov r14,[rbx+WebPVP8PredictMBState.v]
    mov r15,[rbx+WebPVP8PredictMBState.header]
    test r12,r12
    jz .pmb_bad
    test r13,r13
    jz .pmb_bad
    test r14,r14
    jz .pmb_bad
    test r15,r15
    jz .pmb_bad
    cmp dword [rbx+WebPVP8PredictMBState.y_stride],16
    jb .pmb_bad
    cmp dword [rbx+WebPVP8PredictMBState.uv_stride],8
    jb .pmb_bad
    mov eax,[r15+WebPVP8MBHeader.y_mode]
    cmp eax,VP8_Y_MODE_B_PRED
    je .pmb_bpred
    cmp eax,3
    ja .pmb_bad
    xor ecx,ecx
.pmb_y_left:
    mov eax,ecx
    imul eax,[rbx+WebPVP8PredictMBState.y_stride]
    mov al,[r12+rax-1]
    mov [rsp+rcx],al
    inc ecx
    cmp ecx,16
    jb .pmb_y_left
    mov rdi,r12
    mov esi,[rbx+WebPVP8PredictMBState.y_stride]
    mov rdx,r12
    sub rdx,rsi
    lea rcx,[rsp]
    mov r8d,16
    mov r9d,[r15+WebPVP8MBHeader.y_mode]
    movzx eax,byte [rdx-1]
    push rax
    call webp_vp8_predict_block
    add rsp,8
    test eax,eax
    js .pmb_bad
    jmp .pmb_uv
.pmb_bpred:
    mov dword [rsp+32],0
.pmb_bnext:
    mov eax,[rsp+32]
    mov ecx,eax
    and ecx,3
    shl ecx,2
    shr eax,2
    shl eax,2
    imul eax,[rbx+WebPVP8PredictMBState.y_stride]
    add eax,ecx
    lea rdi,[r12+rax]
    mov esi,[rbx+WebPVP8PredictMBState.y_stride]
    mov rdx,rdi
    sub rdx,rsi
    xor ecx,ecx
.pmb_b_left:
    mov eax,ecx
    imul eax,esi
    mov al,[rdi+rax-1]
    mov [rsp+16+rcx],al
    inc ecx
    cmp ecx,4
    jb .pmb_b_left
    lea rcx,[rsp+16]
    mov eax,[rsp+32]
    movzx r8d,byte [r15+WebPVP8MBHeader.b_modes+rax]
    call webp_vp8_predict4x4
    test eax,eax
    js .pmb_bad
    inc dword [rsp+32]
    cmp dword [rsp+32],16
    jb .pmb_bnext
.pmb_uv:
    mov dword [rsp+32],0
.pmb_uv_plane:
    cmp dword [rsp+32],0
    jne .pmb_v_plane
    mov r12,r13
    jmp .pmb_uv_ready
.pmb_v_plane:
    mov r12,r14
.pmb_uv_ready:
    xor ecx,ecx
.pmb_uv_left:
    mov eax,ecx
    imul eax,[rbx+WebPVP8PredictMBState.uv_stride]
    mov al,[r12+rax-1]
    mov [rsp+rcx],al
    inc ecx
    cmp ecx,8
    jb .pmb_uv_left
    mov rdi,r12
    mov esi,[rbx+WebPVP8PredictMBState.uv_stride]
    mov rdx,r12
    sub rdx,rsi
    lea rcx,[rsp]
    mov r8d,8
    mov r9d,[r15+WebPVP8MBHeader.uv_mode]
    movzx eax,byte [rdx-1]
    push rax
    call webp_vp8_predict_block
    add rsp,8
    test eax,eax
    js .pmb_bad
    inc dword [rsp+32]
    cmp dword [rsp+32],2
    jb .pmb_uv_plane
    xor eax,eax
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.pmb_bad:
    mov rax,-EINVAL
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; arena,width,height,WebPVP8FramePlanes* -> 0/-EINVAL/-ENOMEM.
; Allocates padded macroblock planes with VP8's 127 top and 129 left borders.
global webp_vp8_alloc_frame_planes
webp_vp8_alloc_frame_planes:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12d,esi
    mov r13d,edx
    mov r14,rcx
    test rbx,rbx
    jz .planes_bad
    test r12d,r12d
    jz .planes_bad
    test r13d,r13d
    jz .planes_bad
    test r14,r14
    jz .planes_bad
    cmp r12d,16383
    ja .planes_bad
    cmp r13d,16383
    ja .planes_bad
    lea eax,[r12+15]
    and eax,-16
    mov [r14+WebPVP8FramePlanes.coded_width],eax
    lea edx,[r13+15]
    and edx,-16
    mov [r14+WebPVP8FramePlanes.coded_height],edx
    lea ecx,[rax+9]
    mov [r14+WebPVP8FramePlanes.y_stride],ecx
    mov eax,[r14+WebPVP8FramePlanes.coded_width]
    shr eax,1
    add eax,9
    mov [r14+WebPVP8FramePlanes.uv_stride],eax
    mov eax,[r14+WebPVP8FramePlanes.coded_height]
    inc eax
    imul rax,rcx
    mov [rsp],rax
    mov rdi,rbx
    mov rsi,rax
    call arena_alloc
    test rax,rax
    jle .planes_nomem
    mov r15,rax
    mov rdi,rax
    mov al,127
    mov rcx,[rsp]
    rep stosb
    mov ecx,[r14+WebPVP8FramePlanes.y_stride]
    lea rax,[r15+rcx+1]
    mov [r14+WebPVP8FramePlanes.y],rax
    mov edx,[r14+WebPVP8FramePlanes.coded_height]
    inc edx
    mov rdi,r15
.planes_y_left:
    mov byte [rdi],129
    add rdi,rcx
    dec edx
    jnz .planes_y_left
    mov eax,[r14+WebPVP8FramePlanes.coded_height]
    shr eax,1
    inc eax
    mov ecx,[r14+WebPVP8FramePlanes.uv_stride]
    imul rax,rcx
    mov [rsp+8],rax
    mov rdi,rbx
    mov rsi,rax
    call arena_alloc
    test rax,rax
    jle .planes_nomem
    mov r12,rax
    mov rdi,rax
    mov al,127
    mov rcx,[rsp+8]
    rep stosb
    mov ecx,[r14+WebPVP8FramePlanes.uv_stride]
    lea rax,[r12+rcx+1]
    mov [r14+WebPVP8FramePlanes.u],rax
    mov eax,[r14+WebPVP8FramePlanes.coded_height]
    shr eax,1
    inc eax
    mov rdi,r12
.planes_u_left:
    mov byte [rdi],129
    add rdi,rcx
    dec eax
    jnz .planes_u_left
    mov rdi,rbx
    mov rsi,[rsp+8]
    call arena_alloc
    test rax,rax
    jle .planes_nomem
    mov r13,rax
    mov rdi,rax
    mov al,127
    mov rcx,[rsp+8]
    rep stosb
    mov ecx,[r14+WebPVP8FramePlanes.uv_stride]
    lea rax,[r13+rcx+1]
    mov [r14+WebPVP8FramePlanes.v],rax
    mov eax,[r14+WebPVP8FramePlanes.coded_height]
    shr eax,1
    inc eax
    mov rdi,r13
.planes_v_left:
    mov byte [rdi],129
    add rdi,rcx
    dec eax
    jnz .planes_v_left
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.planes_nomem:
    mov rax,-ENOMEM
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.planes_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; WebPVP8RenderMBState* -> 0/-EINVAL. Dequantizes, predicts, and reconstructs.
global webp_vp8_render_macroblock
webp_vp8_render_macroblock:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,112
    mov rbx,rdi
    test rbx,rbx
    jz .render_bad
    mov r12,[rbx+WebPVP8RenderMBState.config]
    mov r13,[rbx+WebPVP8RenderMBState.header]
    mov r14,[rbx+WebPVP8RenderMBState.coeffs]
    mov r15,[rbx+WebPVP8RenderMBState.y]
    test r12,r12
    jz .render_bad
    test r13,r13
    jz .render_bad
    test r14,r14
    jz .render_bad
    test r15,r15
    jz .render_bad
    cmp qword [rbx+WebPVP8RenderMBState.u],0
    je .render_bad
    cmp qword [rbx+WebPVP8RenderMBState.v],0
    je .render_bad
    mov rdi,r12
    mov esi,[r13+WebPVP8MBHeader.segment_id]
    lea rdx,[rsp]
    call webp_vp8_quant_factors
    test eax,eax
    js .render_bad
    mov rdi,r14
    lea rsi,[rsp]
    mov edx,[r13+WebPVP8MBHeader.y_mode]
    call webp_vp8_dequant_macroblock
    test eax,eax
    js .render_bad
    lea rdi,[rsp+16]
    mov [rdi+WebPVP8PredictMBState.y],r15
    mov rax,[rbx+WebPVP8RenderMBState.u]
    mov [rdi+WebPVP8PredictMBState.u],rax
    mov rax,[rbx+WebPVP8RenderMBState.v]
    mov [rdi+WebPVP8PredictMBState.v],rax
    mov [rdi+WebPVP8PredictMBState.header],r13
    mov eax,[rbx+WebPVP8RenderMBState.y_stride]
    mov [rdi+WebPVP8PredictMBState.y_stride],eax
    mov eax,[rbx+WebPVP8RenderMBState.uv_stride]
    mov [rdi+WebPVP8PredictMBState.uv_stride],eax
    call webp_vp8_predict_macroblock
    test eax,eax
    js .render_bad
    lea rdi,[rsp+64]
    mov [rdi+WebPVP8ReconstructState.y],r15
    mov rax,[rbx+WebPVP8RenderMBState.u]
    mov [rdi+WebPVP8ReconstructState.u],rax
    mov rax,[rbx+WebPVP8RenderMBState.v]
    mov [rdi+WebPVP8ReconstructState.v],rax
    mov [rdi+WebPVP8ReconstructState.coeffs],r14
    mov eax,[rbx+WebPVP8RenderMBState.y_stride]
    mov [rdi+WebPVP8ReconstructState.y_stride],eax
    mov eax,[rbx+WebPVP8RenderMBState.uv_stride]
    mov [rdi+WebPVP8ReconstructState.uv_stride],eax
    call webp_vp8_reconstruct_macroblock
    test eax,eax
    js .render_bad
    xor eax,eax
    add rsp,112
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.render_bad:
    mov rax,-EINVAL
    add rsp,112
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

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

; dst,stride,above,left,size,mode,top_left -> 0/-EINVAL.
; Interior VP8 predictors: mode 0=DC, 1=vertical, 2=horizontal, 3=true-motion.
global webp_vp8_predict_block
webp_vp8_predict_block:
    mov r11d,[rsp+8]
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx
    mov r14,rcx
    mov r15d,r8d
    test rbx,rbx
    jz .predict_bad
    test r13,r13
    jz .predict_bad
    test r14,r14
    jz .predict_bad
    test r12d,r12d
    jz .predict_bad
    cmp r15d,4
    je .predict_size_ok
    cmp r15d,8
    je .predict_size_ok
    cmp r15d,16
    jne .predict_bad
.predict_size_ok:
    cmp r9d,3
    ja .predict_bad
    test r9d,r9d
    jz .predict_dc
    cmp r9d,1
    je .predict_vertical
    cmp r9d,2
    je .predict_horizontal
    xor r8d,r8d
.predict_tm_row:
    xor r10d,r10d
.predict_tm_pixel:
    movzx eax,byte [r14+r8]
    movzx edx,byte [r13+r10]
    add eax,edx
    sub eax,r11d
    xor edx,edx
    test eax,eax
    cmovs eax,edx
    mov edx,255
    cmp eax,edx
    cmova eax,edx
    mov [rbx+r10],al
    inc r10d
    cmp r10d,r15d
    jb .predict_tm_pixel
    add rbx,r12
    inc r8d
    cmp r8d,r15d
    jb .predict_tm_row
    jmp .predict_ok
.predict_dc:
    xor eax,eax
    xor r8d,r8d
.predict_dc_sum:
    movzx edx,byte [r13+r8]
    add eax,edx
    movzx edx,byte [r14+r8]
    add eax,edx
    inc r8d
    cmp r8d,r15d
    jb .predict_dc_sum
    add eax,r15d
    lea ecx,[r15*2]
    xor edx,edx
    div ecx
    mov edx,eax
    xor r8d,r8d
.predict_dc_row:
    xor r10d,r10d
.predict_dc_pixel:
    mov [rbx+r10],dl
    inc r10d
    cmp r10d,r15d
    jb .predict_dc_pixel
    add rbx,r12
    inc r8d
    cmp r8d,r15d
    jb .predict_dc_row
    jmp .predict_ok
.predict_vertical:
    xor r8d,r8d
.predict_v_row:
    xor r10d,r10d
.predict_v_pixel:
    mov al,[r13+r10]
    mov [rbx+r10],al
    inc r10d
    cmp r10d,r15d
    jb .predict_v_pixel
    add rbx,r12
    inc r8d
    cmp r8d,r15d
    jb .predict_v_row
    jmp .predict_ok
.predict_horizontal:
    xor r8d,r8d
.predict_h_row:
    mov al,[r14+r8]
    xor r10d,r10d
.predict_h_pixel:
    mov [rbx+r10],al
    inc r10d
    cmp r10d,r15d
    jb .predict_h_pixel
    add rbx,r12
    inc r8d
    cmp r8d,r15d
    jb .predict_h_row
.predict_ok:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.predict_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; dst,stride,above(A0),left(L0),bmode(DC/TM/VE/HE) -> 0/-EINVAL.
global webp_vp8_predict4x4
webp_vp8_predict4x4:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx
    mov r14,rcx
    mov r15d,r8d
    test rbx,rbx
    jz .p4_bad
    test r13,r13
    jz .p4_bad
    test r14,r14
    jz .p4_bad
    cmp r15d,VP8_BMODE_HU
    ja .p4_bad
    cmp r15d,VP8_BMODE_VR
    jae .p4_diagonal
    cmp r15d,VP8_BMODE_RD
    je .p4_rd
    cmp r15d,VP8_BMODE_LD
    je .p4_ld
    cmp r15d,VP8_BMODE_VE
    je .p4_vertical
    cmp r15d,VP8_BMODE_HE
    je .p4_horizontal
    mov rdi,rbx
    mov esi,r12d
    mov rdx,r13
    mov rcx,r14
    mov r8d,4
    xor r9d,r9d
    test r15d,r15d
    jz .p4_basic
    mov r9d,3
.p4_basic:
    movzx eax,byte [r13-1]
    push rax
    call webp_vp8_predict_block
    add rsp,8
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.p4_vertical:
    xor r8d,r8d
.p4_v_col:
    movzx eax,byte [r13+r8-1]
    movzx edx,byte [r13+r8]
    lea eax,[rax+rdx*2+2]
    movzx edx,byte [r13+r8+1]
    add eax,edx
    shr eax,2
    mov [rbx+r8],al
    lea r10,[rbx+r12]
    mov [r10+r8],al
    lea r10,[rbx+r12*2]
    mov [r10+r8],al
    add r10,r12
    mov [r10+r8],al
    inc r8d
    cmp r8d,4
    jb .p4_v_col
    jmp .p4_ok
.p4_horizontal:
    xor r8d,r8d
.p4_h_row:
    test r8d,r8d
    jz .p4_h_top
    movzx eax,byte [r14+r8-1]
    jmp .p4_h_center
.p4_h_top:
    movzx eax,byte [r13-1]
.p4_h_center:
    movzx edx,byte [r14+r8]
    lea eax,[rax+rdx*2+2]
    cmp r8d,3
    je .p4_h_bottom
    movzx edx,byte [r14+r8+1]
    jmp .p4_h_finish
.p4_h_bottom:
    movzx edx,byte [r14+3]
.p4_h_finish:
    add eax,edx
    shr eax,2
    mov edx,eax
    mov eax,r8d
    imul eax,r12d
    lea r10,[rbx+rax]
    mov [r10],dl
    mov [r10+1],dl
    mov [r10+2],dl
    mov [r10+3],dl
    inc r8d
    cmp r8d,4
    jb .p4_h_row
    jmp .p4_ok
.p4_ld:
    xor r8d,r8d
.p4_ld_row:
    xor r9d,r9d
.p4_ld_pixel:
    lea eax,[r8+r9+1]
    cmp eax,7
    je .p4_ld_edge
    movzx edx,byte [r13+rax-1]
    movzx ecx,byte [r13+rax]
    lea edx,[rdx+rcx*2+2]
    movzx ecx,byte [r13+rax+1]
    add edx,ecx
    jmp .p4_ld_store
.p4_ld_edge:
    movzx edx,byte [r13+6]
    movzx ecx,byte [r13+7]
    lea edx,[rdx+rcx*2+2]
    add edx,ecx
.p4_ld_store:
    shr edx,2
    mov eax,r8d
    imul eax,r12d
    lea r10,[rbx+rax]
    mov [r10+r9],dl
    inc r9d
    cmp r9d,4
    jb .p4_ld_pixel
    inc r8d
    cmp r8d,4
    jb .p4_ld_row
    jmp .p4_ok
.p4_rd:
    mov al,[r14+3]
    mov [rsp],al
    mov al,[r14+2]
    mov [rsp+1],al
    mov al,[r14+1]
    mov [rsp+2],al
    mov al,[r14]
    mov [rsp+3],al
    mov al,[r13-1]
    mov [rsp+4],al
    mov eax,[r13]
    mov [rsp+5],eax
    xor r8d,r8d
.p4_rd_row:
    xor r9d,r9d
.p4_rd_pixel:
    lea eax,[r9+4]
    sub eax,r8d
    movzx edx,byte [rsp+rax-1]
    movzx ecx,byte [rsp+rax]
    lea edx,[rdx+rcx*2+2]
    movzx ecx,byte [rsp+rax+1]
    add edx,ecx
    shr edx,2
    mov eax,r8d
    imul eax,r12d
    lea r10,[rbx+rax]
    mov [r10+r9],dl
    inc r9d
    cmp r9d,4
    jb .p4_rd_pixel
    inc r8d
    cmp r8d,4
    jb .p4_rd_row
    jmp .p4_ok
.p4_diagonal:
    mov al,[r14+3]
    mov [rsp],al
    mov al,[r14+2]
    mov [rsp+1],al
    mov al,[r14+1]
    mov [rsp+2],al
    mov al,[r14]
    mov [rsp+3],al
    mov al,[r13-1]
    mov [rsp+4],al
    mov rax,[r13]
    mov [rsp+5],rax
    mov eax,r15d
    sub eax,VP8_BMODE_VR
    shl eax,6
    lea r11,[rel vp8_diagonal_desc]
    add r11,rax
    xor r8d,r8d
.p4_diag_pixel:
    movzx eax,byte [r11]
    movzx ecx,byte [r11+1]
    movzx edx,byte [rsp+rcx]
    cmp eax,1
    je .p4_diag_value
    movzx ecx,byte [r11+2]
    movzx ecx,byte [rsp+rcx]
    cmp eax,2
    je .p4_diag_avg2
    add edx,ecx
    add edx,ecx
    movzx ecx,byte [r11+3]
    movzx ecx,byte [rsp+rcx]
    add edx,ecx
    add edx,2
    shr edx,2
    jmp .p4_diag_value
.p4_diag_avg2:
    add edx,ecx
    inc edx
    shr edx,1
.p4_diag_value:
    mov eax,r8d
    shr eax,2
    imul eax,r12d
    lea r10,[rbx+rax]
    mov eax,r8d
    and eax,3
    mov [r10+rax],dl
    add r11,4
    inc r8d
    cmp r8d,16
    jb .p4_diag_pixel
.p4_ok:
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.p4_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

section .rodata
; descriptor: operation(1=copy,2=avg2,3=avg3), unified-edge indices.
vp8_diagonal_desc:
    ; VR
    db 2,4,5,0, 2,5,6,0, 2,6,7,0, 2,7,8,0
    db 3,3,4,5, 3,4,5,6, 3,5,6,7, 3,6,7,8
    db 3,2,3,4, 2,4,5,0, 2,5,6,0, 2,6,7,0
    db 3,1,2,3, 3,3,4,5, 3,4,5,6, 3,5,6,7
    ; VL
    db 2,5,6,0, 2,6,7,0, 2,7,8,0, 2,8,9,0
    db 3,5,6,7, 3,6,7,8, 3,7,8,9, 3,8,9,10
    db 2,6,7,0, 2,7,8,0, 2,8,9,0, 3,9,10,11
    db 3,6,7,8, 3,7,8,9, 3,8,9,10, 3,10,11,12
    ; HD
    db 2,3,4,0, 3,3,4,5, 3,4,5,6, 3,5,6,7
    db 2,2,3,0, 3,2,3,4, 2,3,4,0, 3,3,4,5
    db 2,1,2,0, 3,1,2,3, 2,2,3,0, 3,2,3,4
    db 2,0,1,0, 3,0,1,2, 2,1,2,0, 3,1,2,3
    ; HU
    db 2,3,2,0, 3,3,2,1, 2,2,1,0, 3,2,1,0
    db 2,2,1,0, 3,2,1,0, 2,1,0,0, 3,1,0,0
    db 2,1,0,0, 3,1,0,0, 1,0,0,0, 1,0,0,0
    db 1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0

section .text

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
