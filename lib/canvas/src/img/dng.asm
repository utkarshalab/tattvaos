; Baseline uncompressed DNG/TIFF adapter for the native sensor pipeline.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern tiff_read_u16
extern tiff_read_u32
extern sensor_process
extern arena_alloc
extern tiff_decompress_block
extern tiff_undo_predictor_block
extern jpeg_lossless_decode
extern dng_prepare_color_matrix

%define TIFF_WIDTH       256
%define TIFF_HEIGHT      257
%define TIFF_BITS        258
%define TIFF_COMPRESSION 259
%define TIFF_PHOTOMETRIC 262
%define TIFF_STRIP_OFF   273
%define TIFF_SAMPLES     277
%define TIFF_ROWS_STRIP  278
%define TIFF_STRIP_COUNT 279
%define TIFF_PREDICTOR   317
%define TIFF_TILE_WIDTH  322
%define TIFF_TILE_HEIGHT 323
%define TIFF_TILE_OFF    324
%define TIFF_TILE_COUNT  325
%define DNG_CFA_PATTERN  33422
%define DNG_BLACK_LEVEL  50714
%define DNG_WHITE_LEVEL  50717
%define DNG_CROP_ORIGIN  50719
%define DNG_CROP_SIZE    50720
%define DNG_COLOR_MATRIX 50721
%define DNG_AS_SHOT_NEUTRAL 50728
%define DNG_ACTIVE_AREA  50829

%define D_BE        112
%define D_COMP      116
%define D_ROWS      120
%define D_NSTRIPS   124
%define D_OFFTYPE   128
%define D_CNTTYPE   132
%define D_OFFVAL    136
%define D_CNTVAL    144
%define D_PRED      152
%define D_RASTER    160
%define D_ROWBYTES  168
%define D_CURROWS   172
%define D_FIRSTROW  176
%define D_ACTIVEVAL 184
%define D_ACTIVETYPE 192
%define D_ACTIVECOUNT 196
%define D_ORIGINVAL 200
%define D_ORIGINTYPE 208
%define D_ORIGINCOUNT 212
%define D_SIZEVAL   216
%define D_SIZETYPE 224
%define D_SIZECOUNT 228
%define D_CROPW     232
%define D_CROPH     236
%define D_NEUTRALVAL 240
%define D_NEUTRALTYPE 248
%define D_NEUTRALCOUNT 252
%define D_MATRIXVAL 256
%define D_MATRIXTYPE 264
%define D_MATRIXCOUNT 268
%define D_BLACKVAL  272
%define D_BLACKTYPE 280
%define D_BLACKCOUNT 284
%define D_STORAGE   288
%define D_TILEW     292
%define D_TILEH     296
%define D_TILESX    300
%define D_TILESY    304
%define D_SCRATCH   312
%define D_TILEBYTES 320
%define D_TILEROW   324
%define D_TILEINDEX 328
%define D_TILEX     332
%define D_TILEY     336
%define D_VALIDW    340
%define D_VALIDH    344
%define D_COPYROW   348
%define D_LOCAL     368

section .text
global dng_probe
dng_probe:
    PROLOGUE
    cmp rsi,8
    jb .no
    xor edx,edx
    cmp word [rdi],0x4949
    je .order
    cmp word [rdi],0x4d4d
    jne .no
    mov edx,1
.order:
    push rdi
    lea rdi,[rdi+2]
    mov esi,edx
    call tiff_read_u16
    pop rdi
    cmp eax,42
    jne .no
    mov eax,1
    leave
    ret
.no:
    xor eax,eax
    leave
    ret

; IN arena,data,len. Decodes strip- or tile-organized CFA DNG into the sensor pipeline.
global dng_decode
dng_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,D_LOCAL
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov rdi,r12
    mov rsi,r13
    call dng_probe
    test rax,rax
    jz .bad
    xor eax,eax
    cmp word [r12],0x4d4d
    sete al
    mov [rsp+D_BE],eax
    mov rdi,rsp
    xor eax,eax
    mov rcx,SensorImageDesc_size/8
    rep stosq
    mov dword [rsp+SensorImageDesc.bit_depth],16
    mov dword [rsp+SensorImageDesc.cfa],SENSOR_CFA_RGGB
    mov dword [rsp+SensorImageDesc.black_level],0
    mov dword [rsp+SensorImageDesc.white_level],65535
    mov dword [rsp+SensorImageDesc.wb_r],0x10000
    mov dword [rsp+SensorImageDesc.wb_g],0x10000
    mov dword [rsp+SensorImageDesc.wb_b],0x10000
    mov dword [rsp+SensorImageDesc.color_matrix+0],0x10000
    mov dword [rsp+SensorImageDesc.color_matrix+16],0x10000
    mov dword [rsp+SensorImageDesc.color_matrix+32],0x10000
    mov dword [rsp+D_COMP],1
    mov dword [rsp+D_ROWS],0xffffffff
    mov dword [rsp+D_NSTRIPS],0
    mov dword [rsp+D_PRED],1
    mov dword [rsp+D_ACTIVECOUNT],0
    mov dword [rsp+D_ORIGINCOUNT],0
    mov dword [rsp+D_SIZECOUNT],0
    mov dword [rsp+D_NEUTRALCOUNT],0
    mov dword [rsp+D_MATRIXCOUNT],0
    mov dword [rsp+D_BLACKCOUNT],0
    mov dword [rsp+D_STORAGE],0
    lea rdi,[r12+4]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    cmp rax,r13
    jae .bad
    lea r14,[r12+rax]
    mov rdi,r14
    mov esi,[rsp+D_BE]
    call tiff_read_u16
    mov r15d,eax
    add r14,2
.entry:
    test r15d,r15d
    jz .parsed
    mov rax,r14
    sub rax,r12
    add rax,12
    cmp rax,r13
    ja .bad
    mov rdi,r14
    mov esi,[rsp+D_BE]
    call tiff_read_u16
    mov r9d,eax
    lea rdi,[r14+2]
    mov esi,[rsp+D_BE]
    call tiff_read_u16
    mov ecx,eax
    lea rdi,[r14+4]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    mov edx,eax
    lea rdi,[r14+8]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    mov r8d,eax
    mov eax,r9d
    cmp eax,TIFF_WIDTH
    je .width
    cmp eax,TIFF_HEIGHT
    je .height
    cmp eax,TIFF_BITS
    je .bits
    cmp eax,TIFF_COMPRESSION
    je .compression
    cmp eax,TIFF_SAMPLES
    je .samples
    cmp eax,TIFF_STRIP_OFF
    je .strip
    cmp eax,TIFF_ROWS_STRIP
    je .rows
    cmp eax,TIFF_STRIP_COUNT
    je .strip_counts
    cmp eax,TIFF_PREDICTOR
    je .predictor
    cmp eax,TIFF_TILE_WIDTH
    je .tile_width
    cmp eax,TIFF_TILE_HEIGHT
    je .tile_height
    cmp eax,TIFF_TILE_OFF
    je .tile_offsets
    cmp eax,TIFF_TILE_COUNT
    je .tile_counts
    cmp eax,DNG_CFA_PATTERN
    je .cfa
    cmp eax,DNG_BLACK_LEVEL
    je .black
    cmp eax,DNG_WHITE_LEVEL
    je .white
    cmp eax,DNG_ACTIVE_AREA
    je .active_area
    cmp eax,DNG_CROP_ORIGIN
    je .crop_origin
    cmp eax,DNG_CROP_SIZE
    je .crop_size
    cmp eax,DNG_AS_SHOT_NEUTRAL
    je .neutral
    cmp eax,DNG_COLOR_MATRIX
    je .matrix
    jmp .next
.width:
    call .scalar
    mov [rsp+SensorImageDesc.width],eax
    jmp .next
.height:
    call .scalar
    mov [rsp+SensorImageDesc.height],eax
    jmp .next
.bits:
    call .scalar
    mov [rsp+SensorImageDesc.bit_depth],eax
    jmp .next
.compression:
    call .scalar
    mov [rsp+D_COMP],eax
    jmp .next
.samples:
    call .scalar
    cmp eax,1
    jne .bad
    jmp .next
.strip:
    cmp dword [rsp+D_STORAGE],1
    je .bad
    mov [rsp+D_NSTRIPS],edx
    mov [rsp+D_OFFTYPE],ecx
    mov [rsp+D_OFFVAL],r8
    jmp .next
.rows:
    call .scalar
    mov [rsp+D_ROWS],eax
    jmp .next
.strip_counts:
    cmp dword [rsp+D_STORAGE],1
    je .bad
    cmp dword [rsp+D_NSTRIPS],0
    jne .strip_count_match
    mov [rsp+D_NSTRIPS],edx
.strip_count_match:
    cmp [rsp+D_NSTRIPS],edx
    jne .bad
    mov [rsp+D_CNTTYPE],ecx
    mov [rsp+D_CNTVAL],r8
    jmp .next
.tile_width:
    call .scalar
    mov [rsp+D_TILEW],eax
    mov dword [rsp+D_STORAGE],1
    jmp .next
.tile_height:
    call .scalar
    mov [rsp+D_TILEH],eax
    mov dword [rsp+D_STORAGE],1
    jmp .next
.tile_offsets:
    mov dword [rsp+D_STORAGE],1
    mov [rsp+D_NSTRIPS],edx
    mov [rsp+D_OFFTYPE],ecx
    mov [rsp+D_OFFVAL],r8
    jmp .next
.tile_counts:
    mov dword [rsp+D_STORAGE],1
    cmp dword [rsp+D_NSTRIPS],0
    jne .tile_count_match
    mov [rsp+D_NSTRIPS],edx
.tile_count_match:
    cmp [rsp+D_NSTRIPS],edx
    jne .bad
    mov [rsp+D_CNTTYPE],ecx
    mov [rsp+D_CNTVAL],r8
    jmp .next
.predictor:
    call .scalar
    mov [rsp+D_PRED],eax
    jmp .next
.black:
    mov [rsp+D_BLACKCOUNT],edx
    mov [rsp+D_BLACKTYPE],ecx
    mov [rsp+D_BLACKVAL],r8
    jmp .next
.white:
    cmp edx,1
    jne .next
    call .scalar
    mov [rsp+SensorImageDesc.white_level],eax
    jmp .next
.active_area:
    mov [rsp+D_ACTIVECOUNT],edx
    mov [rsp+D_ACTIVETYPE],ecx
    mov [rsp+D_ACTIVEVAL],r8
    jmp .next
.crop_origin:
    mov [rsp+D_ORIGINCOUNT],edx
    mov [rsp+D_ORIGINTYPE],ecx
    mov [rsp+D_ORIGINVAL],r8
    jmp .next
.crop_size:
    mov [rsp+D_SIZECOUNT],edx
    mov [rsp+D_SIZETYPE],ecx
    mov [rsp+D_SIZEVAL],r8
    jmp .next
.neutral:
    mov [rsp+D_NEUTRALCOUNT],edx
    mov [rsp+D_NEUTRALTYPE],ecx
    mov [rsp+D_NEUTRALVAL],r8
    jmp .next
.matrix:
    mov [rsp+D_MATRIXCOUNT],edx
    mov [rsp+D_MATRIXTYPE],ecx
    mov [rsp+D_MATRIXVAL],r8
    jmp .next
.cfa:
    cmp edx,4
    jne .next
    ; BYTE values keep file order regardless of TIFF integer endianness.
    cmp byte [r14+8],0
    jne .cfa_bggr
    cmp byte [r14+9],1
    jne .next
    cmp byte [r14+10],1
    jne .next
    cmp byte [r14+11],2             ; RGGB
    je .next
    jmp .next
.cfa_bggr:
    cmp byte [r14+8],2
    jne .cfa_grbg
    cmp byte [r14+9],1
    jne .next
    cmp byte [r14+10],1
    jne .next
    cmp byte [r14+11],0             ; BGGR
    jne .next
    mov dword [rsp+SensorImageDesc.cfa],SENSOR_CFA_BGGR
    jmp .next
.cfa_grbg:
    cmp byte [r14+8],1
    jne .next
    cmp byte [r14+9],0
    jne .cfa_gbrg
    cmp byte [r14+10],2
    jne .next
    cmp byte [r14+11],1             ; GRBG
    jne .next
    mov dword [rsp+SensorImageDesc.cfa],SENSOR_CFA_GRBG
    jmp .next
.cfa_gbrg:
    cmp byte [r14+9],2
    jne .next
    cmp byte [r14+10],0
    jne .next
    cmp byte [r14+11],1             ; GBRG
    jne .next
    mov dword [rsp+SensorImageDesc.cfa],SENSOR_CFA_GBRG
.next:
    add r14,12
    dec r15d
    jmp .entry
.parsed:
    mov eax,[rsp+SensorImageDesc.width]
    test eax,eax
    jz .bad
    mov ecx,[rsp+SensorImageDesc.bit_depth]
    mov dword [rsp+SensorImageDesc.crop_x],0
    mov dword [rsp+SensorImageDesc.crop_y],0
    mov [rsp+D_CROPW],eax
    mov edx,[rsp+SensorImageDesc.height]
    mov [rsp+D_CROPH],edx
    cmp dword [rsp+D_ACTIVECOUNT],4
    jne .crop_origin_meta
    mov rdi,[rsp+D_ACTIVEVAL]
    mov esi,[rsp+D_ACTIVETYPE]
    mov edx,[rsp+D_ACTIVECOUNT]
    xor ecx,ecx
    call .meta_value
    jc .bad
    mov [rsp+SensorImageDesc.crop_y],eax
    mov rdi,[rsp+D_ACTIVEVAL]
    mov esi,[rsp+D_ACTIVETYPE]
    mov edx,[rsp+D_ACTIVECOUNT]
    mov ecx,1
    call .meta_value
    jc .bad
    mov [rsp+SensorImageDesc.crop_x],eax
    mov rdi,[rsp+D_ACTIVEVAL]
    mov esi,[rsp+D_ACTIVETYPE]
    mov edx,[rsp+D_ACTIVECOUNT]
    mov ecx,2
    call .meta_value
    jc .bad
    sub eax,[rsp+SensorImageDesc.crop_y]
    jbe .bad
    mov [rsp+D_CROPH],eax
    mov rdi,[rsp+D_ACTIVEVAL]
    mov esi,[rsp+D_ACTIVETYPE]
    mov edx,[rsp+D_ACTIVECOUNT]
    mov ecx,3
    call .meta_value
    jc .bad
    sub eax,[rsp+SensorImageDesc.crop_x]
    jbe .bad
    mov [rsp+D_CROPW],eax
.crop_origin_meta:
    cmp dword [rsp+D_ORIGINCOUNT],2
    jne .crop_size_meta
    mov rdi,[rsp+D_ORIGINVAL]
    mov esi,[rsp+D_ORIGINTYPE]
    mov edx,[rsp+D_ORIGINCOUNT]
    xor ecx,ecx
    call .meta_value
    jc .bad
    add [rsp+SensorImageDesc.crop_x],eax
    jc .bad
    mov rdi,[rsp+D_ORIGINVAL]
    mov esi,[rsp+D_ORIGINTYPE]
    mov edx,[rsp+D_ORIGINCOUNT]
    mov ecx,1
    call .meta_value
    jc .bad
    add [rsp+SensorImageDesc.crop_y],eax
    jc .bad
.crop_size_meta:
    cmp dword [rsp+D_SIZECOUNT],2
    jne .crop_validate
    mov rdi,[rsp+D_SIZEVAL]
    mov esi,[rsp+D_SIZETYPE]
    mov edx,[rsp+D_SIZECOUNT]
    xor ecx,ecx
    call .meta_value
    jc .bad
    test eax,eax
    jz .bad
    mov [rsp+D_CROPW],eax
    mov rdi,[rsp+D_SIZEVAL]
    mov esi,[rsp+D_SIZETYPE]
    mov edx,[rsp+D_SIZECOUNT]
    mov ecx,1
    call .meta_value
    jc .bad
    test eax,eax
    jz .bad
    mov [rsp+D_CROPH],eax
.crop_validate:
    mov eax,[rsp+SensorImageDesc.crop_x]
    add eax,[rsp+D_CROPW]
    jc .bad
    cmp eax,[rsp+SensorImageDesc.width]
    ja .bad
    mov eax,[rsp+SensorImageDesc.crop_y]
    add eax,[rsp+D_CROPH]
    jc .bad
    cmp eax,[rsp+SensorImageDesc.height]
    ja .bad
.black_meta:
    mov ecx,[rsp+D_BLACKCOUNT]
    test ecx,ecx
    jz .neutral_meta
    cmp ecx,64
    ja .bad
    mov qword [rsp+D_RASTER],0
    mov dword [rsp+D_CURROWS],0
.black_loop:
    mov ecx,[rsp+D_CURROWS]
    cmp ecx,[rsp+D_BLACKCOUNT]
    jae .black_done
    mov rdi,[rsp+D_BLACKVAL]
    mov esi,[rsp+D_BLACKTYPE]
    mov edx,[rsp+D_BLACKCOUNT]
    call .meta_value
    jc .bad
    add [rsp+D_RASTER],rax
    jc .bad
    inc dword [rsp+D_CURROWS]
    jmp .black_loop
.black_done:
    mov rax,[rsp+D_RASTER]
    xor edx,edx
    div dword [rsp+D_BLACKCOUNT]
    mov [rsp+SensorImageDesc.black_level],eax
.neutral_meta:
    cmp dword [rsp+D_NEUTRALCOUNT],3
    jne .matrix_meta
    mov rdi,[rsp+D_NEUTRALVAL]
    mov esi,[rsp+D_NEUTRALTYPE]
    mov edx,[rsp+D_NEUTRALCOUNT]
    xor ecx,ecx
    call .meta_fixed
    jc .bad
    test eax,eax
    jle .bad
    mov [rsp+D_ROWBYTES],eax             ; neutral R
    mov rdi,[rsp+D_NEUTRALVAL]
    mov esi,[rsp+D_NEUTRALTYPE]
    mov edx,[rsp+D_NEUTRALCOUNT]
    mov ecx,1
    call .meta_fixed
    jc .bad
    test eax,eax
    jle .bad
    mov [rsp+D_CURROWS],eax              ; neutral G
    mov rdi,[rsp+D_NEUTRALVAL]
    mov esi,[rsp+D_NEUTRALTYPE]
    mov edx,[rsp+D_NEUTRALCOUNT]
    mov ecx,2
    call .meta_fixed
    jc .bad
    test eax,eax
    jle .bad
    mov [rsp+D_FIRSTROW],eax             ; neutral B
    mov eax,[rsp+D_CURROWS]
    shl rax,16
    xor edx,edx
    div dword [rsp+D_ROWBYTES]
    cmp rax,0x7fffffff
    ja .bad
    mov [rsp+SensorImageDesc.wb_r],eax
    mov dword [rsp+SensorImageDesc.wb_g],0x10000
    mov eax,[rsp+D_CURROWS]
    shl rax,16
    xor edx,edx
    div dword [rsp+D_FIRSTROW]
    cmp rax,0x7fffffff
    ja .bad
    mov [rsp+SensorImageDesc.wb_b],eax
.matrix_meta:
    cmp dword [rsp+D_MATRIXCOUNT],9
    jne .metadata_done
    mov dword [rsp+D_CURROWS],0
.matrix_loop:
    mov ecx,[rsp+D_CURROWS]
    cmp ecx,9
    jae .matrix_convert
    mov rdi,[rsp+D_MATRIXVAL]
    mov esi,[rsp+D_MATRIXTYPE]
    mov edx,[rsp+D_MATRIXCOUNT]
    call .meta_fixed
    jc .bad
    mov ecx,[rsp+D_CURROWS]
    mov [rsp+SensorImageDesc.color_matrix+rcx*4],eax
    inc dword [rsp+D_CURROWS]
    jmp .matrix_loop
.matrix_convert:
    lea rdi,[rsp+SensorImageDesc.color_matrix]
    call dng_prepare_color_matrix
    test rax,rax
    js .bad
.metadata_done:
    mov ecx,[rsp+SensorImageDesc.bit_depth]
    imul eax,ecx
    add eax,7
    shr eax,3
    mov [rsp+SensorImageDesc.stride],eax
    mov [rsp+D_ROWBYTES],eax
    cmp ecx,8
    je .unpacked
    cmp ecx,16
    je .unpacked
    mov dword [rsp+SensorImageDesc.packing],SENSOR_PACK_MSB_BITS
.unpacked:
    cmp dword [rsp+SensorImageDesc.bit_depth],16
    jne .bounds
    cmp dword [rsp+D_BE],0
    je .bounds
    mov dword [rsp+SensorImageDesc.packing],SENSOR_PACK_UNPACKED_BE
.bounds:
    cmp dword [rsp+D_NSTRIPS],0
    je .bad
    cmp dword [rsp+D_STORAGE],1
    je .tile_bounds
    cmp dword [rsp+D_ROWS],0
    je .bad
    mov eax,[rsp+SensorImageDesc.height]
    xor edx,edx
    div dword [rsp+D_ROWS]
    test edx,edx
    jz .strip_total_ready
    inc eax
.strip_total_ready:
    cmp eax,[rsp+D_NSTRIPS]
    jne .bad
    jmp .compression_bounds
.tile_bounds:
    cmp dword [rsp+D_TILEW],0
    je .bad
    cmp dword [rsp+D_TILEH],0
    je .bad
    mov eax,[rsp+SensorImageDesc.width]
    xor edx,edx
    div dword [rsp+D_TILEW]
    test edx,edx
    jz .tiles_x_ready
    inc eax
.tiles_x_ready:
    mov [rsp+D_TILESX],eax
    mov eax,[rsp+SensorImageDesc.height]
    xor edx,edx
    div dword [rsp+D_TILEH]
    test edx,edx
    jz .tiles_y_ready
    inc eax
.tiles_y_ready:
    mov [rsp+D_TILESY],eax
    imul eax,[rsp+D_TILESX]
    jo .bad
    cmp eax,[rsp+D_NSTRIPS]
    jne .bad
.compression_bounds:
    mov eax,[rsp+D_COMP]
    cmp eax,1
    je .compression_ok
    cmp eax,5
    je .compression_ok
    cmp eax,7
    je .compression_ok
    cmp eax,8
    je .compression_ok
    cmp eax,32946
    je .compression_ok
    cmp eax,32773
    jne .bad
.compression_ok:
    cmp dword [rsp+D_COMP],7
    jne .compression_layout_ready
    mov eax,[rsp+SensorImageDesc.width]
    cmp dword [rsp+SensorImageDesc.bit_depth],8
    jbe .lossless_row_ready
    shl eax,1
.lossless_row_ready:
    mov [rsp+D_ROWBYTES],eax
    mov [rsp+SensorImageDesc.stride],eax
    mov dword [rsp+SensorImageDesc.packing],SENSOR_PACK_UNPACKED
.compression_layout_ready:
    mov eax,[rsp+D_PRED]
    cmp eax,1
    je .predictor_ok
    cmp eax,2
    jne .bad
.predictor_ok:
    mov eax,[rsp+D_ROWBYTES]
    imul eax,[rsp+SensorImageDesc.height]
    jo .bad
    add eax,4
    jc .bad
    mov rdi,rbx
    mov esi,eax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+D_RASTER],rax
    mov edx,[rsp+D_ROWBYTES]
    imul edx,[rsp+SensorImageDesc.height]
    mov dword [rax+rdx],0               ; safe packed-MSB lookahead
    mov qword [rsp+SensorImageDesc.data_offset],0
    cmp dword [rsp+D_STORAGE],1
    je .allocate_tile_scratch
    xor r14d,r14d
    mov dword [rsp+D_FIRSTROW],0
.decode_strip:
    cmp r14d,[rsp+D_NSTRIPS]
    jae .decoded
    mov r10d,[rsp+D_FIRSTROW]
    mov eax,[rsp+SensorImageDesc.height]
    sub eax,r10d
    cmp eax,[rsp+D_ROWS]
    jbe .decode_rows
    mov eax,[rsp+D_ROWS]
.decode_rows:
    mov [rsp+D_CURROWS],eax
    mov rdi,[rsp+D_OFFVAL]
    mov esi,[rsp+D_OFFTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov r11,rax
    mov rdi,[rsp+D_CNTVAL]
    mov esi,[rsp+D_CNTTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov rcx,rax
    add rax,r11
    jc .bad
    cmp rax,r13
    ja .bad
    mov r8,[rsp+D_RASTER]
    mov eax,[rsp+D_ROWBYTES]
    imul eax,r10d
    add r8,rax
    mov r9d,[rsp+D_ROWBYTES]
    imul r9d,[rsp+D_CURROWS]
    cmp dword [rsp+D_COMP],7
    je .decode_lossless
    mov rdi,rbx
    mov esi,[rsp+D_COMP]
    lea rdx,[r12+r11]
    call tiff_decompress_block
    test rax,rax
    js .bad
    jmp .strip_decoded
.decode_lossless:
    mov rdi,rbx
    lea rsi,[r12+r11]
    mov rdx,rcx
    mov rcx,r8
    mov r8d,[rsp+SensorImageDesc.width]
    mov r9d,[rsp+D_CURROWS]
    call jpeg_lossless_decode
    test rax,rax
    js .bad
    mov edx,[rsp+D_ROWBYTES]
    imul edx,[rsp+D_CURROWS]
    cmp eax,edx
    jne .bad
.strip_decoded:
    mov eax,[rsp+D_CURROWS]
    add [rsp+D_FIRSTROW],eax
    inc r14d
    jmp .decode_strip
.decoded:
    mov eax,[rsp+D_FIRSTROW]
    cmp eax,[rsp+SensorImageDesc.height]
    jne .bad
    cmp dword [rsp+D_PRED],2
    jne .process
    mov rdi,[rsp+D_RASTER]
    mov esi,[rsp+D_ROWBYTES]
    mov edx,[rsp+SensorImageDesc.height]
    mov ecx,1
    cmp dword [rsp+SensorImageDesc.bit_depth],16
    jne .predict_call
    mov ecx,2
.predict_call:
    mov r8d,[rsp+SensorImageDesc.bit_depth]
    mov r9d,[rsp+D_BE]
    call tiff_undo_predictor_block
    jmp .process

.allocate_tile_scratch:
    mov eax,[rsp+D_TILEW]
    cmp dword [rsp+D_COMP],7
    je .tile_expanded_row
    imul eax,[rsp+SensorImageDesc.bit_depth]
    jo .bad
    add eax,7
    jc .bad
    shr eax,3
    jmp .tile_row_ready
.tile_expanded_row:
    cmp dword [rsp+SensorImageDesc.bit_depth],8
    jbe .tile_row_ready
    shl eax,1
    jc .bad
.tile_row_ready:
    test eax,eax
    jz .bad
    mov [rsp+D_TILEROW],eax
    imul eax,[rsp+D_TILEH]
    jo .bad
    mov [rsp+D_TILEBYTES],eax
    mov rdi,rbx
    mov esi,eax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+D_SCRATCH],rax
    mov dword [rsp+D_TILEINDEX],0
.tile_loop:
    mov r14d,[rsp+D_TILEINDEX]
    cmp r14d,[rsp+D_NSTRIPS]
    jae .process
    mov eax,r14d
    xor edx,edx
    div dword [rsp+D_TILESX]
    mov [rsp+D_TILEY],eax
    mov [rsp+D_TILEX],edx
    mov ecx,[rsp+D_TILEW]
    imul ecx,edx
    mov eax,[rsp+SensorImageDesc.width]
    sub eax,ecx
    cmp eax,[rsp+D_TILEW]
    jbe .tile_width_ready
    mov eax,[rsp+D_TILEW]
.tile_width_ready:
    mov [rsp+D_VALIDW],eax
    mov ecx,[rsp+D_TILEH]
    imul ecx,[rsp+D_TILEY]
    mov eax,[rsp+SensorImageDesc.height]
    sub eax,ecx
    cmp eax,[rsp+D_TILEH]
    jbe .tile_height_ready
    mov eax,[rsp+D_TILEH]
.tile_height_ready:
    mov [rsp+D_VALIDH],eax
    mov rdi,[rsp+D_OFFVAL]
    mov esi,[rsp+D_OFFTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov r11,rax
    mov rdi,[rsp+D_CNTVAL]
    mov esi,[rsp+D_CNTTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov rcx,rax
    add rax,r11
    jc .bad
    cmp rax,r13
    ja .bad
    cmp dword [rsp+D_COMP],7
    je .tile_decode_lossless
    mov rdi,rbx
    mov esi,[rsp+D_COMP]
    lea rdx,[r12+r11]
    mov r8,[rsp+D_SCRATCH]
    mov r9d,[rsp+D_TILEBYTES]
    call tiff_decompress_block
    test rax,rax
    js .bad
    jmp .tile_decoded
.tile_decode_lossless:
    mov rdi,rbx
    lea rsi,[r12+r11]
    mov rdx,rcx
    mov rcx,[rsp+D_SCRATCH]
    mov r8d,[rsp+D_TILEW]
    mov r9d,[rsp+D_TILEH]
    call jpeg_lossless_decode
    test rax,rax
    js .bad
    cmp eax,[rsp+D_TILEBYTES]
    jne .bad
.tile_decoded:
    cmp dword [rsp+D_PRED],2
    jne .tile_predictor_done
    mov rdi,[rsp+D_SCRATCH]
    mov esi,[rsp+D_TILEROW]
    mov edx,[rsp+D_TILEH]
    mov ecx,1
    cmp dword [rsp+SensorImageDesc.bit_depth],16
    jne .tile_predictor_call
    mov ecx,2
.tile_predictor_call:
    mov r8d,[rsp+SensorImageDesc.bit_depth]
    mov r9d,[rsp+D_BE]
    call tiff_undo_predictor_block
.tile_predictor_done:
    mov dword [rsp+D_COPYROW],0
.tile_copy_row:
    mov r10d,[rsp+D_COPYROW]
    cmp r10d,[rsp+D_VALIDH]
    jae .tile_next
    mov rsi,[rsp+D_SCRATCH]
    mov eax,[rsp+D_TILEROW]
    imul eax,r10d
    add rsi,rax
    mov rdi,[rsp+D_RASTER]
    mov eax,[rsp+D_TILEY]
    imul eax,[rsp+D_TILEH]
    add eax,r10d
    imul eax,[rsp+D_ROWBYTES]
    add rdi,rax
    mov eax,[rsp+D_TILEX]
    imul eax,[rsp+D_TILEW]
    cmp dword [rsp+D_COMP],7
    je .tile_x_expanded
    imul eax,[rsp+SensorImageDesc.bit_depth]
    jo .bad
    test eax,7
    jnz .bad
    shr eax,3
    jmp .tile_x_ready
.tile_x_expanded:
    cmp dword [rsp+SensorImageDesc.bit_depth],8
    jbe .tile_x_ready
    shl eax,1
.tile_x_ready:
    add rdi,rax
    mov ecx,[rsp+D_VALIDW]
    cmp dword [rsp+D_COMP],7
    je .tile_copy_expanded
    imul ecx,[rsp+SensorImageDesc.bit_depth]
    add ecx,7
    shr ecx,3
    jmp .tile_copy
.tile_copy_expanded:
    cmp dword [rsp+SensorImageDesc.bit_depth],8
    jbe .tile_copy
    shl ecx,1
.tile_copy:
    rep movsb
    inc dword [rsp+D_COPYROW]
    jmp .tile_copy_row
.tile_next:
    inc dword [rsp+D_TILEINDEX]
    jmp .tile_loop
.process:
    mov edx,[rsp+D_ROWBYTES]
    imul edx,[rsp+SensorImageDesc.height]
    mov eax,[rsp+D_CROPW]
    mov [rsp+SensorImageDesc.width],eax
    mov eax,[rsp+D_CROPH]
    mov [rsp+SensorImageDesc.height],eax
    mov rdi,rbx
    mov rsi,[rsp+D_RASTER]
    mov rcx,rsp
    call sensor_process
    add rsp,D_LOCAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,D_LOCAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; Read one TIFF SHORT/LONG scalar from the current entry.
.scalar:
    mov eax,r8d
    cmp ecx,3
    jne .scalar_done
    cmp dword [rsp+D_BE],0
    je .scalar_le
    shr eax,16
    ret
.scalar_le:
    and eax,0xFFFF
.scalar_done:
    ret

; value/offset, TIFF type, count, index -> unsigned integer (rationals rounded).
.meta_value:
    cmp ecx,edx
    jae .meta_bad
    mov r9d,ecx
    cmp esi,3
    je .meta_short
    cmp esi,4
    je .meta_long
    cmp esi,5
    je .meta_rational
    jmp .meta_bad
.meta_short:
    cmp edx,2
    ja .meta_short_indirect
    mov rax,rdi
    cmp dword [rsp+D_BE],0
    je .meta_short_le
    test r9d,r9d
    jz .meta_short_be_first
    and eax,0xffff
    clc
    ret
.meta_short_be_first:
    shr eax,16
    clc
    ret
.meta_short_le:
    test r9d,r9d
    jz .meta_short_le_first
    shr eax,16
    clc
    ret
.meta_short_le_first:
    and eax,0xffff
    clc
    ret
.meta_short_indirect:
    lea rax,[rdi+r9*2+2]
    cmp rax,r13
    ja .meta_bad
    lea rdi,[rdi+r9*2]
    add rdi,r12
    mov esi,[rsp+D_BE]
    call tiff_read_u16
    clc
    ret
.meta_long:
    cmp edx,1
    jne .meta_long_indirect
    mov rax,rdi
    clc
    ret
.meta_long_indirect:
    lea rax,[rdi+r9*4+4]
    cmp rax,r13
    ja .meta_bad
    lea rdi,[rdi+r9*4]
    add rdi,r12
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    clc
    ret
.meta_rational:
    lea rax,[rdi+r9*8+8]
    cmp rax,r13
    ja .meta_bad
    lea r10,[rdi+r9*8]
    lea rdi,[r12+r10]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    mov r11d,eax
    lea rdi,[r12+r10+4]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    test eax,eax
    jz .meta_bad
    mov ecx,eax
    mov eax,r11d
    xor edx,edx
    div ecx
    clc
    ret
.meta_bad:
    stc
    ret

; RATIONAL/SRATIONAL array element converted to signed 16.16.
.meta_fixed:
    cmp ecx,edx
    jae .fixed_bad
    cmp esi,5
    je .fixed_type_ok
    cmp esi,10
    jne .fixed_bad
.fixed_type_ok:
    mov r9d,esi
    lea rax,[rdi+rcx*8+8]
    cmp rax,r13
    ja .fixed_bad
    lea r10,[rdi+rcx*8]
    lea rdi,[r12+r10]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    mov r11d,eax
    lea rdi,[r12+r10+4]
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    test eax,eax
    jz .fixed_bad
    mov ecx,eax
    cmp r9d,10
    je .fixed_signed
    mov eax,r11d
    shl rax,16
    xor edx,edx
    div rcx
    cmp rax,0x7fffffff
    ja .fixed_bad
    clc
    ret
.fixed_signed:
    test ecx,ecx
    jle .fixed_bad
    movsxd rax,r11d
    shl rax,16
    cqo
    movsxd rcx,ecx
    idiv rcx
    cmp rax,0x7fffffff
    jg .fixed_bad
    cmp rax,-0x80000000
    jl .fixed_bad
    clc
    ret
.fixed_bad:
    stc
    ret

.array_value:
    cmp dword [rsp+D_NSTRIPS],1
    jne .array_indirect
    test edx,edx
    jnz .array_bad
    cmp esi,4
    je .array_long
    cmp esi,3
    jne .array_bad
    mov rax,rdi
    cmp dword [rsp+D_BE],0
    je .array_short_le
    shr rax,16
    clc
    ret
.array_short_le:
    and eax,0xffff
    clc
    ret
.array_long:
    mov rax,rdi
    clc
    ret
.array_indirect:
    cmp esi,3
    je .array_short
    cmp esi,4
    jne .array_bad
    lea rax,[rdi+rdx*4+4]
    cmp rax,r13
    ja .array_bad
    lea rdi,[rdi+rdx*4]
    add rdi,r12
    mov esi,[rsp+D_BE]
    call tiff_read_u32
    clc
    ret
.array_short:
    lea rax,[rdi+rdx*2+2]
    cmp rax,r13
    ja .array_bad
    lea rdi,[rdi+rdx*2]
    add rdi,r12
    mov esi,[rsp+D_BE]
    call tiff_read_u16
    clc
    ret
.array_bad:
    stc
    ret

section .data
global dng_version
dng_version: dq 0x010000
