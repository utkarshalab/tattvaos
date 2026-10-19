; VP8L predictor transform. Inputs and output are packed ARGB.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

%macro AVG2 4
    mov %4,%2
    xor %4,%3
    and %4,0xfefefefe
    shr %4,1
    mov %1,%2
    and %1,%3
    add %1,%4
%endmacro

section .text

; mode,L,T,TL,TR -> predicted ARGB or -EINVAL.
global webp_predict_basic
global webp_predict_pixel
webp_predict_basic:
webp_predict_pixel:
    cmp edi,13
    ja .bad
    mov r9d,esi                        ; L
    mov r10d,edx                       ; T
    mov r11d,ecx                       ; TL
    cmp edi,0
    je .mode0
    cmp edi,1
    je .left
    cmp edi,2
    je .top
    cmp edi,3
    je .top_right
    cmp edi,4
    je .top_left
    cmp edi,5
    je .mode5
    cmp edi,6
    je .mode6
    cmp edi,7
    je .mode7
    cmp edi,8
    je .mode8
    cmp edi,9
    je .mode9
    cmp edi,10
    je .mode10
    cmp edi,11
    je .mode11
    cmp edi,12
    je .mode12
    jmp .mode13
.mode10:
    ; Average2(Average2(L,TL), Average2(T,TR)).
    AVG2 eax,r9d,r11d,edi
    AVG2 edx,r10d,r8d,ecx
    AVG2 eax,eax,edx,ecx
    ret
.mode11:
    ; Select L or T using the aggregate ARGB distance from L+T-TL.
    xor edi,edi                        ; score for L
    xor esi,esi                        ; score for T
    xor ecx,ecx
.select_component:
    mov eax,r9d
    shr eax,cl
    and eax,0xff                       ; L component
    mov edx,r10d
    shr edx,cl
    and edx,0xff                       ; T component
    mov r8d,r11d
    shr r8d,cl
    and r8d,0xff                       ; TL component
    sub r8d,edx
    sub r8d,eax                        ; -(L + T - TL)
    neg r8d
    mov edx,r8d
    sub edx,eax
    mov eax,edx
    sar eax,31
    xor edx,eax
    sub edx,eax
    add edi,edx
    mov eax,r10d
    shr eax,cl
    and eax,0xff
    sub r8d,eax
    mov eax,r8d
    sar eax,31
    xor r8d,eax
    sub r8d,eax
    add esi,r8d
    add ecx,8
    cmp ecx,32
    jb .select_component
    mov eax,r10d
    cmp edi,esi
    cmovb eax,r9d
    ret
.mode12:
    xor r8d,r8d
    xor ecx,ecx
.clamp_add_component:
    mov eax,r9d
    shr eax,cl
    and eax,0xff
    mov edx,r10d
    shr edx,cl
    and edx,0xff
    add eax,edx
    mov edx,r11d
    shr edx,cl
    and edx,0xff
    sub eax,edx
    xor edx,edx
    test eax,eax
    cmovs eax,edx
    mov edx,255
    cmp eax,edx
    cmova eax,edx
    shl eax,cl
    or r8d,eax
    add ecx,8
    cmp ecx,32
    jb .clamp_add_component
    mov eax,r8d
    ret
.mode13:
    xor r8d,r8d
    xor ecx,ecx
.clamp_half_component:
    mov eax,r9d
    shr eax,cl
    and eax,0xff
    mov edx,r10d
    shr edx,cl
    and edx,0xff
    add eax,edx
    shr eax,1                         ; average(L,T)
    mov edx,r11d
    shr edx,cl
    and edx,0xff
    neg edx
    add edx,eax                       ; average - TL
    sar edx,1
    add eax,edx                       ; average + (average-TL)/2
    xor edx,edx
    test eax,eax
    cmovs eax,edx
    mov edx,255
    cmp eax,edx
    cmova eax,edx
    shl eax,cl
    or r8d,eax
    add ecx,8
    cmp ecx,32
    jb .clamp_half_component
    mov eax,r8d
    ret
.mode0:
    mov eax,0xff000000
    ret
.left:
    mov eax,r9d
    ret
.top:
    mov eax,r10d
    ret
.top_right:
    mov eax,r8d
    ret
.top_left:
    mov eax,r11d
    ret
.mode5:
    AVG2 eax,r9d,r8d,edi
    AVG2 eax,eax,r10d,edi
    ret
.mode6:
    AVG2 eax,r9d,r11d,edi
    ret
.mode7:
    AVG2 eax,r9d,r10d,edi
    ret
.mode8:
    AVG2 eax,r11d,r10d,edi
    ret
.mode9:
    AVG2 eax,r10d,r8d,edi
    ret
.bad:
    mov rax,-EINVAL
    ret

; Add packed bytes independently modulo 256.
; residual,predictor -> packed ARGB.
webp_add_pixels:
    mov eax,edi
    add eax,esi
    mov edx,edi
    xor edx,esi
    xor edx,eax
    and edx,0x01010100                 ; carries crossing byte lanes
    sub eax,edx
    ret

; WebPPredictState* -> 0 or -EINVAL.
global webp_inverse_predictor
webp_inverse_predictor:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    test rbx,rbx
    jz .image_bad
    mov r12,[rbx+WebPPredictState.pixels]
    mov r13,[rbx+WebPPredictState.modes]
    test r12,r12
    jz .image_bad
    test r13,r13
    jz .image_bad
    mov r14d,[rbx+WebPPredictState.width]
    mov r15d,[rbx+WebPPredictState.height]
    test r14d,r14d
    jz .image_bad
    test r15d,r15d
    jz .image_bad
    mov ecx,[rbx+WebPPredictState.size_bits]
    cmp ecx,2
    jb .image_bad
    cmp ecx,9
    ja .image_bad
    mov eax,1
    shl eax,cl
    dec eax
    mov [rsp+16],eax                   ; block mask
    add eax,r14d
    jc .image_bad
    shr eax,cl
    mov [rsp+20],eax                   ; transform width
    mov eax,[rsp+16]
    add eax,r15d
    jc .image_bad
    shr eax,cl
    imul rax,[rsp+20]
    jo .image_bad
    cmp rax,[rbx+WebPPredictState.mode_count]
    ja .image_bad
    mov dword [rsp],0                  ; y
.image_row:
    mov eax,[rsp]
    cmp eax,r15d
    jae .image_done
    mov dword [rsp+4],0                ; x
.image_pixel:
    mov eax,[rsp+4]
    cmp eax,r14d
    jae .image_next_row
    mov edx,[rsp]
    imul edx,r14d
    add edx,eax
    mov [rsp+8],edx                    ; raster index
    test eax,eax
    jnz .not_left_edge
    test dword [rsp],-1
    jnz .left_edge
    xor edi,edi                        ; top-left uses black
    jmp .neighbors_ready
.left_edge:
    mov edi,2                          ; left column uses top
    jmp .neighbors_ready
.not_left_edge:
    test dword [rsp],-1
    jnz .interior
    mov edi,1                          ; top row uses left
    jmp .neighbors_ready
.interior:
    mov eax,[rsp]
    mov ecx,[rbx+WebPPredictState.size_bits]
    shr eax,cl
    imul eax,[rsp+20]
    mov edx,[rsp+4]
    shr edx,cl
    add eax,edx
    mov eax,[r13+rax*4]
    shr eax,8
    and eax,0xff
    cmp eax,13
    ja .image_bad
    mov edi,eax
.neighbors_ready:
    mov eax,[rsp+8]
    xor esi,esi
    xor edx,edx
    xor ecx,ecx
    xor r8d,r8d
    cmp dword [rsp+4],0
    je .no_left
    mov esi,[r12+rax*4-4]
.no_left:
    cmp dword [rsp],0
    je .call_predictor
    mov edx,eax
    sub edx,r14d
    mov ecx,[r12+rdx*4]
    cmp dword [rsp+4],0
    je .no_top_left
    mov r8d,[r12+rdx*4-4]              ; temporarily TL
.no_top_left:
    mov r9d,r8d                        ; save TL
    mov r8d,[r12+rdx*4+4]              ; TR
    mov edx,[rsp+4]
    inc edx
    cmp edx,r14d
    jb .top_neighbors_ready
    mov edx,[rsp]
    imul edx,r14d
    mov r8d,[r12+rdx*4]                ; right edge wraps to row start
.top_neighbors_ready:
    mov edx,ecx                        ; T
    mov ecx,r9d                        ; TL
.call_predictor:
    call webp_predict_pixel
    test rax,rax
    js .image_bad
    mov esi,eax
    mov eax,[rsp+8]
    mov edi,[r12+rax*4]
    call webp_add_pixels
    mov edx,[rsp+8]
    mov [r12+rdx*4],eax
    inc dword [rsp+4]
    jmp .image_pixel
.image_next_row:
    inc dword [rsp]
    jmp .image_row
.image_done:
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.image_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global webp_predict_version
webp_predict_version: dq 0x010000
