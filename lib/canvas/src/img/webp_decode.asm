; WebP image decode entry point and baseline VP8L entropy pipeline.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern arena_alloc
extern pixbuf_create
extern webp_inspect
extern webp_bits_init
extern webp_bits_get
extern webp_decode_image
extern webp_inverse_subtract_green
extern webp_inverse_color
extern webp_inverse_color_index
extern webp_inverse_predictor
extern webp_palette_expand
extern webp_vp8_decode

%define TX_TYPE       0
%define TX_BITS       4
%define TX_DATA       8
%define TX_COUNT     16
%define TX_WIDTH     24
%define TX_COLORS    28
%define TX_SIZE      32

section .text

; arena,data,len -> PixBuf* or 0. Lossy VP8 is handled by its own pipeline.
global webp_decode
webp_decode:
    PROLOGUE_SAVE rbx,r12,r13
    sub rsp,WebPInfo_size
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov rdi,r12
    mov rsi,r13
    mov rdx,rsp
    call webp_inspect
    test rax,rax
    js .decode_bad
    cmp dword [rsp+WebPInfo.codec],WEBP_CODEC_VP8
    je .decode_vp8
    cmp dword [rsp+WebPInfo.codec],WEBP_CODEC_VP8L
    jne .decode_bad
    mov rdi,rbx
    mov rsi,[rsp+WebPInfo.payload]
    mov rdx,[rsp+WebPInfo.payload_len]
    call webp_vp8l_decode
    jmp .decode_done
.decode_vp8:
    mov rdi,rbx
    mov rsi,[rsp+WebPInfo.payload]
    mov rdx,[rsp+WebPInfo.payload_len]
    call webp_vp8_decode
.decode_done:
    test rax,rax
    jz .decode_bad
    cmp dword [rsp+WebPInfo.codec],WEBP_CODEC_VP8
    jne .decode_return
    cmp qword [rsp+WebPInfo.alpha],0
    je .decode_return
    mov r12,rax
    mov rdi,rax
    mov rsi,[rsp+WebPInfo.alpha]
    mov rdx,[rsp+WebPInfo.alpha_len]
    mov rcx,rbx
    call webp_alpha_apply_raw
    test eax,eax
    js .decode_bad
    mov rax,r12
.decode_return:
    add rsp,WebPInfo_size
    EPILOGUE_RESTORE rbx,r12,r13
.decode_bad:
    xor eax,eax
    add rsp,WebPInfo_size
    EPILOGUE_RESTORE rbx,r12,r13

; PixBuf*,ALPH payload,len,arena -> 0/-EINVAL. Raw or VP8L alpha.
global webp_alpha_apply_raw
webp_alpha_apply_raw:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov [rsp+24],rcx
    test rbx,rbx
    jz .alpha_bad
    test r12,r12
    jz .alpha_bad
    cmp r13,1
    jb .alpha_bad
    movzx eax,byte [r12]
    mov ecx,eax
    and ecx,3
    cmp ecx,1
    ja .alpha_bad
    mov [rsp+20],ecx
    shr eax,2
    and eax,3
    mov [rsp],eax                     ; predictor filter
    mov r14d,[rbx+PixBuf_width]
    mov r15d,[rbx+PixBuf_height]
    test r14d,r14d
    jz .alpha_bad
    test r15d,r15d
    jz .alpha_bad
    mov eax,r14d
    imul rax,r15
    jo .alpha_bad
    mov [rsp+16],eax                 ; pixel count, then source step
    cmp dword [rsp+20],0
    jne .alpha_compressed
    inc rax
    cmp r13,rax
    jb .alpha_bad
    inc r12
    mov dword [rsp+16],1
    jmp .alpha_source_ready
.alpha_compressed:
    cmp qword [rsp+24],0
    je .alpha_bad
    mov rsi,r13
    add rsi,4                        ; signature + dimensions + stream
    jc .alpha_bad
    mov rdi,[rsp+24]
    call arena_alloc
    test rax,rax
    jle .alpha_bad
    mov byte [rax],0x2f
    mov edx,r14d
    dec edx
    mov ecx,r15d
    dec ecx
    shl ecx,14
    or edx,ecx
    mov [rax+1],edx
    lea rdi,[rax+5]
    lea rsi,[r12+1]
    mov rcx,r13
    dec rcx
    rep movsb
    mov rdi,[rsp+24]
    mov rsi,rax
    mov rdx,r13
    add rdx,4
    call webp_vp8l_decode
    test rax,rax
    jz .alpha_bad
    mov r12,[rax+PixBuf_data]
    inc r12                          ; green byte carries alpha
    mov dword [rsp+16],4
.alpha_source_ready:
    mov r13,[rbx+PixBuf_data]
    mov dword [rsp+4],0               ; y
.alpha_row:
    mov dword [rsp+8],0               ; x
.alpha_pixel:
    mov eax,[rsp+4]
    imul eax,r14d
    add eax,[rsp+8]
    mov ecx,eax
    imul ecx,[rsp+16]
    movzx edx,byte [r12+rcx]
    mov ecx,[rsp+4]
    imul ecx,[rbx+PixBuf_stride]
    mov esi,[rsp+8]
    shl esi,2
    add ecx,esi
    mov [rsp+12],ecx                 ; BGRA byte offset
    cmp dword [rsp],0
    je .alpha_store
    cmp dword [rsp],1
    je .alpha_horizontal
    cmp dword [rsp],2
    je .alpha_vertical
    xor ecx,ecx                       ; gradient predictor
    cmp dword [rsp+8],0
    je .gradient_no_left
    mov ecx,[rsp+12]
    movzx ecx,byte [r13+rcx-1]
.gradient_no_left:
    xor esi,esi
    cmp dword [rsp+4],0
    je .gradient_no_above
    mov esi,[rsp+12]
    sub esi,[rbx+PixBuf_stride]
    movzx esi,byte [r13+rsi+3]
.gradient_no_above:
    add ecx,esi
    cmp dword [rsp+8],0
    je .gradient_clip
    cmp dword [rsp+4],0
    je .gradient_clip
    mov esi,[rsp+12]
    sub esi,[rbx+PixBuf_stride]
    movzx esi,byte [r13+rsi-1]
    sub ecx,esi
.gradient_clip:
    xor esi,esi
    test ecx,ecx
    cmovs ecx,esi
    mov esi,255
    cmp ecx,esi
    cmova ecx,esi
    add edx,ecx
    jmp .alpha_wrap
.alpha_horizontal:
    cmp dword [rsp+8],0
    jne .alpha_horizontal_left
    cmp dword [rsp+4],0
    je .alpha_store
    mov ecx,[rsp+12]
    sub ecx,[rbx+PixBuf_stride]
    movzx ecx,byte [r13+rcx+3]
    add edx,ecx
    jmp .alpha_wrap
.alpha_horizontal_left:
    mov ecx,[rsp+12]
    movzx ecx,byte [r13+rcx-1]
    add edx,ecx
    jmp .alpha_wrap
.alpha_vertical:
    cmp dword [rsp+4],0
    jne .alpha_vertical_above
    cmp dword [rsp+8],0
    je .alpha_store
    mov ecx,[rsp+12]
    movzx ecx,byte [r13+rcx-1]
    add edx,ecx
    jmp .alpha_wrap
.alpha_vertical_above:
    mov ecx,[rsp+12]
    sub ecx,[rbx+PixBuf_stride]
    movzx ecx,byte [r13+rcx+3]
    add edx,ecx
.alpha_wrap:
    and edx,255
.alpha_store:
    mov ecx,[rsp+12]
    mov [r13+rcx+3],dl
    inc dword [rsp+8]
    cmp [rsp+8],r14d
    jb .alpha_pixel
    inc dword [rsp+4]
    cmp [rsp+4],r15d
    jb .alpha_row
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.alpha_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; arena,VP8L payload,payload length -> PixBuf* or 0.
; Decodes transform subimages, spatial entropy groups, the main image, then
; applies inverse transforms in reverse bitstream order.
global webp_vp8l_decode
webp_vp8l_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,288
    mov rbx,rdi                         ; arena
    mov r12,rsi                         ; payload
    mov r13,rdx                         ; length
    cmp r13,5
    jb .vp8l_bad
    cmp byte [r12],0x2f
    jne .vp8l_bad
    mov eax,[r12+1]
    mov edx,eax
    shr edx,29
    jnz .vp8l_bad
    and eax,0x3fff
    inc eax
    mov [rsp+160],eax                   ; original width
    mov [rsp+168],eax                   ; encoded width
    mov eax,[r12+1]
    shr eax,14
    and eax,0x3fff
    inc eax
    mov [rsp+164],eax                   ; height
    lea rdi,[rsp]
    lea rsi,[r12+5]
    mov rdx,r13
    sub rdx,5
    call webp_bits_init
    test rax,rax
    js .vp8l_bad
    mov dword [rsp+172],0               ; transform count
    mov dword [rsp+176],0               ; transform type mask
    mov dword [rsp+180],0               ; color-index present
.transform_loop:
    lea rdi,[rsp]
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .vp8l_bad
    test eax,eax
    jz .transforms_done
    cmp dword [rsp+172],4
    jae .vp8l_bad
    lea rdi,[rsp]
    mov esi,2
    call webp_bits_get
    test rax,rax
    js .vp8l_bad
    mov r14d,eax                        ; transform type
    mov ecx,eax
    mov edx,1
    shl edx,cl
    test [rsp+176],edx
    jnz .vp8l_bad
    or [rsp+176],edx
    mov eax,[rsp+172]
    shl eax,5
    lea r15,[rsp+32+rax]
    mov [r15+TX_TYPE],r14d
    mov eax,[rsp+168]
    mov [r15+TX_WIDTH],eax
    mov qword [r15+TX_DATA],0
    mov qword [r15+TX_COUNT],0
    cmp r14d,2
    je .transform_recorded
    cmp r14d,3
    je .read_palette
    lea rdi,[rsp]
    mov esi,3
    call webp_bits_get
    test rax,rax
    js .vp8l_bad
    add eax,2
    mov [r15+TX_BITS],eax
    mov ecx,eax
    mov edx,1
    shl edx,cl
    dec edx
    mov eax,[rsp+168]
    add eax,edx
    jc .vp8l_bad
    shr eax,cl
    mov r14d,eax                       ; transform width
    mov eax,[rsp+164]
    add eax,edx
    jc .vp8l_bad
    shr eax,cl
    mov r13d,eax                       ; transform height
    imul eax,r14d
    jo .vp8l_bad
    mov [r15+TX_COUNT],rax
    mov rsi,rax
    shl rsi,2
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jle .vp8l_bad
    mov [r15+TX_DATA],rax
    mov rdi,rsp
    mov rsi,rbx
    mov edx,r14d
    mov ecx,r13d
    mov r8,rax
    xor r9d,r9d
    call webp_decode_image
    test rax,rax
    js .vp8l_bad
    jmp .transform_recorded
.read_palette:
    lea rdi,[rsp]
    mov esi,8
    call webp_bits_get
    test rax,rax
    js .vp8l_bad
    inc eax
    mov [r15+TX_COLORS],eax
    mov [r15+TX_COUNT],rax
    mov r14d,eax
    mov rsi,rax
    shl rsi,2
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jle .vp8l_bad
    mov [r15+TX_DATA],rax
    mov rdi,rsp
    mov rsi,rbx
    mov edx,r14d
    mov ecx,1
    mov r8,rax
    xor r9d,r9d
    call webp_decode_image
    test rax,rax
    js .vp8l_bad
    mov rdi,[r15+TX_DATA]
    mov esi,r14d
    call webp_palette_expand
    test rax,rax
    js .vp8l_bad
    xor eax,eax
    cmp r14d,16
    ja .palette_bits_ready
    mov eax,1
    cmp r14d,4
    ja .palette_bits_ready
    mov eax,2
    cmp r14d,2
    ja .palette_bits_ready
    mov eax,3
.palette_bits_ready:
    mov [r15+TX_BITS],eax
    mov ecx,eax
    mov edx,1
    shl edx,cl
    dec edx
    mov eax,[rsp+168]
    add eax,edx
    jc .vp8l_bad
    shr eax,cl
    mov [rsp+168],eax
    mov dword [rsp+180],1
.transform_recorded:
    inc dword [rsp+172]
    jmp .transform_loop
.transforms_done:
    mov rdi,rbx
    mov esi,[rsp+160]
    mov edx,[rsp+164]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jle .vp8l_bad
    mov r12,rax
    mov [rsp+192],rax                  ; PixBuf
    mov r13,[rax+PixBuf_data]
    cmp dword [rsp+180],0
    je .main_buffer_ready
    mov eax,[rsp+168]
    imul eax,[rsp+164]
    jo .vp8l_bad
    mov rsi,rax
    shl rsi,2
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jle .vp8l_bad
    mov r13,rax
.main_buffer_ready:
    mov [rsp+200],r13                  ; current pixel buffer
    lea rdi,[rsp]
    mov rsi,rbx
    mov edx,[rsp+168]
    mov ecx,[rsp+164]
    mov r8,r13
    mov r9d,1
    call webp_decode_image
    test rax,rax
    js .vp8l_bad
    mov eax,[rsp+172]
    mov [rsp+184],eax                  ; reverse transform index
.inverse_loop:
    cmp dword [rsp+184],0
    je .inverse_done
    dec dword [rsp+184]
    mov eax,[rsp+184]
    shl eax,5
    lea r15,[rsp+32+rax]
    mov eax,[r15+TX_TYPE]
    cmp eax,0
    je .inverse_predictor
    cmp eax,1
    je .inverse_color
    cmp eax,2
    je .inverse_green
    cmp eax,3
    jne .vp8l_bad
    lea rdi,[rsp+224]
    mov rax,[rsp+200]
    mov [rdi+WebPIndexState.packed],rax
    mov rax,[rsp+192]
    mov rax,[rax+PixBuf_data]
    mov [rdi+WebPIndexState.output],rax
    mov rax,[r15+TX_DATA]
    mov [rdi+WebPIndexState.palette],rax
    mov eax,[r15+TX_WIDTH]
    mov [rdi+WebPIndexState.width],eax
    mov eax,[rsp+164]
    mov [rdi+WebPIndexState.height],eax
    mov eax,[rsp+168]
    mov [rdi+WebPIndexState.packed_width],eax
    mov eax,[r15+TX_COLORS]
    mov [rdi+WebPIndexState.palette_count],eax
    mov eax,[r15+TX_BITS]
    mov [rdi+WebPIndexState.width_bits],eax
    call webp_inverse_color_index
    test rax,rax
    js .vp8l_bad
    mov rax,[rsp+192]
    mov rax,[rax+PixBuf_data]
    mov [rsp+200],rax
    mov eax,[r15+TX_WIDTH]
    mov [rsp+168],eax
    jmp .inverse_loop
.inverse_green:
    mov rdi,[rsp+200]
    mov eax,[rsp+168]
    imul eax,[rsp+164]
    jo .vp8l_bad
    mov esi,eax
    call webp_inverse_subtract_green
    test rax,rax
    js .vp8l_bad
    jmp .inverse_loop
.inverse_color:
    mov rdi,[rsp+200]
    mov esi,[rsp+168]
    mov edx,[rsp+164]
    mov rcx,[r15+TX_DATA]
    mov r8d,[r15+TX_BITS]
    mov r9,[r15+TX_COUNT]
    call webp_inverse_color
    test rax,rax
    js .vp8l_bad
    jmp .inverse_loop
.inverse_predictor:
    lea rdi,[rsp+224]
    mov rax,[rsp+200]
    mov [rdi+WebPPredictState.pixels],rax
    mov rax,[r15+TX_DATA]
    mov [rdi+WebPPredictState.modes],rax
    mov eax,[rsp+168]
    mov [rdi+WebPPredictState.width],eax
    mov eax,[rsp+164]
    mov [rdi+WebPPredictState.height],eax
    mov eax,[r15+TX_BITS]
    mov [rdi+WebPPredictState.size_bits],eax
    mov eax,[r15+TX_COUNT]
    mov [rdi+WebPPredictState.mode_count],eax
    call webp_inverse_predictor
    test rax,rax
    js .vp8l_bad
    jmp .inverse_loop
.inverse_done:
    mov rax,[rsp+192]
    add rsp,288
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.vp8l_bad:
    xor eax,eax
    add rsp,288
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

section .data
global webp_decode_version
webp_decode_version: dq 0x010000
