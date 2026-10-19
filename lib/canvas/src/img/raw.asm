; Headerless raster import and YUV-to-BGRA conversion.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text
; IN rdi=arena, rsi=data, rdx=data_len, rcx=RawImageDesc*. OUT PixBuf* or 0.
global raw_decode
raw_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,64
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    mov eax,[r14+RawImageDesc.width]
    mov [rsp],eax
    mov eax,[r14+RawImageDesc.height]
    mov [rsp+4],eax
    mov eax,[r14+RawImageDesc.stride0]
    mov [rsp+8],eax
    mov eax,[r14+RawImageDesc.format]
    mov [rsp+12],eax
    test dword [rsp],-1
    jz .bad
    test dword [rsp+4],-1
    jz .bad
    cmp dword [rsp],32768
    ja .bad
    cmp dword [rsp+4],32768
    ja .bad
    cmp dword [rsp+12],RAW_FMT_YUYV
    ja .bad
    mov eax,[rsp+8]
    test eax,eax
    jnz .stride_ready
    mov eax,[rsp]
    mov ecx,[rsp+12]
    cmp ecx,RAW_FMT_RGB24
    je .stride3
    cmp ecx,RAW_FMT_BGR24
    je .stride3
    cmp ecx,RAW_FMT_RGBA32
    jb .stride_other
    cmp ecx,RAW_FMT_ABGR32
    jbe .stride4
.stride_other:
    cmp ecx,RAW_FMT_GRAY16LE
    je .stride2
    cmp ecx,RAW_FMT_RGB565LE
    je .stride2
    cmp ecx,RAW_FMT_YUYV
    je .stride2
    jmp .stride_set
.stride3:
    lea eax,[rax+rax*2]
    jmp .stride_set
.stride4:
    shl eax,2
    jmp .stride_set
.stride2:
    shl eax,1
.stride_set:
    mov [rsp+8],eax
.stride_ready:
    mov eax,[rsp+8]
    imul rax,[rsp+4]
    cmp rax,r13
    ja .bad
    mov rdi,rbx
    mov esi,[rsp]
    mov edx,[rsp+4]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov [rsp+16],rax
    mov r15,[rax+PixBuf_data]
    xor r10d,r10d                 ; y
.row:
    cmp r10d,[rsp+4]
    jae .done
    mov eax,r10d
    imul eax,[rsp+8]
    lea r8,[r12+rax]              ; source row
    mov rax,[rsp+16]
    mov eax,[rax+PixBuf_stride]
    imul eax,r10d
    lea r9,[r15+rax]              ; destination row
    xor r11d,r11d                 ; x
.pixel:
    cmp r11d,[rsp]
    jae .next_row
    mov eax,[rsp+12]
    cmp eax,RAW_FMT_RGB24
    je .rgb24
    cmp eax,RAW_FMT_BGR24
    je .bgr24
    cmp eax,RAW_FMT_RGBA32
    je .rgba
    cmp eax,RAW_FMT_BGRA32
    je .bgra
    cmp eax,RAW_FMT_ARGB32
    je .argb
    cmp eax,RAW_FMT_ABGR32
    je .abgr
    cmp eax,RAW_FMT_GRAY8
    je .gray8
    cmp eax,RAW_FMT_GRAY16LE
    je .gray16
    cmp eax,RAW_FMT_RGB565LE
    je .rgb565
    cmp eax,RAW_FMT_YUYV
    je .yuyv
    cmp eax,RAW_FMT_NV12
    je .nv12
    jmp .i420
.rgb24:
    lea rcx,[r11+r11*2]
    mov al,[r8+rcx+2]
    mov [r9+r11*4],al
    mov al,[r8+rcx+1]
    mov [r9+r11*4+1],al
    mov al,[r8+rcx]
    mov [r9+r11*4+2],al
    jmp .opaque
.bgr24:
    lea rcx,[r11+r11*2]
    mov eax,[r8+rcx]
    mov [r9+r11*4],eax
    jmp .opaque
.rgba:
    mov eax,[r8+r11*4]
    bswap eax
    ror eax,8
    mov [r9+r11*4],eax
    jmp .advance
.bgra:
    mov eax,[r8+r11*4]
    mov [r9+r11*4],eax
    jmp .advance
.argb:
    mov eax,[r8+r11*4]
    rol eax,8
    bswap eax
    mov [r9+r11*4],eax
    jmp .advance
.abgr:
    mov eax,[r8+r11*4]
    ror eax,8
    mov [r9+r11*4],eax
    jmp .advance
.gray8:
    movzx eax,byte [r8+r11]
    imul eax,0x00010101
    or eax,0xFF000000
    mov [r9+r11*4],eax
    jmp .advance
.gray16:
    movzx eax,word [r8+r11*2]
    shr eax,8
    imul eax,0x00010101
    or eax,0xFF000000
    mov [r9+r11*4],eax
    jmp .advance
.rgb565:
    movzx eax,word [r8+r11*2]
    mov edx,eax
    and edx,31
    shl edx,3
    mov ecx,eax
    shr ecx,5
    and ecx,63
    shl ecx,10
    or edx,ecx
    shr eax,11
    shl eax,19
    or eax,edx
    or eax,0xFF000000
    mov [r9+r11*4],eax
    jmp .advance
.yuyv:
    mov eax,r11d
    and eax,-2
    shl eax,1
    movzx edx,byte [r8+rax+1]
    movzx ecx,byte [r8+rax+3]
    test r11b,1
    jz .yuyv_even
    movzx eax,byte [r8+rax+2]
    jmp .convert_yuv
.yuyv_even:
    movzx eax,byte [r8+rax]
    jmp .convert_yuv
.nv12:
    movzx eax,byte [r8+r11]
    mov rdx,[r14+RawImageDesc.plane1_offset]
    test rdx,rdx
    jnz .nv_off
    mov edx,[rsp+8]
    imul rdx,[rsp+4]
.nv_off:
    mov ecx,[r14+RawImageDesc.stride1]
    test ecx,ecx
    jnz .nv_stride
    mov ecx,[rsp+8]
.nv_stride:
    mov esi,r10d
    shr esi,1
    imul esi,ecx
    mov ecx,r11d
    and ecx,-2
    add rsi,rdx
    movzx edx,byte [r12+rsi+rcx]
    movzx ecx,byte [r12+rsi+rcx+1]
    jmp .convert_yuv
.i420:
    movzx eax,byte [r8+r11]
    mov rdx,[r14+RawImageDesc.plane1_offset]
    mov rsi,[r14+RawImageDesc.plane2_offset]
    test rdx,rdx
    jz .bad
    test rsi,rsi
    jz .bad
    mov ecx,[r14+RawImageDesc.stride1]
    mov edi,r10d
    shr edi,1
    imul edi,ecx
    mov ecx,r11d
    shr ecx,1
    add edi,ecx
    movzx edx,byte [r12+rdx+rdi]
    movzx ecx,byte [r12+rsi+rdi]
.convert_yuv:
    sub eax,16
    jns .y_nonnegative
    xor eax,eax
.y_nonnegative:
    sub edx,128
    sub ecx,128
    mov [rsp+24],edx
    mov [rsp+28],ecx
    imul eax,298
    mov esi,eax                    ; G accumulator
    mov edi,eax                    ; B accumulator
    mov ecx,[rsp+28]
    imul ecx,409
    add ecx,eax                    ; R accumulator
    mov edx,[rsp+24]
    imul edx,100
    sub esi,edx
    mov edx,[rsp+28]
    imul edx,208
    sub esi,edx
    mov edx,[rsp+24]
    imul edx,516
    add edi,edx
    mov eax,ecx
    add eax,128
    sar eax,8
    add esi,128
    sar esi,8
    add edi,128
    sar edi,8
    call .pack_clamped
    mov [r9+r11*4],eax
    jmp .advance
.opaque:
    mov byte [r9+r11*4+3],255
.advance:
    inc r11d
    jmp .pixel
.next_row:
    inc r10d
    jmp .row
.done:
    mov rax,[rsp+16]
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; IN eax=R, esi=G, edi=B. OUT eax=BGRA.
.pack_clamped:
    test eax,eax
    jns .r_hi
    xor eax,eax
.r_hi:
    cmp eax,255
    jbe .g_lo
    mov eax,255
.g_lo:
    test esi,esi
    jns .g_hi
    xor esi,esi
.g_hi:
    cmp esi,255
    jbe .b_lo
    mov esi,255
.b_lo:
    test edi,edi
    jns .b_hi
    xor edi,edi
.b_hi:
    cmp edi,255
    jbe .pack
    mov edi,255
.pack:
    shl eax,16
    shl esi,8
    or eax,esi
    or eax,edi
    or eax,0xFF000000
    ret

section .data
global raw_version
raw_version: dq 0x010000
