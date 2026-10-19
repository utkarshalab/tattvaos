; ============================================================================
; Unit Tests — JPEG signature and canonical Huffman decoding
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

extern jpeg_probe
extern jpeg_huff_build
extern jpeg_huff_decode
extern jpeg_huff_decode_stream
extern jpeg_idct8x8
extern jpeg_bits_init
extern jpeg_bits_get
extern jpeg_receive_extend
extern jpeg_expect_restart
extern jpeg_decode_block
extern jpeg_ycbcr_to_bgra
extern jpeg_upsample_component
extern jpeg_decode_component_mcu
extern gif_inspect_animation
extern gif_apply_disposal
extern gif_composite_canvas
extern gif_decode_animation
extern arena_init
extern tiff_read_u16
extern tiff_read_u32
extern tiff_packbits_decode
extern tiff_lzw_decode
extern tiff_decode
extern dng_probe
extern dng_decode
extern sensor_sample
extern jpeg_lossless_decode
extern dng_prepare_color_matrix

%define HuffTable_SIZE 1556

section .text

global test_jpeg_suite
test_jpeg_suite:
    PROLOGUE_SAVE rbx
    xor ebx, ebx
    call test_jpeg_probe_soi
    add ebx, eax
    call test_jpeg_probe_reject
    add ebx, eax
    call test_jpeg_huffman_canonical
    add ebx, eax
    call test_jpeg_huffman_reject_oversubscribed
    add ebx, eax
    call test_jpeg_idct_dc
    add ebx, eax
    call test_jpeg_entropy
    add ebx, eax
    call test_jpeg_zero_block
    add ebx, eax
    call test_jpeg_color
    add ebx, eax
    call test_jpeg_sampling
    add ebx, eax
    call test_jpeg_component_mcu
    add ebx, eax
    call test_gif_animation_metadata
    add ebx, eax
    call test_gif_disposal
    add ebx, eax
    call test_gif_decode_animation
    add ebx, eax
    call test_tiff_primitives
    add ebx, eax
    call test_tiff_endian_decode
    add ebx, eax
    call test_sensor_crop
    add ebx, eax
    call test_dng_color_matrix
    add ebx, eax
    call test_dng_tiled_decode
    add ebx, eax
    mov eax, ebx
    EPILOGUE_RESTORE rbx
    ret

global test_jpeg_main
test_jpeg_main:
    jmp test_jpeg_suite

global test_jpeg_probe_soi
test_jpeg_probe_soi:
    lea rdi, [rel jpeg_soi]
    mov esi, 2
    call jpeg_probe
    cmp eax, 1
    sete al
    xor al, 1
    movzx eax, al
    ret

global test_jpeg_probe_reject
test_jpeg_probe_reject:
    lea rdi, [rel not_jpeg]
    mov esi, 2
    call jpeg_probe
    test eax, eax
    setne al
    movzx eax, al
    ret

; Counts 1,1,2 generate codes: A=0, B=10, C=110, D=111.
; The MSB-aligned stream 0|10|110|111 must decode A,B,C,D.
global test_jpeg_huffman_canonical
test_jpeg_huffman_canonical:
    PROLOGUE_SAVE rbx, r12
    lea rdi, [rel huff_table]
    lea rsi, [rel huff_counts]
    lea rdx, [rel huff_symbols]
    mov ecx, 4
    call jpeg_huff_build
    test eax, eax
    js .fail
    mov rax, 0x5B80000000000000
    mov [rel bitreader], rax
    mov qword [rel bitreader + 8], 9
    lea rbx, [rel expected]
    xor r12d, r12d
.decode:
    lea rdi, [rel huff_table]
    lea rsi, [rel bitreader]
    call jpeg_huff_decode
    cmp al, [rbx + r12]
    jne .fail
    inc r12d
    cmp r12d, 4
    jb .decode
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

global test_jpeg_huffman_reject_oversubscribed
test_jpeg_huffman_reject_oversubscribed:
    lea rdi, [rel huff_table]
    lea rsi, [rel oversubscribed_counts]
    lea rdx, [rel oversubscribed_symbols]
    mov ecx, 3
    call jpeg_huff_build
    test eax, eax
    sets al
    xor al, 1
    movzx eax, al
    ret

; A DC-only block must produce one uniform level. DC=80 yields 128+10.
global test_jpeg_idct_dc
test_jpeg_idct_dc:
    PROLOGUE_SAVE rbx
    lea rdi, [rel idct_block]
    xor eax, eax
    mov ecx, 16
    rep stosq
    mov word [rel idct_block], 80
    lea rdi, [rel idct_block]
    lea rsi, [rel unit_quant]
    call jpeg_idct8x8
    test eax, eax
    jnz .idct_fail
    lea rbx, [rel idct_block]
    xor ecx, ecx
.idct_check:
    cmp word [rbx + rcx * 2], 138
    jne .idct_fail
    inc ecx
    cmp ecx, 64
    jb .idct_check
    xor eax, eax
    EPILOGUE_RESTORE rbx
    ret
.idct_fail:
    mov eax, 1
    EPILOGUE_RESTORE rbx
    ret

global test_jpeg_entropy
test_jpeg_entropy:
    PROLOGUE_SAVE rbx
    lea rdi, [rel entropy_reader]
    lea rsi, [rel stuffed_stream]
    mov edx, stuffed_stream_end - stuffed_stream
    call jpeg_bits_init
    test eax, eax
    jnz .entropy_fail
    lea rdi, [rel entropy_reader]
    mov esi, 4
    call jpeg_bits_get
    cmp eax, 0x0A
    jne .entropy_fail
    lea rdi, [rel entropy_reader]
    mov esi, 8
    call jpeg_bits_get
    cmp eax, 0xAF
    jne .entropy_fail
    lea rdi, [rel entropy_reader]
    mov esi, 8
    call jpeg_bits_get
    cmp eax, 0xFC
    jne .entropy_fail
    lea rdi, [rel entropy_reader]
    mov esi, 8
    call jpeg_bits_get
    test eax, eax
    jns .entropy_fail
    cmp dword [rel entropy_reader + 28], 0xD0
    jne .entropy_fail

    lea rdi, [rel entropy_reader]
    lea rsi, [rel amplitude_stream]
    mov edx, 1
    call jpeg_bits_init
    lea rdi, [rel entropy_reader]
    mov esi, 3
    call jpeg_receive_extend
    cmp eax, -4
    jne .entropy_fail
    lea rdi, [rel entropy_reader]
    mov esi, 3
    call jpeg_receive_extend
    cmp eax, 7
    jne .entropy_fail

    lea rdi, [rel entropy_reader]
    lea rsi, [rel restart_stream]
    mov edx, restart_stream_end - restart_stream
    call jpeg_bits_init
    lea rdi, [rel entropy_reader]
    xor esi, esi
    call jpeg_expect_restart
    test eax, eax
    jnz .entropy_fail
    lea rdi, [rel entropy_reader]
    mov esi, 1
    call jpeg_expect_restart
    test eax, eax
    jnz .entropy_fail

    lea rdi, [rel entropy_reader]
    lea rsi, [rel canonical_stream]
    mov edx, 2
    call jpeg_bits_init
    lea rbx, [rel expected]
    xor ecx, ecx
.stream_huff:
    push rcx
    lea rdi, [rel huff_table]
    lea rsi, [rel entropy_reader]
    call jpeg_huff_decode_stream
    pop rcx
    cmp al, [rbx + rcx]
    jne .entropy_fail
    inc ecx
    cmp ecx, 4
    jb .stream_huff
    xor eax, eax
    EPILOGUE_RESTORE rbx
    ret
.entropy_fail:
    mov eax, 1
    EPILOGUE_RESTORE rbx
    ret

; DC category 0 followed by AC EOB decodes to a flat level-128 block.
global test_jpeg_zero_block
test_jpeg_zero_block:
    PROLOGUE_SAVE rbx
    lea rdi, [rel dc_zero_table]
    lea rsi, [rel zero_counts]
    lea rdx, [rel zero_symbol]
    mov ecx, 1
    call jpeg_huff_build
    test eax, eax
    jnz .block_fail
    lea rdi, [rel ac_eob_table]
    lea rsi, [rel zero_counts]
    lea rdx, [rel zero_symbol]
    mov ecx, 1
    call jpeg_huff_build
    test eax, eax
    jnz .block_fail
    mov dword [rel dc_predictor], 0
    lea rdi, [rel entropy_reader]
    lea rsi, [rel zero_block_stream]
    mov edx, 1
    call jpeg_bits_init
    lea rdi, [rel entropy_reader]
    lea rsi, [rel dc_zero_table]
    lea rdx, [rel ac_eob_table]
    lea rcx, [rel dc_predictor]
    lea r8, [rel unit_quant]
    lea r9, [rel idct_block]
    call jpeg_decode_block
    test eax, eax
    jnz .block_fail
    cmp dword [rel dc_predictor], 0
    jne .block_fail
    lea rbx, [rel idct_block]
    xor ecx, ecx
.block_pixels:
    cmp word [rbx + rcx * 2], 128
    jne .block_fail
    inc ecx
    cmp ecx, 64
    jb .block_pixels
    xor eax, eax
    EPILOGUE_RESTORE rbx
    ret
.block_fail:
    mov eax, 1
    EPILOGUE_RESTORE rbx
    ret

global test_jpeg_color
test_jpeg_color:
    lea rdi, [rel color_output]
    lea rsi, [rel color_y]
    lea rdx, [rel color_neutral]
    lea rcx, [rel color_neutral]
    mov r8d, 3
    call jpeg_ycbcr_to_bgra
    test eax, eax
    jnz .color_fail
    cmp dword [rel color_output], 0xFF000000
    jne .color_fail
    cmp dword [rel color_output + 4], 0xFF808080
    jne .color_fail
    cmp dword [rel color_output + 8], 0xFFFFFFFF
    jne .color_fail
    lea rdi, [rel color_output]
    lea rsi, [rel color_mid]
    lea rdx, [rel color_high]
    lea rcx, [rel color_high]
    mov r8d, 1
    call jpeg_ycbcr_to_bgra
    cmp dword [rel color_output], 0xFFFF00FF
    jne .color_fail
    xor eax, eax
    ret
.color_fail:
    mov eax, 1
    ret

global test_jpeg_sampling
test_jpeg_sampling:
    lea rdi, [rel sample_source]
    xor eax, eax
.sample_init:
    mov [rdi + rax * 2], ax
    inc eax
    cmp eax, 64
    jb .sample_init
    lea rdi, [rel sample_output]
    lea rsi, [rel sample_source]
    mov edx, 1
    mov ecx, 1
    mov r8d, 2
    mov r9d, 2
    call jpeg_upsample_component
    test eax, eax
    jnz .sampling_fail
    cmp word [rel sample_output], 0
    jne .sampling_fail
    cmp word [rel sample_output + 2], 0
    jne .sampling_fail
    cmp word [rel sample_output + 4], 1
    jne .sampling_fail
    cmp word [rel sample_output + 32], 0
    jne .sampling_fail
    cmp word [rel sample_output + 64], 8
    jne .sampling_fail
    cmp word [rel sample_output + 510], 63
    jne .sampling_fail
    xor eax, eax
    ret
.sampling_fail:
    mov eax, 1
    ret

global test_jpeg_component_mcu
test_jpeg_component_mcu:
    mov dword [rel dc_predictor], 0
    lea rdi, [rel entropy_reader]
    lea rsi, [rel component_stream]
    mov edx, 1
    call jpeg_bits_init
    lea rdi, [rel entropy_reader]
    lea rsi, [rel dc_zero_table]
    lea rdx, [rel ac_eob_table]
    lea rcx, [rel dc_predictor]
    lea r8, [rel unit_quant]
    lea r9, [rel sample_output]
    mov r10d, 2
    mov r11d, 2
    call jpeg_decode_component_mcu
    test eax, eax
    jnz .component_fail
    lea rdi, [rel sample_output]
    xor ecx, ecx
.component_pixels:
    cmp word [rdi + rcx * 2], 128
    jne .component_fail
    inc ecx
    cmp ecx, 256
    jb .component_pixels
    xor eax, eax
    ret
.component_fail:
    mov eax, 1
    ret

global test_gif_animation_metadata
test_gif_animation_metadata:
    lea rdi, [rel gif_animation]
    mov esi, gif_animation_end - gif_animation
    lea rdx, [rel gif_info]
    call gif_inspect_animation
    test eax, eax
    jnz .gif_fail
    cmp dword [rel gif_info + GifAnimationInfo.width], 1
    jne .gif_fail
    cmp dword [rel gif_info + GifAnimationInfo.height], 1
    jne .gif_fail
    cmp dword [rel gif_info + GifAnimationInfo.frame_count], 2
    jne .gif_fail
    cmp dword [rel gif_info + GifAnimationInfo.loop_count], 0
    jne .gif_fail
    cmp qword [rel gif_info + GifAnimationInfo.duration_cs], 12
    jne .gif_fail
    lea rdi, [rel gif_truncated]
    mov esi, gif_truncated_end - gif_truncated
    lea rdx, [rel gif_info]
    call gif_inspect_animation
    test eax, eax
    jns .gif_fail
    xor eax, eax
    ret
.gif_fail:
    mov eax, 1
    ret

global test_gif_disposal
test_gif_disposal:
    lea rdi, [rel gif_canvas]
    lea rsi, [rel gif_pixels]
    call init_test_pixbuf
    lea rdi, [rel gif_saved]
    lea rsi, [rel gif_saved_pixels]
    call init_test_pixbuf
    lea rdi, [rel gif_pixels]
    mov eax, 0xAABBCCDD
    mov ecx, 12
    rep stosd
    lea rdi, [rel gif_saved_pixels]
    mov eax, 0x01020304
    mov ecx, 12
    rep stosd
    lea rdi, [rel gif_canvas]
    xor esi, esi
    mov edx, 1
    mov ecx, 1
    mov r8d, 2
    mov r9d, 1
    mov r10d, 2
    mov r11d, 0x11223344
    call gif_apply_disposal
    test eax, eax
    jnz .disposal_fail
    cmp dword [rel gif_pixels + 16], 0xAABBCCDD
    jne .disposal_fail
    cmp dword [rel gif_pixels + 20], 0x11223344
    jne .disposal_fail
    cmp dword [rel gif_pixels + 24], 0x11223344
    jne .disposal_fail
    lea rdi, [rel gif_canvas]
    lea rsi, [rel gif_saved]
    mov edx, 1
    mov ecx, 1
    mov r8d, 2
    mov r9d, 1
    mov r10d, 3
    xor r11d, r11d
    call gif_apply_disposal
    test eax, eax
    jnz .disposal_fail
    cmp dword [rel gif_pixels + 20], 0x01020304
    jne .disposal_fail
    cmp dword [rel gif_pixels + 24], 0x01020304
    jne .disposal_fail
    lea rdi, [rel gif_saved_pixels]
    xor eax, eax
    mov ecx, 12
    rep stosd
    mov dword [rel gif_saved_pixels], 0xFF332211
    mov dword [rel gif_saved_pixels + 4], 0x00332211
    mov dword [rel gif_pixels], 0xFF010101
    mov dword [rel gif_pixels + 4], 0xFF020202
    lea rdi, [rel gif_canvas]
    lea rsi, [rel gif_saved]
    call gif_composite_canvas
    test eax, eax
    jnz .disposal_fail
    cmp dword [rel gif_pixels], 0xFF332211
    jne .disposal_fail
    cmp dword [rel gif_pixels + 4], 0xFF020202
    jne .disposal_fail
    xor eax, eax
    ret
.disposal_fail:
    mov eax, 1
    ret

init_test_pixbuf:
    mov qword [rdi + PixBuf_width], 4
    mov qword [rdi + PixBuf_height], 3
    mov qword [rdi + PixBuf_stride], 16
    mov qword [rdi + PixBuf_format], DRM_FORMAT_BGRA8888
    mov [rdi + PixBuf_data], rsi
    mov qword [rdi + PixBuf_size], 48
    ret

global test_gif_decode_animation
test_gif_decode_animation:
    lea rdi, [rel gif_test_arena]
    lea rsi, [rel gif_test_storage]
    mov edx, 131072
    call arena_init
    test eax, eax
    jnz .decode_animation_fail
    lea rdi, [rel gif_test_arena]
    lea rsi, [rel gif_animation]
    mov edx, gif_animation_end - gif_animation
    call gif_decode_animation
    test rax, rax
    jz .decode_animation_fail
    cmp dword [rax + GifAnimation.frame_count], 2
    jne .decode_animation_fail
    cmp dword [rax + GifAnimation.loop_count], 0
    jne .decode_animation_fail
    mov rdx, [rax + GifAnimation.delays_cs]
    cmp dword [rdx], 5
    jne .decode_animation_fail
    cmp dword [rdx + 4], 7
    jne .decode_animation_fail
    mov rdx, [rax + GifAnimation.frames]
    cmp qword [rdx], 0
    je .decode_animation_fail
    cmp qword [rdx + 8], 0
    je .decode_animation_fail
    mov rdx, [rdx]
    mov rdx, [rdx + PixBuf_data]
    cmp dword [rdx], 0xFF000000
    jne .decode_animation_fail
    xor eax, eax
    ret
.decode_animation_fail:
    mov eax, 1
    ret

global test_tiff_primitives
test_tiff_primitives:
    lea rdi,[rel tiff_endian_words]
    xor esi,esi
    call tiff_read_u16
    cmp eax,0x1234
    jne .fail
    lea rdi,[rel tiff_endian_words+2]
    mov esi,1
    call tiff_read_u32
    cmp eax,0x12345678
    jne .fail
    lea rdi,[rel tiff_packbits]
    mov esi,tiff_packbits_end-tiff_packbits
    lea rdx,[rel tiff_packbits_out]
    mov ecx,6
    call tiff_packbits_decode
    cmp eax,6
    jne .fail
    cmp dword [rel tiff_packbits_out],0x42414241
    jne .fail
    cmp word [rel tiff_packbits_out+4],0x4343
    jne .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel gif_test_storage]
    mov edx,131072
    call arena_init
    test eax,eax
    jnz .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel tiff_lzw]
    mov edx,tiff_lzw_end-tiff_lzw
    lea rcx,[rel tiff_lzw_out]
    mov r8d,1
    call tiff_lzw_decode
    cmp eax,1
    jne .fail
    cmp byte [rel tiff_lzw_out],'A'
    jne .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel lossless_jpeg]
    mov edx,lossless_jpeg_end-lossless_jpeg
    lea rcx,[rel lossless_jpeg_out]
    mov r8d,1
    mov r9d,1
    call jpeg_lossless_decode
    cmp eax,1
    jne .fail
    cmp byte [rel lossless_jpeg_out],128
    jne .fail
    lea rdi,[rel tiff_le]
    mov esi,tiff_le_end-tiff_le
    call dng_probe
    cmp eax,1
    jne .fail
    lea rdi,[rel tiff_be]
    mov esi,tiff_be_end-tiff_be
    call dng_probe
    cmp eax,1
    jne .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

global test_tiff_endian_decode
test_tiff_endian_decode:
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel gif_test_storage]
    mov edx,131072
    call arena_init
    test eax,eax
    jnz .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel tiff_le]
    mov edx,tiff_le_end-tiff_le
    call tiff_decode
    test rax,rax
    jz .fail
    mov rdx,[rax+PixBuf_data]
    cmp dword [rdx],0xffffffff
    jne .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel tiff_be]
    mov edx,tiff_be_end-tiff_be
    call tiff_decode
    test rax,rax
    jz .fail
    mov rdx,[rax+PixBuf_data]
    cmp dword [rdx],0xff202020
    jne .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel tiff_1bit]
    mov edx,tiff_1bit_end-tiff_1bit
    call tiff_decode
    test rax,rax
    jz .fail
    mov rdx,[rax+PixBuf_data]
    cmp dword [rdx],0xffffffff
    jne .fail
    cmp dword [rdx+4],0xff000000
    jne .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel tiff_tile]
    mov edx,tiff_tile_end-tiff_tile
    call tiff_decode
    test rax,rax
    jz .fail
    mov rdx,[rax+PixBuf_data]
    cmp dword [rdx],0xff7f7f7f
    jne .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

global test_sensor_crop
test_sensor_crop:
    lea rdi,[rel sensor_crop_desc]
    xor eax,eax
    mov ecx,SensorImageDesc_size/8
    rep stosq
    mov dword [rel sensor_crop_desc+SensorImageDesc.width],1
    mov dword [rel sensor_crop_desc+SensorImageDesc.height],1
    mov dword [rel sensor_crop_desc+SensorImageDesc.stride],2
    mov dword [rel sensor_crop_desc+SensorImageDesc.bit_depth],8
    mov dword [rel sensor_crop_desc+SensorImageDesc.white_level],255
    mov dword [rel sensor_crop_desc+SensorImageDesc.crop_x],1
    mov dword [rel sensor_crop_desc+SensorImageDesc.crop_y],1
    lea rdi,[rel sensor_crop_data]
    mov esi,sensor_crop_data_end-sensor_crop_data
    lea rdx,[rel sensor_crop_desc]
    xor ecx,ecx
    xor r8d,r8d
    call sensor_sample
    cmp eax,32896
    jne .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

global test_dng_color_matrix
test_dng_color_matrix:
    lea rdi,[rel dng_matrix_test]
    xor eax,eax
    mov ecx,5
    rep stosq
    mov dword [rel dng_matrix_test],0x10000
    mov dword [rel dng_matrix_test+16],0x10000
    mov dword [rel dng_matrix_test+32],0x10000
    lea rdi,[rel dng_matrix_test]
    call dng_prepare_color_matrix
    test eax,eax
    js .fail
    lea rsi,[rel dng_matrix_expected]
    lea rdi,[rel dng_matrix_test]
    xor ecx,ecx
.check:
    mov eax,[rdi+rcx*4]
    cmp eax,[rsi+rcx*4]
    jne .fail
    inc ecx
    cmp ecx,9
    jb .check
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

global test_dng_tiled_decode
test_dng_tiled_decode:
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel gif_test_storage]
    mov edx,131072
    call arena_init
    test eax,eax
    jnz .fail
    lea rdi,[rel gif_test_arena]
    lea rsi,[rel dng_tiled]
    mov edx,dng_tiled_end-dng_tiled
    call dng_decode
    test rax,rax
    jz .fail
    cmp qword [rax+PixBuf_width],2
    jne .fail
    cmp qword [rax+PixBuf_height],1
    jne .fail
    cmp qword [rax+PixBuf_data],0
    je .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

section .rodata
jpeg_soi:      db 0xFF, 0xD8
not_jpeg:      db 0x89, 0x50
; Two 1x1 raw CFA tiles exercise tile-array lookup and horizontal placement.
dng_tiled:
    db 'II',42,0
    dd 8
    dw 11
    dw 256,4
    dd 1
    dd 2
    dw 257,4
    dd 1
    dd 1
    dw 258,3
    dd 1
    dw 8,0
    dw 259,3
    dd 1
    dw 1,0
    dw 262,3
    dd 1
    dw 32803,0
    dw 277,3
    dd 1
    dw 1,0
    dw 322,4
    dd 1
    dd 1
    dw 323,4
    dd 1
    dd 1
    dw 324,4
    dd 2
    dd dng_tiled_offsets-dng_tiled
    dw 325,4
    dd 2
    dd dng_tiled_counts-dng_tiled
    dw 33422,1
    dd 4
    db 0,1,1,2
    dd 0
dng_tiled_offsets:
    dd dng_tiled_pixels-dng_tiled, dng_tiled_pixels+1-dng_tiled
dng_tiled_counts:
    dd 1,1
dng_tiled_pixels:
    db 32,224
dng_tiled_end:
huff_counts:   db 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
huff_symbols:  db 'A', 'B', 'C', 'D'
oversubscribed_counts: db 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
oversubscribed_symbols: db 1, 2, 3
expected:      db 'A', 'B', 'C', 'D'
stuffed_stream: db 0xAA, 0xFF, 0x00, 0xC0, 0xFF, 0xD0
stuffed_stream_end:
amplitude_stream: db 0x7C
canonical_stream: db 0x5B, 0x80
restart_stream: db 0xFF, 0xD0, 0xFF, 0xFF, 0xD1
restart_stream_end:
zero_counts:     db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
zero_symbol:     db 0
zero_block_stream: db 0
component_stream: db 0
align 16
unit_quant:    times 64 dd 1
color_y:       dw 0, 128, 255
color_neutral: dw 128, 128, 128
color_mid:     dw 128
color_high:    dw 255
gif_animation:
    db 'GIF89a', 1,0, 1,0, 0x80,0,0
    db 0,0,0, 255,255,255
    db 0x21,0xFF,11,'NETSCAPE2.0',3,1,0,0,0
    db 0x21,0xF9,4,0,5,0,0,0
    db 0x2C,0,0,0,0,1,0,1,0,0, 2,2,0x44,0x01,0
    db 0x21,0xF9,4,0,7,0,0,0
    db 0x2C,0,0,0,0,1,0,1,0,0, 2,2,0x44,0x01,0
    db 0x3B
gif_animation_end:
gif_truncated:
    db 'GIF89a', 1,0, 1,0, 0,0,0
    db 0x2C,0,0,0,0,1,0,1,0,0, 2,5,0x44
gif_truncated_end:
tiff_endian_words: db 0x34,0x12, 0x12,0x34,0x56,0x78
tiff_packbits: db 3,'A','B','A','B', 0xff,'C'
tiff_packbits_end:
tiff_lzw: db 0x80,0x10,0x60,0x20
tiff_lzw_end:
sensor_crop_data: db 0,0,0,128
sensor_crop_data_end:
lossless_jpeg:
    db 0xff,0xd8
    db 0xff,0xc4, 0,20, 0
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0
    db 0xff,0xc3, 0,11, 8, 0,1, 0,1, 1, 1,0x11,0
    db 0xff,0xda, 0,8, 1, 1,0, 1,0,0
    db 0
    db 0xff,0xd9
lossless_jpeg_end:
dng_matrix_expected:
    dd 205380,-105963,-32153
    dd -64145,125576,2192
    dd 4715,-15007,92094

; 1x1, 8-bit black-is-zero grayscale, one uncompressed strip.
tiff_le:
    db 'II',42,0,8,0,0,0
    dw 9
    dw 256,4,1,0
    dd 1
    dw 257,4,1,0
    dd 1
    dw 258,3,1,0
    dw 8,0
    dw 259,3,1,0
    dw 1,0
    dw 262,3,1,0
    dw 1,0
    dw 273,4,1,0
    dd 122
    dw 277,3,1,0
    dw 1,0
    dw 278,4,1,0
    dd 1
    dw 279,4,1,0
    dd 1
    dd 0
    db 255
tiff_le_end:

tiff_be:
    db 'MM',0,42, 0,0,0,8
    db 0,9
    db 1,0, 0,4, 0,0,0,1, 0,0,0,1
    db 1,1, 0,4, 0,0,0,1, 0,0,0,1
    db 1,2, 0,3, 0,0,0,1, 0,8,0,0
    db 1,3, 0,3, 0,0,0,1, 0,1,0,0
    db 1,6, 0,3, 0,0,0,1, 0,1,0,0
    db 1,17,0,4, 0,0,0,1, 0,0,0,122
    db 1,21,0,3, 0,0,0,1, 0,1,0,0
    db 1,22,0,4, 0,0,0,1, 0,0,0,1
    db 1,23,0,4, 0,0,0,1, 0,0,0,1
    dd 0
    db 0x20
tiff_be_end:
tiff_1bit:
    db 'II',42,0,8,0,0,0
    dw 9
    dw 256,4,1,0
    dd 2
    dw 257,4,1,0
    dd 1
    dw 258,3,1,0
    dw 1,0
    dw 259,3,1,0
    dw 1,0
    dw 262,3,1,0
    dw 1,0
    dw 273,4,1,0
    dd 122
    dw 277,3,1,0
    dw 1,0
    dw 278,4,1,0
    dd 1
    dw 279,4,1,0
    dd 1
    dd 0
    db 0x80
tiff_1bit_end:
tiff_tile:
    db 'II',42,0,8,0,0,0
    dw 9
    dw 256,4,1,0
    dd 1
    dw 257,4,1,0
    dd 1
    dw 258,3,1,0
    dw 8,0
    dw 259,3,1,0
    dw 1,0
    dw 262,3,1,0
    dw 1,0
    dw 322,4,1,0
    dd 1
    dw 323,4,1,0
    dd 1
    dw 324,4,1,0
    dd 122
    dw 325,4,1,0
    dd 1
    dd 0
    db 0x7f
tiff_tile_end:

section .bss
alignb 16
huff_table:    resb HuffTable_SIZE
bitreader:     resq 2
alignb 16
idct_block:    resw 64
alignb 16
entropy_reader: resb 32
alignb 16
dc_zero_table:  resb HuffTable_SIZE
alignb 16
ac_eob_table:   resb HuffTable_SIZE
dc_predictor:   resd 1
color_output:   resd 3
alignb 16
sample_source:  resw 64
sample_output:  resw 256
alignb 8
gif_info:       resb GifAnimationInfo_size
alignb 16
gif_canvas:     resb 64
gif_saved:      resb 64
gif_pixels:     resd 12
gif_saved_pixels: resd 12
tiff_packbits_out: resb 6
tiff_lzw_out: resb 1
lossless_jpeg_out: resb 2
alignb 16
sensor_crop_desc: resb SensorImageDesc_size
dng_matrix_test: resd 10
alignb 16
gif_test_arena: resb 32
alignb 16
gif_test_storage: resb 131072

section .data
global test_jpeg_version
test_jpeg_version: dq 0x010100
