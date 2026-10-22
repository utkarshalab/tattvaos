; WebP extended-container animation inspection.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

%define FOURCC_RIFF 0x46464952
%define FOURCC_WEBP 0x50424557
%define FOURCC_VP8X 0x58385056
%define FOURCC_ANIM 0x4d494e41
%define FOURCC_ANMF 0x464d4e41
%define FOURCC_ALPH 0x48504c41
%define FOURCC_VP8  0x20385056
%define FOURCC_VP8L 0x4c385056

extern fill_solid
extern arena_alloc
extern pixbuf_create
extern blit_copy
extern webp_vp8_decode
extern webp_vp8l_decode
extern webp_alpha_apply_raw

section .text

; data,len,WebPAnimationInfo* -> 0/-EINVAL.
; Validates the complete animated container and every nested frame chunk.
global webp_inspect_animation
webp_inspect_animation:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test rbx,rbx
    jz .bad
    test r13,r13
    jz .bad
    cmp r12,30                         ; RIFF + mandatory VP8X
    jb .bad
    cmp dword [rbx],FOURCC_RIFF
    jne .bad
    cmp dword [rbx+8],FOURCC_WEBP
    jne .bad
    mov r14d,[rbx+4]
    add r14,8
    jc .bad
    cmp r14,r12
    ja .bad
    cmp dword [rbx+12],FOURCC_VP8X
    jne .bad
    cmp dword [rbx+16],10
    jne .bad
    movzx eax,byte [rbx+20]
    test eax,0xc1                      ; reserved VP8X bits
    jnz .bad
    test eax,WEBP_FLAG_ANIMATION
    jz .bad
    cmp byte [rbx+21],0
    jne .bad
    cmp byte [rbx+22],0
    jne .bad
    cmp byte [rbx+23],0
    jne .bad

    mov rdi,r13
    xor eax,eax
    mov ecx,WebPAnimationInfo_size/8
    rep stosq
    mov eax,[rbx+24]
    and eax,0x00ffffff
    inc eax
    mov [r13+WebPAnimationInfo.width],eax
    mov eax,[rbx+27]
    and eax,0x00ffffff
    inc eax
    mov [r13+WebPAnimationInfo.height],eax
    mov dword [rsp],0                  ; ANIM seen
    mov dword [rsp+4],0                ; frame count
    mov qword [rsp+8],0                ; total duration
    mov r15d,30

.top:
    cmp r15,r14
    jae .done
    lea rax,[r15+8]
    cmp rax,r14
    ja .bad
    mov r10d,[rbx+r15]
    mov r11d,[rbx+r15+4]
    lea r8,[r15+8]
    lea rax,[r8+r11]
    cmp rax,r8
    jb .bad
    cmp rax,r14
    ja .bad
    cmp r10d,FOURCC_ANIM
    je .anim
    cmp r10d,FOURCC_ANMF
    je .anmf
.next:
    lea r15,[r15+r11+9]
    and r15,-2
    cmp r15,r14
    ja .bad
    jmp .top

.anim:
    cmp r11d,6
    jne .bad
    cmp dword [rsp],0
    jne .bad
    cmp dword [rsp+4],0                ; ANIM must precede frames
    jne .bad
    mov dword [rsp],1
    mov eax,[rbx+r8]
    mov [r13+WebPAnimationInfo.background],eax
    movzx eax,word [rbx+r8+4]
    mov [r13+WebPAnimationInfo.loop_count],eax
    jmp .next

.anmf:
    cmp dword [rsp],1
    jne .bad
    cmp r11d,16
    jbe .bad
    mov eax,[rbx+r8]
    and eax,0x00ffffff
    shl eax,1
    mov [rsp+16],eax                   ; x
    mov eax,[rbx+r8+3]
    and eax,0x00ffffff
    shl eax,1
    mov [rsp+20],eax                   ; y
    mov eax,[rbx+r8+6]
    and eax,0x00ffffff
    inc eax
    mov [rsp+24],eax                   ; width
    add eax,[rsp+16]
    jc .bad
    cmp eax,[r13+WebPAnimationInfo.width]
    ja .bad
    mov eax,[rbx+r8+9]
    and eax,0x00ffffff
    inc eax
    mov [rsp+28],eax                   ; height
    add eax,[rsp+20]
    jc .bad
    cmp eax,[r13+WebPAnimationInfo.height]
    ja .bad
    mov eax,[rbx+r8+12]
    and eax,0x00ffffff
    add [rsp+8],rax
    jc .bad
    test byte [rbx+r8+15],0xfc         ; only dispose/blend are defined
    jnz .bad

    lea r9,[rbx+r8+16]                 ; nested cursor (absolute address)
    lea rdx,[rbx+r8]
    add rdx,r11                        ; nested end
    xor ecx,ecx                        ; primary bitstream count
    xor edi,edi                        ; ALPH count
.nested:
    cmp r9,rdx
    jae .nested_done
    lea rax,[r9+8]
    cmp rax,rdx
    ja .bad
    mov r10d,[r9]
    mov r11d,[r9+4]
    lea rax,[r9+r11+8]
    cmp rax,r9
    jb .bad
    cmp rax,rdx
    ja .bad
    cmp r10d,FOURCC_ALPH
    je .nested_alpha
    cmp r10d,FOURCC_VP8
    je .nested_primary
    cmp r10d,FOURCC_VP8L
    je .nested_primary
.nested_next:
    lea r9,[r9+r11+8]
    test r11b,1
    jz .nested_aligned
    inc r9
.nested_aligned:
    cmp r9,rdx
    ja .bad
    jmp .nested
.nested_alpha:
    test ecx,ecx                       ; ALPH must precede primary
    jnz .bad
    inc edi
    cmp edi,1
    ja .bad
    cmp r11d,1
    jb .bad
    jmp .nested_next
.nested_primary:
    inc ecx
    cmp ecx,1
    ja .bad
    cmp r10d,FOURCC_VP8
    jne .nested_vp8l
    cmp r11d,10
    jb .bad
    jmp .nested_next
.nested_vp8l:
    cmp r11d,5
    jb .bad
    cmp byte [r9+8],0x2f
    jne .bad
    jmp .nested_next
.nested_done:
    cmp r9,rdx
    jne .bad
    cmp ecx,1
    jne .bad
    inc dword [rsp+4]
    mov r11d,[rbx+r15+4]               ; restore top-level chunk size
    jmp .next

.done:
    cmp r15,r14
    jne .bad
    cmp dword [rsp],1
    jne .bad
    cmp dword [rsp+4],0
    je .bad
    mov eax,[rsp+4]
    mov [r13+WebPAnimationInfo.frame_count],eax
    mov rax,[rsp+8]
    mov [r13+WebPAnimationInfo.duration_ms],rax
    xor eax,eax
    jmp .out
.bad:
    mov rax,-EINVAL
.out:
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; WebPCompositeState* -> 0/-EINVAL. BGRA pixels use straight alpha.
global webp_composite_frame
webp_composite_frame:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    test rbx,rbx
    jz .composite_bad
    mov r12,[rbx+WebPCompositeState.canvas]
    mov r13,[rbx+WebPCompositeState.frame]
    test r12,r12
    jz .composite_bad
    test r13,r13
    jz .composite_bad
    mov eax,[rbx+WebPCompositeState.width]
    test eax,eax
    jz .composite_bad
    cmp rax,[r13+PixBuf_width]
    ja .composite_bad
    add eax,[rbx+WebPCompositeState.x]
    jc .composite_bad
    cmp rax,[r12+PixBuf_width]
    ja .composite_bad
    mov eax,[rbx+WebPCompositeState.height]
    test eax,eax
    jz .composite_bad
    cmp rax,[r13+PixBuf_height]
    ja .composite_bad
    add eax,[rbx+WebPCompositeState.y]
    jc .composite_bad
    cmp rax,[r12+PixBuf_height]
    ja .composite_bad
    xor r14d,r14d
.composite_row:
    cmp r14d,[rbx+WebPCompositeState.height]
    jae .composite_ok
    mov eax,r14d
    add eax,[rbx+WebPCompositeState.y]
    imul rax,[r12+PixBuf_stride]
    add rax,[r12+PixBuf_data]
    mov edx,[rbx+WebPCompositeState.x]
    lea rax,[rax+rdx*4]
    mov [rsp],rax
    mov eax,r14d
    imul rax,[r13+PixBuf_stride]
    add rax,[r13+PixBuf_data]
    mov [rsp+8],rax
    xor r15d,r15d
.composite_pixel:
    cmp r15d,[rbx+WebPCompositeState.width]
    jae .composite_next_row
    mov rdi,[rsp]
    mov rsi,[rsp+8]
    mov eax,[rsi+r15*4]
    mov [rsp+16],eax                  ; source
    cmp dword [rbx+WebPCompositeState.blend],0
    je .composite_store_source
    mov ecx,eax
    shr ecx,24                        ; source alpha
    test ecx,ecx
    jz .composite_advance
    cmp ecx,255
    je .composite_store_source
    mov edx,[rdi+r15*4]
    mov [rsp+20],edx                  ; destination
    mov r8d,edx
    shr r8d,24                        ; destination alpha
    mov r9d,255
    sub r9d,ecx                       ; inverse source alpha
    imul r8d,r9d
    add r8d,127
    mov eax,r8d
    xor edx,edx
    mov r10d,255
    div r10d
    add eax,ecx
    mov [rsp+24],eax                  ; output alpha
    imul eax,255
    mov [rsp+28],eax                  ; common denominator
    xor r11d,r11d                    ; output color
    xor r10d,r10d                    ; channel shift
.channel:
    mov eax,[rsp+16]
    mov ecx,r10d
    shr eax,cl
    and eax,255
    mov ecx,[rsp+16]
    shr ecx,24
    imul eax,ecx
    imul eax,255
    mov edx,[rsp+20]
    mov ecx,r10d
    shr edx,cl
    and edx,255
    mov ecx,[rsp+20]
    shr ecx,24
    imul edx,ecx
    mov ecx,255
    mov edi,[rsp+16]
    shr edi,24
    sub ecx,edi
    imul edx,ecx
    add eax,edx
    mov edx,[rsp+28]
    shr edx,1
    add eax,edx
    xor edx,edx
    div dword [rsp+28]
    mov ecx,r10d
    shl eax,cl
    or r11d,eax
    add r10d,8
    cmp r10d,24
    jb .channel
    mov eax,[rsp+24]
    shl eax,24
    or eax,r11d
    mov rdi,[rsp]
    mov [rdi+r15*4],eax
    jmp .composite_advance
.composite_store_source:
    mov [rdi+r15*4],eax
.composite_advance:
    inc r15d
    jmp .composite_pixel
.composite_next_row:
    inc r14d
    jmp .composite_row
.composite_ok:
    xor eax,eax
    jmp .composite_out
.composite_bad:
    mov rax,-EINVAL
.composite_out:
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; canvas,x,y,width,height,background BGRA -> 0/-EINVAL.
global webp_dispose_background
webp_dispose_background:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    test rbx,rbx
    jz .dispose_bad
    test r14,r14
    jz .dispose_bad
    test r15,r15
    jz .dispose_bad
    mov rax,r12
    add rax,r14
    jc .dispose_bad
    cmp rax,[rbx+PixBuf_width]
    ja .dispose_bad
    mov rax,r13
    add rax,r15
    jc .dispose_bad
    cmp rax,[rbx+PixBuf_height]
    ja .dispose_bad
    mov rax,r13
    imul rax,[rbx+PixBuf_stride]
    add rax,[rbx+PixBuf_data]
    lea rdi,[rax+r12*4]
    mov esi,r9d
    mov rdx,r14
    mov rcx,r15
    mov r8,[rbx+PixBuf_stride]
    call fill_solid
    jmp .dispose_out
.dispose_bad:
    mov rax,-EINVAL
.dispose_out:
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; arena,data,len -> WebPAnimation* or 0.
global webp_decode_animation
webp_decode_animation:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,184
    mov rbx,rdi                         ; arena
    mov r12,rsi                         ; container
    mov r13,rdx                         ; length
    test rbx,rbx
    jz .decode_fail
    lea rdx,[rsp]
    mov rdi,r12
    mov rsi,r13
    call webp_inspect_animation
    test eax,eax
    jnz .decode_fail
    mov rdi,rbx
    mov esi,WebPAnimation_size
    call arena_alloc
    test rax,rax
    jz .decode_fail
    mov r14,rax
    mov eax,[rsp+WebPAnimationInfo.width]
    mov [r14+WebPAnimation.width],eax
    mov eax,[rsp+WebPAnimationInfo.height]
    mov [r14+WebPAnimation.height],eax
    mov eax,[rsp+WebPAnimationInfo.frame_count]
    mov [r14+WebPAnimation.frame_count],eax
    mov eax,[rsp+WebPAnimationInfo.loop_count]
    mov [r14+WebPAnimation.loop_count],eax
    mov rax,[rsp+WebPAnimationInfo.duration_ms]
    mov [r14+WebPAnimation.duration_ms],rax
    mov eax,[rsp+WebPAnimationInfo.background]
    mov [r14+WebPAnimation.background],eax
    mov [r14+WebPAnimation.arena],rbx

    mov eax,[r14+WebPAnimation.frame_count]
    lea rsi,[rax*8]
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jz .decode_fail
    mov [r14+WebPAnimation.frames],rax
    mov eax,[r14+WebPAnimation.frame_count]
    lea rsi,[rax*4]
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jz .decode_fail
    mov [r14+WebPAnimation.delays_ms],rax
    mov esi,[r14+WebPAnimation.frame_count]
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jz .decode_fail
    mov [r14+WebPAnimation.disposals],rax
    mov esi,[r14+WebPAnimation.frame_count]
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jz .decode_fail
    mov [r14+WebPAnimation.blends],rax

    mov rdi,rbx
    mov esi,[r14+WebPAnimation.width]
    mov edx,[r14+WebPAnimation.height]
    mov ecx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jle .decode_fail
    mov [rsp+40],rax                    ; working canvas
    mov rdi,[rax+PixBuf_data]
    mov esi,[r14+WebPAnimation.background]
    mov edx,[r14+WebPAnimation.width]
    mov ecx,[r14+WebPAnimation.height]
    mov r8,[rax+PixBuf_stride]
    call fill_solid

    mov eax,[r12+4]
    add rax,8
    mov r15,rax                         ; logical RIFF end offset
    mov qword [rsp+48],30               ; top-level cursor
    mov dword [rsp+56],0                ; frame index
.decode_top:
    mov r10,[rsp+48]
    cmp r10,r15
    jae .decode_done
    mov r11d,[r12+r10+4]
    cmp dword [r12+r10],FOURCC_ANMF
    jne .decode_next
    lea r8,[r10+8]
    mov eax,[r12+r8]
    and eax,0x00ffffff
    shl eax,1
    mov [rsp+64],eax
    mov eax,[r12+r8+3]
    and eax,0x00ffffff
    shl eax,1
    mov [rsp+68],eax
    mov eax,[r12+r8+6]
    and eax,0x00ffffff
    inc eax
    mov [rsp+72],eax
    mov eax,[r12+r8+9]
    and eax,0x00ffffff
    inc eax
    mov [rsp+76],eax
    mov eax,[r12+r8+12]
    and eax,0x00ffffff
    mov [rsp+80],eax
    movzx eax,byte [r12+r8+15]
    mov [rsp+84],eax
    mov qword [rsp+88],0                ; alpha payload
    mov qword [rsp+96],0
    mov qword [rsp+104],0               ; primary payload
    mov qword [rsp+112],0
    mov dword [rsp+120],0               ; codec
    lea r9,[r12+r8+16]
    lea rdx,[r12+r8]
    add rdx,r11
.decode_nested:
    cmp r9,rdx
    jae .decode_frame
    mov ecx,[r9]
    mov r11d,[r9+4]
    cmp ecx,FOURCC_ALPH
    je .decode_alpha
    cmp ecx,FOURCC_VP8
    je .decode_vp8_chunk
    cmp ecx,FOURCC_VP8L
    je .decode_vp8l_chunk
.decode_nested_next:
    lea r9,[r9+r11+8]
    test r11b,1
    jz .decode_nested
    inc r9
    jmp .decode_nested
.decode_alpha:
    lea rax,[r9+8]
    mov [rsp+88],rax
    mov [rsp+96],r11
    jmp .decode_nested_next
.decode_vp8_chunk:
    mov dword [rsp+120],WEBP_CODEC_VP8
    jmp .decode_primary
.decode_vp8l_chunk:
    mov dword [rsp+120],WEBP_CODEC_VP8L
.decode_primary:
    lea rax,[r9+8]
    mov [rsp+104],rax
    mov [rsp+112],r11
    jmp .decode_nested_next

.decode_frame:
    mov rdi,rbx
    mov rsi,[rsp+104]
    mov rdx,[rsp+112]
    cmp dword [rsp+120],WEBP_CODEC_VP8
    je .decode_lossy
    call webp_vp8l_decode
    jmp .decoded_frame
.decode_lossy:
    call webp_vp8_decode
.decoded_frame:
    test rax,rax
    jz .decode_fail
    mov [rsp+128],rax                   ; decoded frame
    mov ecx,[rsp+72]
    cmp rcx,[rax+PixBuf_width]
    jne .decode_fail
    mov ecx,[rsp+76]
    cmp rcx,[rax+PixBuf_height]
    jne .decode_fail
    cmp dword [rsp+120],WEBP_CODEC_VP8
    jne .frame_alpha_done
    cmp qword [rsp+88],0
    je .frame_alpha_done
    mov rdi,rax
    mov rsi,[rsp+88]
    mov rdx,[rsp+96]
    mov rcx,rbx
    call webp_alpha_apply_raw
    test eax,eax
    js .decode_fail
.frame_alpha_done:
    lea rdi,[rsp+136]
    mov rax,[rsp+40]
    mov [rdi+WebPCompositeState.canvas],rax
    mov rax,[rsp+128]
    mov [rdi+WebPCompositeState.frame],rax
    mov eax,[rsp+64]
    mov [rdi+WebPCompositeState.x],eax
    mov eax,[rsp+68]
    mov [rdi+WebPCompositeState.y],eax
    mov eax,[rsp+72]
    mov [rdi+WebPCompositeState.width],eax
    mov eax,[rsp+76]
    mov [rdi+WebPCompositeState.height],eax
    mov eax,[rsp+84]
    shr eax,1
    xor eax,1                          ; ANMF bit 1: 0=blend, 1=replace
    and eax,1
    mov [rdi+WebPCompositeState.blend],eax
    call webp_composite_frame
    test eax,eax
    jnz .decode_fail

    ; Snapshot the displayed canvas.
    mov rdi,rbx
    mov esi,[r14+WebPAnimation.width]
    mov edx,[r14+WebPAnimation.height]
    mov ecx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jle .decode_fail
    mov [rsp+128],rax
    mov rdi,[rax+PixBuf_data]
    mov rax,[rsp+40]
    mov rsi,[rax+PixBuf_data]
    mov edx,[r14+WebPAnimation.width]
    mov ecx,[r14+WebPAnimation.height]
    mov rax,[rsp+128]
    mov r8,[rax+PixBuf_stride]
    mov rax,[rsp+40]
    mov r9,[rax+PixBuf_stride]
    call blit_copy
    mov ecx,[rsp+56]
    mov rdi,[r14+WebPAnimation.frames]
    mov rax,[rsp+128]
    mov [rdi+rcx*8],rax
    mov rdi,[r14+WebPAnimation.delays_ms]
    mov eax,[rsp+80]
    mov [rdi+rcx*4],eax
    mov eax,[rsp+84]
    mov rdi,[r14+WebPAnimation.disposals]
    and eax,1
    mov [rdi+rcx],al
    mov edx,[rsp+84]
    shr edx,1
    xor edx,1
    and edx,1
    mov rdi,[r14+WebPAnimation.blends]
    mov [rdi+rcx],dl
    inc dword [rsp+56]
    test eax,eax
    jz .decode_restore_top
    mov rdi,[rsp+40]
    mov esi,[rsp+64]
    mov edx,[rsp+68]
    mov ecx,[rsp+72]
    mov r8d,[rsp+76]
    mov r9d,[r14+WebPAnimation.background]
    call webp_dispose_background
    test eax,eax
    jnz .decode_fail
.decode_restore_top:
    mov r10,[rsp+48]
    mov r11d,[r12+r10+4]
.decode_next:
    lea r10,[r10+r11+9]
    and r10,-2
    mov [rsp+48],r10
    jmp .decode_top
.decode_done:
    mov eax,[rsp+56]
    cmp eax,[r14+WebPAnimation.frame_count]
    jne .decode_fail
    mov rax,r14
    jmp .decode_out
.decode_fail:
    xor eax,eax
.decode_out:
    add rsp,184
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global webp_animation_version
webp_animation_version: dq 0x010000
