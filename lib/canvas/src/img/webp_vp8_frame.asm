; Complete VP8 key-frame raster pipeline for lossy WebP.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern arena_alloc
extern pixbuf_create
extern webp_bool_init
extern webp_bool_get
extern webp_bool_literal
extern webp_vp8_inspect
extern webp_vp8_parse_config
extern webp_vp8_parse_partitions
extern webp_vp8_coeff_probs_init
extern webp_vp8_coeff_probs_update
extern webp_vp8_decode_mb_header
extern webp_vp8_decode_macroblock_residual
extern webp_vp8_alloc_frame_planes
extern webp_vp8_render_macroblock
extern webp_vp8_yuv420_to_bgra
extern webp_vp8_filter_frame

%define F_INFO          0
%define F_FIRST        48
%define F_CONFIG       80
%define F_PARTS       224
%define F_READERS     368
%define F_PROBS       624
%define F_PLANES     1680
%define F_HEADER     1720
%define F_COEFFS     1752
%define F_RENDER     2552
%define F_RESIDUAL   2616
%define F_YUV        2664
%define F_PIXBUF     2720
%define F_ABOVE_RES  2728
%define F_ABOVE_MODE 2736
%define F_MB_COLS    2744
%define F_MB_ROWS    2748
%define F_ROW        2752
%define F_COL        2756
%define F_SKIP       2760
%define F_SKIP_PROB  2764
%define F_LEFT_RES   2768              ; 9 used; row reset clears through F_LEFT_MODE
%define F_LEFT_MODE  2784
%define F_META       2792
%define F_FILTER     2800
%define F_SIZE       2864

section .text

; arena,VP8 payload,payload length -> PixBuf* or 0.
global webp_vp8_decode
webp_vp8_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,F_SIZE
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test rbx,rbx
    jz .bad
    mov rdi,r12
    mov rsi,r13
    lea rdx,[rsp+F_INFO]
    call webp_vp8_inspect
    test eax,eax
    js .bad
    lea rdi,[rsp+F_FIRST]
    mov rsi,[rsp+F_INFO+WebPVP8Info.first]
    mov rdx,[rsp+F_INFO+WebPVP8Info.first_len]
    call webp_bool_init
    test eax,eax
    js .bad
    lea rdi,[rsp+F_FIRST]
    lea rsi,[rsp+F_CONFIG]
    call webp_vp8_parse_config
    test eax,eax
    js .bad
    lea rdi,[rsp+F_PROBS]
    call webp_vp8_coeff_probs_init
    test eax,eax
    js .bad
    lea rdi,[rsp+F_FIRST]
    lea rsi,[rsp+F_PROBS]
    call webp_vp8_coeff_probs_update
    test eax,eax
    js .bad
    lea rdi,[rsp+F_FIRST]
    mov esi,128
    call webp_bool_get
    test eax,eax
    js .bad
    mov [rsp+F_SKIP],eax
    mov dword [rsp+F_SKIP_PROB],0
    test eax,eax
    jz .skip_ready
    lea rdi,[rsp+F_FIRST]
    mov esi,8
    call webp_bool_literal
    test eax,eax
    js .bad
    mov [rsp+F_SKIP_PROB],eax
.skip_ready:
    mov rdi,[rsp+F_INFO+WebPVP8Info.tokens]
    mov rsi,[rsp+F_INFO+WebPVP8Info.tokens_len]
    mov edx,[rsp+F_CONFIG+WebPVP8Config.token_partitions]
    lea rcx,[rsp+F_PARTS]
    call webp_vp8_parse_partitions
    test eax,eax
    js .bad
    xor r14d,r14d
.reader_init:
    lea rdi,[rsp+F_READERS]
    mov eax,r14d
    shl eax,5
    add rdi,rax
    mov rsi,[rsp+F_PARTS+WebPVP8Partitions.data+r14*8]
    mov rdx,[rsp+F_PARTS+WebPVP8Partitions.length+r14*8]
    call webp_bool_init
    test eax,eax
    js .bad
    inc r14d
    cmp r14d,[rsp+F_PARTS+WebPVP8Partitions.count]
    jb .reader_init
    mov eax,[rsp+F_INFO+WebPVP8Info.width]
    add eax,15
    shr eax,4
    mov [rsp+F_MB_COLS],eax
    mov eax,[rsp+F_INFO+WebPVP8Info.height]
    add eax,15
    shr eax,4
    mov [rsp+F_MB_ROWS],eax
    mov rdi,rbx
    mov esi,[rsp+F_INFO+WebPVP8Info.width]
    mov edx,[rsp+F_INFO+WebPVP8Info.height]
    lea rcx,[rsp+F_PLANES]
    call webp_vp8_alloc_frame_planes
    test eax,eax
    js .bad
    mov eax,[rsp+F_MB_COLS]
    imul eax,9
    mov rsi,rax
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+F_ABOVE_RES],rax
    mov rdi,rax
    xor eax,eax
    mov ecx,[rsp+F_MB_COLS]
    imul ecx,9
    rep stosb
    mov eax,[rsp+F_MB_COLS]
    shl eax,2
    mov rsi,rax
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+F_ABOVE_MODE],rax
    mov rdi,rax
    xor eax,eax
    mov ecx,[rsp+F_MB_COLS]
    shl ecx,2
    rep stosb
    mov eax,[rsp+F_MB_COLS]
    imul eax,[rsp+F_MB_ROWS]
    shl eax,2
    mov rsi,rax
    mov rdi,rbx
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+F_META],rax
    mov rdi,rax
    xor eax,eax
    mov ecx,[rsp+F_MB_COLS]
    imul ecx,[rsp+F_MB_ROWS]
    rep stosd
    mov rdi,rbx
    mov esi,[rsp+F_INFO+WebPVP8Info.width]
    mov edx,[rsp+F_INFO+WebPVP8Info.height]
    mov ecx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jle .bad
    mov [rsp+F_PIXBUF],rax
    mov dword [rsp+F_ROW],0
.row:
    lea rdi,[rsp+F_LEFT_RES]
    xor eax,eax
    mov ecx,3
    rep stosq
    mov dword [rsp+F_COL],0
.column:
    ; Per-macroblock modes live in the first partition (RFC 6386 section 19.3);
    ; only the residual tokens come from the row's token partition.
    lea rdi,[rsp+F_FIRST]
    lea rsi,[rsp+F_CONFIG]
    mov edx,[rsp+F_SKIP]
    mov ecx,[rsp+F_SKIP_PROB]
    mov eax,[rsp+F_COL]
    shl eax,2
    mov r8,[rsp+F_ABOVE_MODE]
    add r8,rax
    lea r9,[rsp+F_LEFT_MODE]
    lea rax,[rsp+F_HEADER]
    push rax
    call webp_vp8_decode_mb_header
    add rsp,8
    test eax,eax
    js .bad
    call .update_modes
    cmp dword [rsp+F_HEADER+WebPVP8MBHeader.skip_coeff],0
    jne .zero_residual
    lea rdi,[rsp+F_RESIDUAL]
    mov eax,[rsp+F_ROW]
    mov ecx,[rsp+F_PARTS+WebPVP8Partitions.count]
    dec ecx
    and eax,ecx
    shl eax,5
    lea rax,[rsp+F_READERS+rax]
    mov [rdi+WebPVP8ResidualState.reader],rax
    lea rax,[rsp+F_PROBS]
    mov [rdi+WebPVP8ResidualState.probs],rax
    lea rax,[rsp+F_COEFFS]
    mov [rdi+WebPVP8ResidualState.coeffs],rax
    mov eax,[rsp+F_COL]
    imul eax,9
    mov rdx,[rsp+F_ABOVE_RES]
    add rdx,rax
    mov [rdi+WebPVP8ResidualState.above],rdx
    lea rax,[rsp+F_LEFT_RES]
    mov [rdi+WebPVP8ResidualState.left],rax
    mov eax,[rsp+F_HEADER+WebPVP8MBHeader.y_mode]
    mov [rdi+WebPVP8ResidualState.y_mode],eax
    call webp_vp8_decode_macroblock_residual
    test eax,eax
    js .bad
    jmp .render
.zero_residual:
    ; A skipped macroblock clears its non-zero contexts; the Y2 context is
    ; only touched when the macroblock actually has a Y2 block (not B_PRED).
    lea rdi,[rsp+F_COEFFS]
    xor eax,eax
    mov ecx,100
    rep stosq
    mov ecx,8
    cmp dword [rsp+F_HEADER+WebPVP8MBHeader.y_mode],VP8_Y_MODE_B_PRED
    je .zero_contexts
    inc ecx
.zero_contexts:
    mov r8d,ecx
    mov edx,[rsp+F_COL]
    imul edx,9
    mov rdi,[rsp+F_ABOVE_RES]
    add rdi,rdx
    rep stosb
    lea rdi,[rsp+F_LEFT_RES]
    mov ecx,r8d
    rep stosb
.render:
    call .store_meta
    lea rdi,[rsp+F_RENDER]
    lea rax,[rsp+F_CONFIG]
    mov [rdi+WebPVP8RenderMBState.config],rax
    lea rax,[rsp+F_HEADER]
    mov [rdi+WebPVP8RenderMBState.header],rax
    lea rax,[rsp+F_COEFFS]
    mov [rdi+WebPVP8RenderMBState.coeffs],rax
    mov eax,[rsp+F_ROW]
    shl eax,4
    imul eax,[rsp+F_PLANES+WebPVP8FramePlanes.y_stride]
    mov edx,[rsp+F_COL]
    shl edx,4
    add eax,edx
    mov rdx,[rsp+F_PLANES+WebPVP8FramePlanes.y]
    add rdx,rax
    mov [rdi+WebPVP8RenderMBState.y],rdx
    mov eax,[rsp+F_ROW]
    shl eax,3
    imul eax,[rsp+F_PLANES+WebPVP8FramePlanes.uv_stride]
    mov edx,[rsp+F_COL]
    shl edx,3
    add eax,edx
    mov rdx,[rsp+F_PLANES+WebPVP8FramePlanes.u]
    add rdx,rax
    mov [rdi+WebPVP8RenderMBState.u],rdx
    mov rdx,[rsp+F_PLANES+WebPVP8FramePlanes.v]
    add rdx,rax
    mov [rdi+WebPVP8RenderMBState.v],rdx
    mov eax,[rsp+F_PLANES+WebPVP8FramePlanes.y_stride]
    mov [rdi+WebPVP8RenderMBState.y_stride],eax
    mov eax,[rsp+F_PLANES+WebPVP8FramePlanes.uv_stride]
    mov [rdi+WebPVP8RenderMBState.uv_stride],eax
    xor eax,eax
    cmp dword [rsp+F_COL],0
    jne .flags_not_left
    or eax,VP8_MB_LEFT_EDGE
.flags_not_left:
    cmp dword [rsp+F_ROW],0
    jne .flags_not_top
    or eax,VP8_MB_TOP_EDGE
.flags_not_top:
    mov edx,[rsp+F_COL]
    inc edx
    cmp edx,[rsp+F_MB_COLS]
    jne .flags_ready
    or eax,VP8_MB_RIGHT_EDGE
.flags_ready:
    mov [rdi+WebPVP8RenderMBState.mb_flags],eax
    call webp_vp8_render_macroblock
    test eax,eax
    js .bad
    inc dword [rsp+F_COL]
    mov eax,[rsp+F_COL]
    cmp eax,[rsp+F_MB_COLS]
    jb .column
    inc dword [rsp+F_ROW]
    mov eax,[rsp+F_ROW]
    cmp eax,[rsp+F_MB_ROWS]
    jb .row
    lea rdi,[rsp+F_FILTER]
    mov rax,[rsp+F_PLANES+WebPVP8FramePlanes.y]
    mov [rdi+WebPVP8FilterFrameState.y],rax
    mov rax,[rsp+F_PLANES+WebPVP8FramePlanes.u]
    mov [rdi+WebPVP8FilterFrameState.u],rax
    mov rax,[rsp+F_PLANES+WebPVP8FramePlanes.v]
    mov [rdi+WebPVP8FilterFrameState.v],rax
    lea rax,[rsp+F_CONFIG]
    mov [rdi+WebPVP8FilterFrameState.config],rax
    mov rax,[rsp+F_META]
    mov [rdi+WebPVP8FilterFrameState.meta],rax
    mov eax,[rsp+F_PLANES+WebPVP8FramePlanes.y_stride]
    mov [rdi+WebPVP8FilterFrameState.y_stride],eax
    mov eax,[rsp+F_PLANES+WebPVP8FramePlanes.uv_stride]
    mov [rdi+WebPVP8FilterFrameState.uv_stride],eax
    mov eax,[rsp+F_MB_COLS]
    mov [rdi+WebPVP8FilterFrameState.mb_cols],eax
    mov eax,[rsp+F_MB_ROWS]
    mov [rdi+WebPVP8FilterFrameState.mb_rows],eax
    call webp_vp8_filter_frame
    test eax,eax
    js .bad
    lea rdi,[rsp+F_YUV]
    mov rax,[rsp+F_PLANES+WebPVP8FramePlanes.y]
    mov [rdi+WebPYUVState.y],rax
    mov rax,[rsp+F_PLANES+WebPVP8FramePlanes.u]
    mov [rdi+WebPYUVState.u],rax
    mov rax,[rsp+F_PLANES+WebPVP8FramePlanes.v]
    mov [rdi+WebPYUVState.v],rax
    mov rax,[rsp+F_PIXBUF]
    mov rdx,[rax+PixBuf_data]
    mov [rdi+WebPYUVState.output],rdx
    mov edx,[rsp+F_INFO+WebPVP8Info.width]
    mov [rdi+WebPYUVState.width],edx
    mov edx,[rsp+F_INFO+WebPVP8Info.height]
    mov [rdi+WebPYUVState.height],edx
    mov edx,[rsp+F_PLANES+WebPVP8FramePlanes.y_stride]
    mov [rdi+WebPYUVState.y_stride],edx
    mov edx,[rsp+F_PLANES+WebPVP8FramePlanes.uv_stride]
    mov [rdi+WebPYUVState.uv_stride],edx
    mov edx,[rax+PixBuf_stride]
    mov [rdi+WebPYUVState.output_stride],edx
    call webp_vp8_yuv420_to_bgra
    test eax,eax
    js .bad
    mov rax,[rsp+F_PIXBUF]
    add rsp,F_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.bad:
    xor eax,eax
    add rsp,F_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; Propagate the current macroblock's bottom/right 4x4 modes.
.update_modes:
    mov eax,[rsp+8+F_COL]
    shl eax,2
    mov rdx,[rsp+8+F_ABOVE_MODE]
    add rdx,rax
    lea rcx,[rsp+8+F_LEFT_MODE]
    cmp dword [rsp+8+F_HEADER+WebPVP8MBHeader.y_mode],VP8_Y_MODE_B_PRED
    jne .uniform_modes
    mov eax,[rsp+8+F_HEADER+WebPVP8MBHeader.b_modes+12]
    mov [rdx],eax
    mov al,[rsp+8+F_HEADER+WebPVP8MBHeader.b_modes+3]
    mov [rcx],al
    mov al,[rsp+8+F_HEADER+WebPVP8MBHeader.b_modes+7]
    mov [rcx+1],al
    mov al,[rsp+8+F_HEADER+WebPVP8MBHeader.b_modes+11]
    mov [rcx+2],al
    mov al,[rsp+8+F_HEADER+WebPVP8MBHeader.b_modes+15]
    mov [rcx+3],al
    ret
.uniform_modes:
    mov eax,[rsp+8+F_HEADER+WebPVP8MBHeader.y_mode]
    lea r8,[rel vp8_y_to_bmode]
    mov al,[r8+rax]
    mov [rdx],al
    mov [rdx+1],al
    mov [rdx+2],al
    mov [rdx+3],al
    mov [rcx],al
    mov [rcx+1],al
    mov [rcx+2],al
    mov [rcx+3],al
    ret

; Save segment, Y mode, and whether this macroblock has non-zero residue.
.store_meta:
    mov eax,[rsp+8+F_ROW]
    imul eax,[rsp+8+F_MB_COLS]
    add eax,[rsp+8+F_COL]
    shl eax,2
    mov rdx,[rsp+8+F_META]
    add rdx,rax
    mov al,[rsp+8+F_HEADER+WebPVP8MBHeader.segment_id]
    mov [rdx],al
    mov al,[rsp+8+F_HEADER+WebPVP8MBHeader.y_mode]
    mov [rdx+1],al
    mov byte [rdx+2],0
    lea rax,[rsp+8+F_COEFFS]
    xor ecx,ecx
.meta_scan:
    cmp word [rax+rcx*2],0
    jne .meta_nonzero
    inc ecx
    cmp ecx,25*16
    jb .meta_scan
    ret
.meta_nonzero:
    mov byte [rdx+2],1
    ret

section .rodata
vp8_y_to_bmode: db VP8_BMODE_DC,VP8_BMODE_VE,VP8_BMODE_HE,VP8_BMODE_TM

section .data
global webp_vp8_frame_version
webp_vp8_frame_version: dq 0x010000
