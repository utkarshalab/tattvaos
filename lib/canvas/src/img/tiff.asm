; TIFF 6.0 raster decoder: II/MM, multi-strip raw/PackBits/Deflate,
; 8/16-bit Gray/RGB/RGBA, horizontal prediction, and orientation.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

extern arena_alloc
extern memcopy
extern pixbuf_create
extern zlib_decompress
extern dng_decode
extern tiff_lzw_decode

%define L_W             0
%define L_H             4
%define L_BITS          8
%define L_SAMPLES      12
%define L_COMP         16
%define L_PHOTO        20
%define L_ORIENT       24
%define L_PLANAR       28
%define L_PREDICTOR    32
%define L_ROWS         36
%define L_NSTRIPS      40
%define L_OFFTYPE      44
%define L_CNTTYPE      48
%define L_BE           52
%define L_OFFVAL       56
%define L_CNTVAL       64
%define L_RASTER       72
%define L_ROWBYTES     80
%define L_OUTW         88
%define L_OUTH         92
%define L_CURROWS      96
%define L_ENCROW      100
%define L_SPP         104
%define L_CMAP        108
%define L_CMAPCOUNT   116
%define L_TILEW       120
%define L_TILEH       124
%define L_TILESX      128
%define L_TILESY      132
%define L_SCRATCH     136
%define L_STORAGE     144
%define L_TILEBYTES   148
%define L_TILEINDEX   152
%define L_TILEPLANE   156
%define L_TILEX       160
%define L_TILEY       164
%define L_VALIDW      168
%define L_VALIDH      172
%define L_TILEROW     176
%define LOCAL_SIZE    192

section .text

global tiff_read_u16
tiff_read_u16:                         ; pointer, big-endian flag
    movzx eax,word [rdi]
    test esi,esi
    jz .done
    xchg al,ah
.done:
    ret

global tiff_read_u32
tiff_read_u32:                         ; pointer, big-endian flag
    mov eax,[rdi]
    test esi,esi
    jz .done
    bswap eax
.done:
    ret

; pointer, input length, output, exact output length -> written or -1.
global tiff_packbits_decode
tiff_packbits_decode:
    push rbx
    xor r8d,r8d                        ; input position
    xor r9d,r9d                        ; output position
.packet:
    cmp r9,rcx
    je .ok
    cmp r8,rsi
    jae .bad
    movsx eax,byte [rdi+r8]
    inc r8
    cmp eax,-128
    je .packet
    test eax,eax
    js .repeat
    inc eax
    mov ebx,eax
    lea r10,[r8+rbx]
    cmp r10,rsi
    ja .bad
    lea r10,[r9+rbx]
    cmp r10,rcx
    ja .bad
.literal:
    mov al,[rdi+r8]
    mov [rdx+r9],al
    inc r8
    inc r9
    dec ebx
    jnz .literal
    jmp .packet
.repeat:
    neg eax
    inc eax
    mov ebx,eax
    cmp r8,rsi
    jae .bad
    lea r10,[r9+rbx]
    cmp r10,rcx
    ja .bad
    mov al,[rdi+r8]
    inc r8
.repeat_bytes:
    mov [rdx+r9],al
    inc r9
    dec ebx
    jnz .repeat_bytes
    jmp .packet
.ok:
    mov rax,r9
    pop rbx
    ret
.bad:
    mov rax,-1
    pop rbx
    ret

; arena, compression, source, source length, output, exact output length.
global tiff_decompress_block
tiff_decompress_block:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    mov [rsp],r9
    cmp r12,1
    je .raw
    cmp r12,5
    je .lzw
    cmp r12,32773
    je .packbits
    cmp r12,8
    je .deflate
    cmp r12,32946
    jne .fail
.deflate:
    mov rdi,rbx
    mov rsi,r13
    mov rdx,r14
    mov rcx,r15
    mov r8,[rsp]
    call zlib_decompress
    jmp .check
.lzw:
    mov rdi,rbx
    mov rsi,r13
    mov rdx,r14
    mov rcx,r15
    mov r8,[rsp]
    call tiff_lzw_decode
    jmp .check
.packbits:
    mov rdi,r13
    mov rsi,r14
    mov rdx,r15
    mov rcx,[rsp]
    call tiff_packbits_decode
    jmp .check
.raw:
    cmp r14,[rsp]
    jb .fail
    mov rdi,r15
    mov rsi,r13
    mov rdx,[rsp]
    call memcopy
    mov rax,[rsp]
.check:
    cmp rax,[rsp]
    jne .fail
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.fail:
    mov rax,-1
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; data, row bytes, rows, pixel stride bytes, bit depth, endian flag.
global tiff_undo_predictor_block
tiff_undo_predictor_block:
    push rbx
    xor r10d,r10d
.row:
    cmp r10d,edx
    jae .done
    mov r11d,ecx
    cmp r8d,16
    je .word
.byte:
    cmp r11d,esi
    jae .next
    mov al,[rdi+r11]
    mov ebx,r11d
    sub ebx,ecx
    add al,[rdi+rbx]
    mov [rdi+r11],al
    inc r11d
    jmp .byte
.word:
    cmp r11d,esi
    jae .next
    mov ebx,r11d
    sub ebx,ecx
    movzx eax,word [rdi+r11]
    movzx ebx,word [rdi+rbx]
    test r9d,r9d
    jz .word_add
    xchg al,ah
    rol bx,8
.word_add:
    add ax,bx
    test r9d,r9d
    jz .word_store
    xchg al,ah
.word_store:
    mov [rdi+r11],ax
    add r11d,2
    jmp .word
.next:
    add rdi,rsi
    inc r10d
    jmp .row
.done:
    pop rbx
    ret

global tiff_decode
tiff_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,LOCAL_SIZE
    mov rbx,rdi                         ; arena
    mov r12,rsi                        ; file
    mov r13,rdx                        ; length
    cmp r13,8
    jb .bad
    xor r15d,r15d
    cmp word [r12],0x4949
    je .order_ok
    cmp word [r12],0x4d4d
    jne .bad
    mov r15d,1
.order_ok:
    mov [rsp+L_BE],r15d
    lea rdi,[r12+2]
    mov esi,r15d
    call tiff_read_u16
    cmp eax,42
    jne .bad
    lea rdi,[r12+4]
    mov esi,r15d
    call tiff_read_u32
    cmp rax,r13
    jae .bad
    lea r14,[r12+rax]
    mov rdi,r14
    mov esi,r15d
    call tiff_read_u16
    mov r10d,eax                       ; entry count
    add r14,2
    mov dword [rsp+L_BITS],8
    mov dword [rsp+L_SAMPLES],1
    mov dword [rsp+L_COMP],1
    mov dword [rsp+L_PHOTO],1
    mov dword [rsp+L_ORIENT],1
    mov dword [rsp+L_PLANAR],1
    mov dword [rsp+L_PREDICTOR],1
    mov dword [rsp+L_ROWS],0xffffffff
    mov dword [rsp+L_NSTRIPS],0
    mov dword [rsp+L_CMAPCOUNT],0
    mov qword [rsp+L_CMAP],0
    mov dword [rsp+L_STORAGE],0
.entry:
    test r10d,r10d
    jz .parsed
    mov rax,r14
    sub rax,r12
    add rax,12
    cmp rax,r13
    ja .bad
    mov rdi,r14
    mov esi,r15d
    call tiff_read_u16
    mov r11d,eax                       ; tag
    lea rdi,[r14+2]
    mov esi,r15d
    call tiff_read_u16
    mov r9d,eax                        ; type
    lea rdi,[r14+4]
    mov esi,r15d
    call tiff_read_u32
    mov r8d,eax                        ; count
    lea rdi,[r14+8]
    mov esi,r15d
    call tiff_read_u32
    mov edx,eax                        ; value/offset
    cmp r11d,256
    je .width
    cmp r11d,257
    je .height
    cmp r11d,258
    je .bits
    cmp r11d,259
    je .compression
    cmp r11d,262
    je .photo
    cmp r11d,273
    je .offsets
    cmp r11d,274
    je .orientation
    cmp r11d,277
    je .samples
    cmp r11d,278
    je .rows
    cmp r11d,279
    je .counts
    cmp r11d,284
    je .planar
    cmp r11d,317
    je .predictor
    cmp r11d,320
    je .colormap
    cmp r11d,322
    je .tile_width
    cmp r11d,323
    je .tile_height
    cmp r11d,324
    je .tile_offsets
    cmp r11d,325
    je .tile_counts
    jmp .next
.width:
    call .scalar
    mov [rsp+L_W],eax
    jmp .next
.height:
    call .scalar
    mov [rsp+L_H],eax
    jmp .next
.bits:
    cmp r8d,1
    je .bits_inline
    cmp r9d,3
    jne .bad
    mov eax,r8d
    shl eax,1
    add rax,rdx
    cmp rax,r13
    ja .bad
    xor ecx,ecx
    xor r11d,r11d
.bits_array:
    cmp ecx,r8d
    jae .bits_array_done
    lea rdi,[r12+rdx]
    lea rdi,[rdi+rcx*2]
    mov esi,r15d
    call tiff_read_u16
    test ecx,ecx
    jnz .bits_same
    mov r11d,eax
.bits_same:
    cmp eax,r11d
    jne .bad
    inc ecx
    jmp .bits_array
.bits_array_done:
    mov [rsp+L_BITS],r11d
    jmp .next
.bits_inline:
    call .scalar
    mov [rsp+L_BITS],eax
    jmp .next
.compression:
    call .scalar
    mov [rsp+L_COMP],eax
    jmp .next
.photo:
    call .scalar
    mov [rsp+L_PHOTO],eax
    jmp .next
.orientation:
    call .scalar
    mov [rsp+L_ORIENT],eax
    jmp .next
.samples:
    call .scalar
    mov [rsp+L_SAMPLES],eax
    jmp .next
.rows:
    call .scalar
    mov [rsp+L_ROWS],eax
    jmp .next
.planar:
    call .scalar
    mov [rsp+L_PLANAR],eax
    jmp .next
.predictor:
    call .scalar
    mov [rsp+L_PREDICTOR],eax
    jmp .next
.colormap:
    cmp r9d,3
    jne .bad
    mov [rsp+L_CMAPCOUNT],r8d
    mov [rsp+L_CMAP],rdx
    jmp .next
.tile_width:
    call .scalar
    mov [rsp+L_TILEW],eax
    jmp .next
.tile_height:
    call .scalar
    mov [rsp+L_TILEH],eax
    jmp .next
.tile_offsets:
    mov dword [rsp+L_STORAGE],1
    mov [rsp+L_NSTRIPS],r8d
    mov [rsp+L_OFFTYPE],r9d
    mov [rsp+L_OFFVAL],rdx
    jmp .next
.tile_counts:
    mov dword [rsp+L_STORAGE],1
    cmp dword [rsp+L_NSTRIPS],0
    jne .tile_count_match
    mov [rsp+L_NSTRIPS],r8d
.tile_count_match:
    cmp [rsp+L_NSTRIPS],r8d
    jne .bad
    mov [rsp+L_CNTTYPE],r9d
    mov [rsp+L_CNTVAL],rdx
    jmp .next
.offsets:
    mov [rsp+L_NSTRIPS],r8d
    mov [rsp+L_OFFTYPE],r9d
    mov [rsp+L_OFFVAL],rdx
    jmp .next
.counts:
    cmp dword [rsp+L_NSTRIPS],0
    jne .count_match
    mov [rsp+L_NSTRIPS],r8d
.count_match:
    cmp [rsp+L_NSTRIPS],r8d
    jne .bad
    mov [rsp+L_CNTTYPE],r9d
    mov [rsp+L_CNTVAL],rdx
.next:
    add r14,12
    dec r10d
    jmp .entry

; Convert an inline SHORT/LONG entry value to host order.
.scalar:
    mov eax,edx
    cmp r9d,3
    jne .scalar_done
    test r15d,r15d
    jz .scalar_le
    shr eax,16
    ret
.scalar_le:
    and eax,0xffff
.scalar_done:
    ret

.parsed:
    cmp dword [rsp+L_PHOTO],32803
    je .camera
    cmp dword [rsp+L_BITS],1
    je .depth_ok
    cmp dword [rsp+L_BITS],2
    je .depth_ok
    cmp dword [rsp+L_BITS],4
    je .depth_ok
    cmp dword [rsp+L_BITS],8
    je .depth_ok
    cmp dword [rsp+L_BITS],16
    jne .bad
.depth_ok:
    cmp dword [rsp+L_PLANAR],1
    je .planar_ok
    cmp dword [rsp+L_PLANAR],2
    jne .bad
.planar_ok:
    mov eax,[rsp+L_W]
    test eax,eax
    jz .bad
    mov ecx,[rsp+L_H]
    test ecx,ecx
    jz .bad
    mov edx,[rsp+L_SAMPLES]
    cmp edx,1
    je .samples_ok
    cmp edx,3
    je .samples_ok
    cmp edx,4
    jne .bad
.samples_ok:
    cmp dword [rsp+L_ROWS],0
    je .bad
    cmp edx,1
    jne .rgb_photo
    cmp dword [rsp+L_PHOTO],0
    je .photo_ok
    cmp dword [rsp+L_PHOTO],1
    je .photo_ok
    cmp dword [rsp+L_PHOTO],3
    jne .bad
    mov eax,1
    mov ecx,[rsp+L_BITS]
    shl eax,cl
    imul eax,3
    cmp eax,[rsp+L_CMAPCOUNT]
    jne .bad
    mov edx,[rsp+L_CMAP]
    lea rax,[rdx+rax*2]
    cmp rax,r13
    ja .bad
    jmp .photo_ok
.rgb_photo:
    cmp dword [rsp+L_BITS],8
    jb .bad
    cmp dword [rsp+L_PHOTO],2
    jne .bad
.photo_ok:
    cmp dword [rsp+L_NSTRIPS],0
    je .bad
    mov esi,[rsp+L_COMP]
    cmp esi,1
    je .compression_ok
    cmp esi,5
    je .compression_ok
    cmp esi,8
    je .compression_ok
    cmp esi,32946
    je .compression_ok
    cmp esi,32773
    jne .bad
.compression_ok:
    mov esi,[rsp+L_PREDICTOR]
    cmp esi,1
    je .predictor_ok
    cmp esi,2
    jne .bad
.predictor_ok:
    cmp esi,2
    jne .predictor_depth_ok
    cmp dword [rsp+L_BITS],8
    jb .bad
.predictor_depth_ok:
    imul rax,rdx
    imul eax,[rsp+L_BITS]
    jo .bad
    add eax,7
    shr eax,3
.rowbytes_ready:
    mov [rsp+L_ROWBYTES],rax
    mov [rsp+L_ENCROW],eax
    cmp dword [rsp+L_PLANAR],2
    jne .encoded_row_ready
    mov eax,[rsp+L_W]
    imul eax,[rsp+L_BITS]
    add eax,7
    shr eax,3
    mov [rsp+L_ENCROW],eax
.encoded_row_ready:
    cmp dword [rsp+L_STORAGE],1
    je .tile_geometry
    mov eax,[rsp+L_H]
    xor edx,edx
    div dword [rsp+L_ROWS]
    test edx,edx
    jz .spp_ready
    inc eax
.spp_ready:
    mov [rsp+L_SPP],eax
    mov ecx,eax
    cmp dword [rsp+L_PLANAR],2
    jne .strip_count_ready
    imul ecx,[rsp+L_SAMPLES]
    jo .bad
.strip_count_ready:
    cmp ecx,[rsp+L_NSTRIPS]
    jne .bad
.allocate_raster:
    mov eax,[rsp+L_ROWBYTES]
    imul eax,[rsp+L_H]
    jo .bad
    mov rdi,rbx
    mov esi,eax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+L_RASTER],rax
    cmp dword [rsp+L_STORAGE],1
    je .allocate_tile_scratch
    xor r14d,r14d                       ; strip index
.strip:
    cmp r14d,[rsp+L_NSTRIPS]
    jae .strips_done
    mov eax,r14d
    xor edx,edx
    div dword [rsp+L_SPP]
    mov r10d,edx                        ; strip within plane
    imul r10d,[rsp+L_ROWS]              ; first row
    mov r9d,[rsp+L_H]
    sub r9d,r10d
    cmp r9d,[rsp+L_ROWS]
    jbe .strip_rows
    mov r9d,[rsp+L_ROWS]
.strip_rows:
    mov [rsp+L_CURROWS],r9d
    mov rdi,[rsp+L_OFFVAL]
    mov esi,[rsp+L_OFFTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov r11,rax                         ; source offset
    mov rdi,[rsp+L_CNTVAL]
    mov esi,[rsp+L_CNTTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov r8,rax                          ; source length
    add rax,r11
    jc .bad
    cmp rax,r13
    ja .bad
    mov r15d,[rsp+L_ENCROW]
    imul r15,r9                         ; expected bytes
    mov rdx,[rsp+L_RASTER]
    mov eax,r14d
    xor ecx,ecx
    div dword [rsp+L_SPP]               ; eax = plane
    mov ecx,eax
    imul ecx,[rsp+L_H]
    imul ecx,[rsp+L_ENCROW]
    add rdx,rcx
    mov eax,[rsp+L_ENCROW]
    imul rax,r10
    add rdx,rax
    mov r9,r15
    mov rcx,r8
    mov r8,rdx
    lea rdx,[r12+r11]
    mov rdi,r12
    mov rdi,rbx
    mov esi,[rsp+L_COMP]
    call tiff_decompress_block
    test rax,rax
    js .bad
.strip_done:
    inc r14d
    jmp .strip
.strips_done:
    cmp dword [rsp+L_PREDICTOR],2
    jne .create
    cmp dword [rsp+L_BITS],16
    je .predict16_start
    mov rdi,[rsp+L_RASTER]
    xor r10d,r10d
.pred_row:
    mov ecx,[rsp+L_SAMPLES]
    mov edx,[rsp+L_ENCROW]
    cmp dword [rsp+L_PLANAR],1
    je .pred_stride_ready
    mov ecx,1
.pred_stride_ready:
    mov r8d,ecx
.pred_byte:
    cmp r8d,edx
    jae .pred_next
    mov al,[rdi+r8]
    mov r9,r8
    sub r9,rcx
    add al,[rdi+r9]
    mov [rdi+r8],al
    inc r8d
    jmp .pred_byte
.pred_next:
    add rdi,[rsp+L_ENCROW]
    inc r10d
    mov eax,[rsp+L_H]
    cmp dword [rsp+L_PLANAR],1
    je .pred_rows_ready
    imul eax,[rsp+L_SAMPLES]
.pred_rows_ready:
    cmp r10d,eax
    jb .pred_row
    jmp .create

.tile_geometry:
    mov eax,[rsp+L_TILEW]
    test eax,eax
    jz .bad
    mov ecx,[rsp+L_TILEH]
    test ecx,ecx
    jz .bad
    mov eax,[rsp+L_W]
    xor edx,edx
    div dword [rsp+L_TILEW]
    test edx,edx
    jz .tiles_x_ready
    inc eax
.tiles_x_ready:
    mov [rsp+L_TILESX],eax
    mov eax,[rsp+L_H]
    xor edx,edx
    div dword [rsp+L_TILEH]
    test edx,edx
    jz .tiles_y_ready
    inc eax
.tiles_y_ready:
    mov [rsp+L_TILESY],eax
    imul eax,[rsp+L_TILESX]
    jo .bad
    mov [rsp+L_SPP],eax                 ; tiles per plane
    mov ecx,eax
    cmp dword [rsp+L_PLANAR],2
    jne .tile_count_ready
    imul ecx,[rsp+L_SAMPLES]
    jo .bad
.tile_count_ready:
    cmp ecx,[rsp+L_NSTRIPS]
    jne .bad
    jmp .allocate_raster

.allocate_tile_scratch:
    mov eax,[rsp+L_TILEW]
    imul eax,[rsp+L_BITS]
    cmp dword [rsp+L_PLANAR],2
    je .tile_row_bits
    imul eax,[rsp+L_SAMPLES]
.tile_row_bits:
    add eax,7
    shr eax,3
    test eax,eax
    jz .bad
    mov [rsp+L_TILEROW],eax
    imul eax,[rsp+L_TILEH]
    jo .bad
    mov [rsp+L_TILEBYTES],eax
    mov rdi,rbx
    mov esi,eax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+L_SCRATCH],rax
    mov dword [rsp+L_TILEINDEX],0
.tile_loop:
    mov r14d,[rsp+L_TILEINDEX]
    cmp r14d,[rsp+L_NSTRIPS]
    jae .strips_done
    mov eax,r14d
    xor edx,edx
    div dword [rsp+L_SPP]
    mov [rsp+L_TILEPLANE],eax
    mov eax,edx
    xor edx,edx
    div dword [rsp+L_TILESX]
    mov [rsp+L_TILEY],eax
    mov [rsp+L_TILEX],edx
    mov ecx,[rsp+L_TILEW]
    imul ecx,edx
    mov eax,[rsp+L_W]
    sub eax,ecx
    cmp eax,[rsp+L_TILEW]
    jbe .tile_width_ready
    mov eax,[rsp+L_TILEW]
.tile_width_ready:
    mov [rsp+L_VALIDW],eax
    mov ecx,[rsp+L_TILEH]
    imul ecx,[rsp+L_TILEY]
    mov eax,[rsp+L_H]
    sub eax,ecx
    cmp eax,[rsp+L_TILEH]
    jbe .tile_height_ready
    mov eax,[rsp+L_TILEH]
.tile_height_ready:
    mov [rsp+L_VALIDH],eax
    mov rdi,[rsp+L_OFFVAL]
    mov esi,[rsp+L_OFFTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov r11,rax
    mov rdi,[rsp+L_CNTVAL]
    mov esi,[rsp+L_CNTTYPE]
    mov edx,r14d
    call .array_value
    jc .bad
    mov rcx,rax
    add rax,r11
    jc .bad
    cmp rax,r13
    ja .bad
    mov rdi,rbx
    mov esi,[rsp+L_COMP]
    lea rdx,[r12+r11]
    mov r8,[rsp+L_SCRATCH]
    mov r9d,[rsp+L_TILEBYTES]
    call tiff_decompress_block
    test rax,rax
    js .bad
    cmp dword [rsp+L_PREDICTOR],2
    jne .tile_predictor_done
    mov rdi,[rsp+L_SCRATCH]
    mov esi,[rsp+L_TILEROW]
    mov edx,[rsp+L_TILEH]
    mov ecx,[rsp+L_SAMPLES]
    cmp dword [rsp+L_PLANAR],1
    je .tile_predictor_stride
    mov ecx,1
.tile_predictor_stride:
    cmp dword [rsp+L_BITS],16
    jne .tile_predictor_call
    shl ecx,1
.tile_predictor_call:
    mov r8d,[rsp+L_BITS]
    mov r9d,[rsp+L_BE]
    call tiff_undo_predictor_block
.tile_predictor_done:
    ; Copy the visible tile rectangle into the canonical raster.
    mov dword [rsp+L_CURROWS],0
.tile_copy_row:
    mov r10d,[rsp+L_CURROWS]
    cmp r10d,[rsp+L_VALIDH]
    jae .tile_next
    mov rsi,[rsp+L_SCRATCH]
    mov eax,[rsp+L_TILEROW]
    imul eax,r10d
    add rsi,rax
    mov rdi,[rsp+L_RASTER]
    mov eax,[rsp+L_TILEPLANE]
    imul eax,[rsp+L_H]
    imul eax,[rsp+L_ENCROW]
    add rdi,rax
    mov eax,[rsp+L_TILEY]
    imul eax,[rsp+L_TILEH]
    add eax,r10d
    imul eax,[rsp+L_ENCROW]
    add rdi,rax
    mov eax,[rsp+L_TILEX]
    imul eax,[rsp+L_TILEW]
    imul eax,[rsp+L_BITS]
    cmp dword [rsp+L_PLANAR],2
    je .tile_x_bits
    imul eax,[rsp+L_SAMPLES]
.tile_x_bits:
    test eax,7
    jnz .bad
    shr eax,3
    add rdi,rax
    mov eax,[rsp+L_VALIDW]
    imul eax,[rsp+L_BITS]
    cmp dword [rsp+L_PLANAR],2
    je .tile_copy_bits
    imul eax,[rsp+L_SAMPLES]
.tile_copy_bits:
    add eax,7
    shr eax,3
    mov edx,eax
    call memcopy
    inc dword [rsp+L_CURROWS]
    jmp .tile_copy_row
.tile_next:
    inc dword [rsp+L_TILEINDEX]
    jmp .tile_loop
.predict16_start:
    mov rdi,[rsp+L_RASTER]
    xor r10d,r10d
.pred16_row:
    mov ecx,[rsp+L_SAMPLES]
    cmp dword [rsp+L_PLANAR],1
    je .pred16_stride
    mov ecx,1
.pred16_stride:
    shl ecx,1
    mov edx,[rsp+L_ENCROW]
    mov r8d,ecx
.pred16_word:
    cmp r8d,edx
    jae .pred16_next
    mov r9,r8
    sub r9,rcx
    movzx eax,word [rdi+r8]
    movzx r11d,word [rdi+r9]
    cmp dword [rsp+L_BE],0
    je .pred16_add
    xchg al,ah
    rol r11w,8
.pred16_add:
    add ax,r11w
    cmp dword [rsp+L_BE],0
    je .pred16_store
    xchg al,ah
.pred16_store:
    mov [rdi+r8],ax
    add r8d,2
    jmp .pred16_word
.pred16_next:
    add rdi,[rsp+L_ENCROW]
    inc r10d
    mov eax,[rsp+L_H]
    cmp dword [rsp+L_PLANAR],1
    je .pred16_rows_ready
    imul eax,[rsp+L_SAMPLES]
.pred16_rows_ready:
    cmp r10d,eax
    jb .pred16_row
    jmp .create
.create:
    mov eax,[rsp+L_W]
    mov ecx,[rsp+L_H]
    mov edx,[rsp+L_ORIENT]
    cmp edx,1
    jb .bad
    cmp edx,8
    ja .bad
    cmp edx,5
    jb .dims
    xchg eax,ecx
.dims:
    mov [rsp+L_OUTW],eax
    mov [rsp+L_OUTH],ecx
    mov rdi,rbx
    mov esi,eax
    mov edx,ecx
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov rbx,rax
    call .compose
    mov rax,rbx
    jmp .return

; Resolve one SHORT/LONG array element.
.array_value:
    cmp dword [rsp+L_NSTRIPS],1
    jne .indirect
    test edx,edx
    jnz .array_bad
    cmp esi,4
    je .array_inline_long
    cmp esi,3
    jne .array_bad
    mov rax,rdi
    cmp dword [rsp+L_BE],0
    je .array_inline_short_le
    shr rax,16
    clc
    ret
.array_inline_short_le:
    and eax,0xffff
    clc
    ret
.array_inline_long:
    mov rax,rdi
    clc
    ret
.indirect:
    cmp esi,3
    je .short_array
    cmp esi,4
    jne .array_bad
    lea rax,[rdi+rdx*4+4]
    cmp rax,r13
    ja .array_bad
    lea rdi,[rdi+rdx*4]
    add rdi,r12
    mov esi,[rsp+L_BE]
    call tiff_read_u32
    clc
    ret
.short_array:
    lea rax,[rdi+rdx*2+2]
    cmp rax,r13
    ja .array_bad
    lea rdi,[rdi+rdx*2]
    add rdi,r12
    mov esi,[rsp+L_BE]
    call tiff_read_u16
    clc
    ret
.array_bad:
    stc
    ret

.compose:
    mov rsi,[rsp+L_RASTER]
    xor r10d,r10d
.cy:
    cmp r10d,[rsp+L_H]
    jae .composed
    xor r11d,r11d
.cx:
    cmp r11d,[rsp+L_W]
    jae .next_y
    mov eax,r11d
    mov ecx,r10d
    mov edx,[rsp+L_ORIENT]
    cmp edx,2
    je .o2
    cmp edx,3
    je .o3
    cmp edx,4
    je .o4
    cmp edx,5
    je .o5
    cmp edx,6
    je .o6
    cmp edx,7
    je .o7
    cmp edx,8
    je .o8
    jmp .mapped
.o2:
    mov eax,[rsp+L_W]
    dec eax
    sub eax,r11d
    jmp .mapped
.o3:
    mov eax,[rsp+L_W]
    dec eax
    sub eax,r11d
    mov ecx,[rsp+L_H]
    dec ecx
    sub ecx,r10d
    jmp .mapped
.o4:
    mov ecx,[rsp+L_H]
    dec ecx
    sub ecx,r10d
    jmp .mapped
.o5:
    mov eax,r10d
    mov ecx,r11d
    jmp .mapped
.o6:
    mov eax,[rsp+L_H]
    dec eax
    sub eax,r10d
    mov ecx,r11d
    jmp .mapped
.o7:
    mov eax,[rsp+L_H]
    dec eax
    sub eax,r10d
    mov ecx,[rsp+L_W]
    dec ecx
    sub ecx,r11d
    jmp .mapped
.o8:
    mov eax,r10d
    mov ecx,[rsp+L_W]
    dec ecx
    sub ecx,r11d
.mapped:
    imul ecx,[rsp+L_OUTW]
    add ecx,eax
    shl rcx,2
    add rcx,[rbx+PixBuf_data]
    cmp dword [rsp+L_PLANAR],2
    je .planar_pixel
    cmp dword [rsp+L_BITS],8
    jb .packed_pixel
    cmp dword [rsp+L_BITS],16
    je .pixel16
    cmp dword [rsp+L_SAMPLES],1
    jne .rgb
    mov al,[rsi]
    cmp dword [rsp+L_PHOTO],0
    jne .gray_ready
    not al
.gray_ready:
    mov [rcx],al
    mov [rcx+1],al
    mov [rcx+2],al
    mov byte [rcx+3],255
    inc rsi
    jmp .pixel_done
.rgb:
    mov al,[rsi+2]
    mov [rcx],al
    mov al,[rsi+1]
    mov [rcx+1],al
    mov al,[rsi]
    mov [rcx+2],al
    mov byte [rcx+3],255
    cmp dword [rsp+L_SAMPLES],4
    jne .rgb3
    mov al,[rsi+3]
    mov [rcx+3],al
    add rsi,4
    jmp .pixel_done
.rgb3:
    add rsi,3
    jmp .pixel_done
.pixel16:
    cmp dword [rsp+L_SAMPLES],1
    jne .rgb16
    mov al,[rsi]
    cmp dword [rsp+L_BE],0
    jne .gray16_value
    mov al,[rsi+1]
.gray16_value:
    cmp dword [rsp+L_PHOTO],0
    jne .gray16_ready
    not al
.gray16_ready:
    mov [rcx],al
    mov [rcx+1],al
    mov [rcx+2],al
    mov byte [rcx+3],255
    add rsi,2
    jmp .pixel_done
.rgb16:
    cmp dword [rsp+L_BE],0
    je .rgb16_le
    mov al,[rsi+4]
    mov [rcx],al
    mov al,[rsi+2]
    mov [rcx+1],al
    mov al,[rsi]
    mov [rcx+2],al
    mov byte [rcx+3],255
    cmp dword [rsp+L_SAMPLES],4
    jne .rgb16_3
    mov al,[rsi+6]
    mov [rcx+3],al
    add rsi,8
    jmp .pixel_done
.rgb16_le:
    mov al,[rsi+5]
    mov [rcx],al
    mov al,[rsi+3]
    mov [rcx+1],al
    mov al,[rsi+1]
    mov [rcx+2],al
    mov byte [rcx+3],255
    cmp dword [rsp+L_SAMPLES],4
    jne .rgb16_3
    mov al,[rsi+7]
    mov [rcx+3],al
    add rsi,8
    jmp .pixel_done
.rgb16_3:
    add rsi,6
    jmp .pixel_done
.packed_pixel:
    mov eax,r10d
    imul eax,[rsp+L_ROWBYTES]
    mov edx,r11d
    imul edx,[rsp+L_BITS]
    mov edi,edx
    shr edx,3
    add eax,edx
    mov rdx,[rsp+L_RASTER]
    movzx eax,byte [rdx+rax]
    and edi,7
    mov edx,8
    sub edx,[rsp+L_BITS]
    sub edx,edi
    mov ecx,edx
    shr eax,cl
    mov edx,1
    mov ecx,[rsp+L_BITS]
    shl edx,cl
    dec edx
    and eax,edx                        ; palette/gray sample
    ; Rebuild destination pointer because CL was used for shifts.
    push rax
    mov eax,r11d
    mov ecx,r10d
    mov edx,[rsp+8+L_ORIENT]
    cmp edx,2
    je .packed_o2
    cmp edx,3
    je .packed_o3
    cmp edx,4
    je .packed_o4
    cmp edx,5
    je .packed_o5
    cmp edx,6
    je .packed_o6
    cmp edx,7
    je .packed_o7
    cmp edx,8
    je .packed_o8
    jmp .packed_mapped
.packed_o2:
    mov eax,[rsp+8+L_W]
    dec eax
    sub eax,r11d
    jmp .packed_mapped
.packed_o3:
    mov eax,[rsp+8+L_W]
    dec eax
    sub eax,r11d
    mov ecx,[rsp+8+L_H]
    dec ecx
    sub ecx,r10d
    jmp .packed_mapped
.packed_o4:
    mov ecx,[rsp+8+L_H]
    dec ecx
    sub ecx,r10d
    jmp .packed_mapped
.packed_o5:
    mov eax,r10d
    mov ecx,r11d
    jmp .packed_mapped
.packed_o6:
    mov eax,[rsp+8+L_H]
    dec eax
    sub eax,r10d
    mov ecx,r11d
    jmp .packed_mapped
.packed_o7:
    mov eax,[rsp+8+L_H]
    dec eax
    sub eax,r10d
    mov ecx,[rsp+8+L_W]
    dec ecx
    sub ecx,r11d
    jmp .packed_mapped
.packed_o8:
    mov eax,r10d
    mov ecx,[rsp+8+L_W]
    dec ecx
    sub ecx,r11d
.packed_mapped:
    imul ecx,[rsp+8+L_OUTW]
    add ecx,eax
    shl rcx,2
    add rcx,[rbx+PixBuf_data]
    mov r14,rcx
    pop rax
    cmp dword [rsp+L_PHOTO],3
    je .palette_pixel
    imul eax,255
    mov edx,1
    mov ecx,[rsp+L_BITS]
    shl edx,cl
    dec edx
    div edx
    cmp dword [rsp+L_PHOTO],0
    jne .packed_gray_ready
    not al
.packed_gray_ready:
    mov [r14],al
    mov [r14+1],al
    mov [r14+2],al
    mov byte [r14+3],255
    jmp .pixel_done
.palette_pixel:
    mov rdi,[rsp+L_CMAP]
    add rdi,r12
    mov edx,1
    mov ecx,[rsp+L_BITS]
    shl edx,cl                         ; entries per color
    mov r8d,eax
    shl r8d,1
    cmp dword [rsp+L_BE],0
    jne .palette_values
    inc r8d
.palette_values:
    mov al,[rdi+r8]
    mov [r14+2],al
    mov r9d,edx
    shl r9d,1
    add r9d,r8d
    mov al,[rdi+r9]
    mov [r14+1],al
    add r9d,edx
    add r9d,edx
    mov al,[rdi+r9]
    mov [r14],al
    mov byte [r14+3],255
    jmp .pixel_done
.planar_pixel:
    mov eax,r10d
    imul eax,[rsp+L_W]
    add eax,r11d                        ; sample index
    mov rdi,[rsp+L_RASTER]
    cmp dword [rsp+L_BITS],16
    je .planar16
    cmp dword [rsp+L_SAMPLES],1
    jne .planar8_rgb
    mov al,[rdi+rax]
    cmp dword [rsp+L_PHOTO],0
    jne .planar8_gray_ready
    not al
.planar8_gray_ready:
    mov [rcx],al
    mov [rcx+1],al
    mov [rcx+2],al
    mov byte [rcx+3],255
    jmp .pixel_done
.planar8_rgb:
    mov edx,[rsp+L_W]
    imul edx,[rsp+L_H]                  ; plane bytes
    mov r8d,eax
    mov al,[rdi+r8]
    mov [rcx+2],al
    add r8d,edx
    mov al,[rdi+r8]
    mov [rcx+1],al
    add r8d,edx
    mov al,[rdi+r8]
    mov [rcx],al
    mov byte [rcx+3],255
    cmp dword [rsp+L_SAMPLES],4
    jne .pixel_done
    add r8d,edx
    mov al,[rdi+r8]
    mov [rcx+3],al
    jmp .pixel_done
.planar16:
    shl eax,1
    cmp dword [rsp+L_SAMPLES],1
    jne .planar16_rgb
    mov r8d,eax
    mov al,[rdi+r8]
    cmp dword [rsp+L_BE],0
    jne .planar16_gray_value
    mov al,[rdi+r8+1]
.planar16_gray_value:
    cmp dword [rsp+L_PHOTO],0
    jne .planar16_gray_ready
    not al
.planar16_gray_ready:
    mov [rcx],al
    mov [rcx+1],al
    mov [rcx+2],al
    mov byte [rcx+3],255
    jmp .pixel_done
.planar16_rgb:
    mov edx,[rsp+L_W]
    imul edx,[rsp+L_H]
    shl edx,1                           ; plane bytes
    mov r8d,eax
    cmp dword [rsp+L_BE],0
    jne .planar16_rgb_values
    inc r8d
.planar16_rgb_values:
    mov al,[rdi+r8]
    mov [rcx+2],al
    add r8d,edx
    mov al,[rdi+r8]
    mov [rcx+1],al
    add r8d,edx
    mov al,[rdi+r8]
    mov [rcx],al
    mov byte [rcx+3],255
    cmp dword [rsp+L_SAMPLES],4
    jne .pixel_done
    add r8d,edx
    mov al,[rdi+r8]
    mov [rcx+3],al
.pixel_done:
    inc r11d
    jmp .cx
.next_y:
    inc r10d
    jmp .cy
.composed:
    ret

.camera:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call dng_decode
    jmp .return
.bad:
    xor eax,eax
.return:
    add rsp,LOCAL_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global tiff_version
tiff_version: dq 0x020000
