; WebP RIFF and primary-bitstream metadata tests.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern webp_probe
extern webp_inspect
extern webp_bits_init
extern webp_bits_get
extern webp_huff_build
extern webp_huff_decode
extern webp_huff_read
extern webp_huff_group_read
extern webp_prefix_value
extern webp_copy_pixels
extern webp_color_cache_index
extern webp_huff_group_decode_literals
extern webp_distance_value
extern webp_huff_group_decode
extern webp_huff_group_decode_one
extern webp_huff_groups_decode
extern webp_decode_image
extern webp_vp8l_decode
extern webp_bool_init
extern webp_bool_get
extern webp_bool_literal
extern webp_vp8_inspect
extern webp_vp8_idct4x4
extern webp_vp8_iwht4x4
extern webp_vp8_add_block
extern webp_vp8_yuv420_to_bgra
extern webp_inverse_subtract_green
extern webp_inverse_color
extern webp_inverse_color_index
extern webp_palette_expand
extern webp_predict_basic
extern webp_inverse_predictor

section .text
global test_webp_suite
test_webp_suite:
    PROLOGUE_SAVE rbx
    xor ebx,ebx
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_bits]
    mov edx,2
    call webp_bits_init
    test eax,eax
    jnz .bits_fail
    lea rdi,[rel webp_reader]
    mov esi,3
    call webp_bits_get
    cmp eax,5
    jne .bits_fail
    lea rdi,[rel webp_reader]
    mov esi,7
    call webp_bits_get
    cmp eax,85
    jne .bits_fail
    lea rdi,[rel webp_reader]
    mov esi,6
    call webp_bits_get
    cmp eax,42
    jne .bits_fail
    lea rdi,[rel webp_reader]
    mov esi,1
    call webp_bits_get
    cmp eax,-EINVAL
    je .bits_done
.bits_fail:
    inc ebx
.bits_done:
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_bool_zeros]
    mov edx,webp_bool_zeros_end-webp_bool_zeros
    call webp_bool_init
    test eax,eax
    jnz .bool_fail
    lea rdi,[rel webp_bool_reader]
    mov esi,16
    call webp_bool_literal
    test eax,eax
    jnz .bool_fail
    lea rdi,[rel webp_vp8+20]
    mov esi,10
    lea rdx,[rel webp_vp8_info]
    call webp_vp8_inspect
    test eax,eax
    jnz .bool_fail
    cmp dword [rel webp_vp8_info+WebPVP8Info.width],4
    jne .bool_fail
    cmp dword [rel webp_vp8_info+WebPVP8Info.height],5
    je .bool_done
.bool_fail:
    inc ebx
.bool_done:
    lea rdi,[rel webp_vp8_coeffs]
    xor eax,eax
    mov ecx,8
    rep stosd
    mov word [rel webp_vp8_coeffs],8
    lea rdi,[rel webp_vp8_coeffs]
    lea rsi,[rel webp_vp8_residual]
    call webp_vp8_idct4x4
    test eax,eax
    jnz .recon_fail
    lea rdi,[rel webp_vp8_residual]
    mov ecx,16
.idct_vector:
    cmp word [rdi],1
    jne .recon_fail
    add rdi,2
    loop .idct_vector
    lea rdi,[rel webp_vp8_coeffs]
    lea rsi,[rel webp_vp8_residual]
    call webp_vp8_iwht4x4
    test eax,eax
    jnz .recon_fail
    lea rdi,[rel webp_vp8_residual]
    mov ecx,16
.wht_vector:
    cmp word [rdi],1
    jne .recon_fail
    add rdi,2
    loop .wht_vector
    lea rdi,[rel webp_vp8_coeffs]
    mov eax,-8
    mov ecx,16
.coeff_ramp:
    mov [rdi],ax
    inc eax
    add rdi,2
    loop .coeff_ramp
    lea rdi,[rel webp_vp8_coeffs]
    lea rsi,[rel webp_vp8_residual]
    call webp_vp8_idct4x4
    test eax,eax
    jnz .recon_fail
    lea rdi,[rel webp_vp8_residual]
    lea rsi,[rel webp_vp8_idct_expected]
    mov ecx,16
.idct_ac_vector:
    mov ax,[rsi]
    cmp [rdi],ax
    jne .recon_fail
    add rdi,2
    add rsi,2
    loop .idct_ac_vector
    lea rdi,[rel webp_vp8_coeffs]
    lea rsi,[rel webp_vp8_residual]
    call webp_vp8_iwht4x4
    test eax,eax
    jnz .recon_fail
    lea rdi,[rel webp_vp8_residual]
    lea rsi,[rel webp_vp8_wht_expected]
    mov ecx,16
.wht_ac_vector:
    mov ax,[rsi]
    cmp [rdi],ax
    jne .recon_fail
    add rdi,2
    add rsi,2
    loop .wht_ac_vector
    lea rdi,[rel webp_vp8_predict]
    mov al,250
    mov ecx,16
    rep stosb
    lea rdi,[rel webp_vp8_residual]
    mov ax,10
    mov ecx,16
    rep stosw
    lea rdi,[rel webp_vp8_block]
    mov esi,4
    lea rdx,[rel webp_vp8_predict]
    mov ecx,4
    lea r8,[rel webp_vp8_residual]
    call webp_vp8_add_block
    test eax,eax
    jnz .recon_fail
    lea rdi,[rel webp_vp8_block]
    mov ecx,16
.add_vector:
    cmp byte [rdi],255
    jne .recon_fail
    inc rdi
    loop .add_vector
    mov dword [rel webp_vp8_y],0x10101010
    mov byte [rel webp_vp8_u],128
    mov byte [rel webp_vp8_v],128
    lea rdi,[rel webp_yuv_state]
    lea rax,[rel webp_vp8_y]
    mov [rdi+WebPYUVState.y],rax
    lea rax,[rel webp_vp8_u]
    mov [rdi+WebPYUVState.u],rax
    lea rax,[rel webp_vp8_v]
    mov [rdi+WebPYUVState.v],rax
    lea rax,[rel webp_vp8_bgra]
    mov [rdi+WebPYUVState.output],rax
    mov dword [rdi+WebPYUVState.width],2
    mov dword [rdi+WebPYUVState.height],2
    mov dword [rdi+WebPYUVState.y_stride],2
    mov dword [rdi+WebPYUVState.uv_stride],1
    mov dword [rdi+WebPYUVState.output_stride],8
    call webp_vp8_yuv420_to_bgra
    test eax,eax
    jnz .recon_fail
    cmp dword [rel webp_vp8_bgra],0xff000000
    jne .recon_fail
    cmp dword [rel webp_vp8_bgra+12],0xff000000
    je .recon_done
.recon_fail:
    inc ebx
.recon_done:
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_huff_lengths]
    mov edx,3
    call webp_huff_build
    test eax,eax
    jnz .huff_fail
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_huff_bits]
    mov edx,1
    call webp_bits_init
    test eax,eax
    jnz .huff_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    test eax,eax
    jnz .huff_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,1
    jne .huff_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,2
    jne .huff_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_huff_bad_lengths]
    mov edx,3
    call webp_huff_build
    cmp eax,-EINVAL
    je .huff_done
.huff_fail:
    inc ebx
.huff_done:
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_simple_bits]
    mov edx,2
    call webp_bits_init
    lea rdi,[rel webp_reader]
    mov esi,4
    lea rdx,[rel webp_huff_table]
    lea rcx,[rel webp_huff_scratch]
    lea r8,[rel webp_huff_temp]
    call webp_huff_read
    test eax,eax
    jnz .huff_read_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    test eax,eax
    jnz .huff_read_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,2
    je .huff_read_done
.huff_read_fail:
    inc ebx
.huff_read_done:
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_normal_bits]
    mov edx,3
    call webp_bits_init
    lea rdi,[rel webp_reader]
    mov esi,4
    lea rdx,[rel webp_huff_table]
    lea rcx,[rel webp_huff_scratch]
    lea r8,[rel webp_huff_temp]
    call webp_huff_read
    test eax,eax
    jnz .huff_normal_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    test eax,eax
    jnz .huff_normal_fail
    lea rdi,[rel webp_huff_table]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,1
    je .huff_normal_done
.huff_normal_fail:
    inc ebx
.huff_normal_done:
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_group_bits]
    mov edx,webp_group_bits_end-webp_group_bits
    call webp_bits_init
    lea rdi,[rel webp_reader]
    xor esi,esi
    lea rdx,[rel webp_huff_group]
    lea rcx,[rel webp_huff_scratch]
    lea r8,[rel webp_huff_temp]
    call webp_huff_group_read
    test eax,eax
    jnz .group_fail
    lea rdi,[rel webp_huff_group+WEBP_GROUP_GREEN]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,34
    jne .group_fail
    lea rdi,[rel webp_huff_group+WEBP_GROUP_RED]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,17
    jne .group_fail
    lea rdi,[rel webp_huff_group+WEBP_GROUP_BLUE]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,51
    jne .group_fail
    lea rdi,[rel webp_huff_group+WEBP_GROUP_ALPHA]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    cmp eax,255
    jne .group_fail
    lea rdi,[rel webp_huff_group+WEBP_GROUP_DISTANCE]
    lea rsi,[rel webp_reader]
    call webp_huff_decode
    test eax,eax
    jz .group_done
.group_fail:
    inc ebx
.group_done:
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena],rax
    mov [rel webp_entropy_arena+8],rax
    add rax,65536
    mov [rel webp_entropy_arena+16],rax
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_image_bits]
    mov edx,webp_image_bits_end-webp_image_bits
    call webp_bits_init
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_entropy_arena]
    mov edx,1
    mov ecx,1
    lea r8,[rel webp_entropy_output]
    mov r9d,1
    call webp_decode_image
    test eax,eax
    jnz .image_data_fail
    cmp dword [rel webp_entropy_output],0xff112233
    je .image_data_done
.image_data_fail:
    inc ebx
.image_data_done:
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena],rax
    mov [rel webp_entropy_arena+8],rax
    add rax,65536
    mov [rel webp_entropy_arena+16],rax
    lea rdi,[rel webp_entropy_arena]
    lea rsi,[rel webp_vp8l_plain]
    mov edx,webp_vp8l_plain_end-webp_vp8l_plain
    call webp_vp8l_decode
    test rax,rax
    jz .vp8l_integration_fail
    mov rax,[rax+PixBuf_data]
    cmp dword [rax],0xff112233
    jne .vp8l_integration_fail
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena+8],rax
    lea rdi,[rel webp_entropy_arena]
    lea rsi,[rel webp_vp8l_green]
    mov edx,webp_vp8l_green_end-webp_vp8l_green
    call webp_vp8l_decode
    test rax,rax
    jz .vp8l_integration_fail
    mov rax,[rax+PixBuf_data]
    cmp dword [rax],0xff332255
    je .vp8l_integration_done
.vp8l_integration_fail:
    inc ebx
.vp8l_integration_done:
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_empty_bits]
    mov edx,1
    call webp_bits_init
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_huff_group]
    lea rdx,[rel webp_decoded_pixels]
    mov ecx,2
    lea r8,[rel webp_color_cache]
    mov r9d,2
    call webp_huff_group_decode_literals
    cmp eax,2
    jne .literal_fail
    cmp dword [rel webp_decoded_pixels],0xff112233
    jne .literal_fail
    cmp dword [rel webp_decoded_pixels+4],0xff112233
    je .literal_done
.literal_fail:
    inc ebx
.literal_done:
    mov edi,10
    mov esi,1
    call webp_distance_value
    cmp eax,10
    jne .distance_fail
    mov edi,10
    mov esi,2
    call webp_distance_value
    cmp eax,1
    jne .distance_fail
    mov edi,10
    mov esi,120
    call webp_distance_value
    cmp eax,78
    jne .distance_fail
    mov edi,10
    mov esi,121
    call webp_distance_value
    cmp eax,1
    je .distance_done
.distance_fail:
    inc ebx
.distance_done:
    lea rdi,[rel webp_huff_scratch]
    xor eax,eax
    mov ecx,281
    rep stosb
    mov byte [rel webp_huff_scratch+34],1
    mov byte [rel webp_huff_scratch+256],1
    lea rdi,[rel webp_huff_group+WEBP_GROUP_GREEN]
    lea rsi,[rel webp_huff_scratch]
    mov edx,280
    call webp_huff_build
    test eax,eax
    jnz .copy_fail
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_copy_bits]
    mov edx,1
    call webp_bits_init
    lea rdi,[rel webp_vp8l_state]
    lea rax,[rel webp_decoded_pixels]
    mov [rdi+WebPVP8LState.pixels],rax
    mov qword [rdi+WebPVP8LState.capacity],2
    mov qword [rdi+WebPVP8LState.produced],0
    mov qword [rdi+WebPVP8LState.cache],0
    mov dword [rdi+WebPVP8LState.width],1
    mov dword [rdi+WebPVP8LState.cache_bits],0
    mov rdx,rdi
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_huff_group]
    call webp_huff_group_decode
    cmp eax,2
    jne .copy_fail
    cmp dword [rel webp_decoded_pixels],0xff112233
    jne .copy_fail
    cmp dword [rel webp_decoded_pixels+4],0xff112233
    jne .copy_fail
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_copy_bits]
    mov edx,1
    call webp_bits_init
    mov qword [rel webp_vp8l_state+WebPVP8LState.produced],0
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_huff_group]
    lea rdx,[rel webp_vp8l_state]
    call webp_huff_group_decode_one
    cmp eax,1
    jne .copy_fail
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_huff_group]
    lea rdx,[rel webp_vp8l_state]
    call webp_huff_group_decode_one
    cmp eax,2
    jne .copy_fail
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_copy_bits]
    mov edx,1
    call webp_bits_init
    mov qword [rel webp_vp8l_state+WebPVP8LState.produced],0
    mov dword [rel webp_entropy_pixel],0
    lea rdi,[rel webp_meta_state]
    lea rax,[rel webp_huff_group]
    mov [rdi+WebPMetaState.groups],rax
    lea rax,[rel webp_entropy_pixel]
    mov [rdi+WebPMetaState.entropy],rax
    lea rax,[rel webp_vp8l_state]
    mov [rdi+WebPMetaState.vp8l],rax
    mov dword [rdi+WebPMetaState.group_count],1
    mov dword [rdi+WebPMetaState.entropy_width],1
    mov dword [rdi+WebPMetaState.prefix_bits],2
    mov rsi,rdi
    lea rdi,[rel webp_reader]
    call webp_huff_groups_decode
    cmp eax,2
    je .copy_done
.copy_fail:
    inc ebx
.copy_done:
    mov dword [rel webp_transform_pixels],0xfffa0afb
    lea rdi,[rel webp_transform_pixels]
    mov esi,1
    call webp_inverse_subtract_green
    test eax,eax
    jnz .transform_fail
    cmp dword [rel webp_transform_pixels],0xff040a05
    jne .transform_fail
    mov dword [rel webp_transform_pixels],0xff140a05
    mov dword [rel webp_transform_data],0xff000020
    lea rdi,[rel webp_transform_pixels]
    mov esi,1
    mov edx,1
    lea rcx,[rel webp_transform_data]
    mov r8d,2
    mov r9d,1
    call webp_inverse_color
    test eax,eax
    jnz .transform_fail
    cmp dword [rel webp_transform_pixels],0xff1e0a05
    je .transform_done
.transform_fail:
    inc ebx
.transform_done:
    mov dword [rel webp_index_palette],0x10203040
    mov dword [rel webp_index_palette+4],0xfff0e0d0
    lea rdi,[rel webp_index_palette]
    mov esi,2
    call webp_palette_expand
    test eax,eax
    jnz .index_fail
    cmp dword [rel webp_index_palette+4],0x0f101010
    jne .index_fail
    mov dword [rel webp_index_packed],0xff000500
    mov dword [rel webp_index_palette],0xff000000
    mov dword [rel webp_index_palette+4],0xffffffff
    lea rdi,[rel webp_index_state]
    lea rax,[rel webp_index_packed]
    mov [rdi+WebPIndexState.packed],rax
    lea rax,[rel webp_index_output]
    mov [rdi+WebPIndexState.output],rax
    lea rax,[rel webp_index_palette]
    mov [rdi+WebPIndexState.palette],rax
    mov dword [rdi+WebPIndexState.width],3
    mov dword [rdi+WebPIndexState.height],1
    mov dword [rdi+WebPIndexState.packed_width],1
    mov dword [rdi+WebPIndexState.palette_count],2
    mov dword [rdi+WebPIndexState.width_bits],3
    call webp_inverse_color_index
    test eax,eax
    jnz .index_fail
    cmp dword [rel webp_index_output],0xffffffff
    jne .index_fail
    cmp dword [rel webp_index_output+4],0xff000000
    jne .index_fail
    cmp dword [rel webp_index_output+8],0xffffffff
    je .index_done
.index_fail:
    inc ebx
.index_done:
    xor edi,edi
    xor esi,esi
    xor edx,edx
    xor ecx,ecx
    xor r8d,r8d
    call webp_predict_basic
    cmp eax,0xff000000
    jne .predict_fail
    mov edi,7
    mov esi,0x10203040
    mov edx,0x50607080
    xor ecx,ecx
    xor r8d,r8d
    call webp_predict_basic
    cmp eax,0x30405060
    jne .predict_fail
    mov edi,10
    mov esi,0x10203040
    mov edx,0x50607080
    mov ecx,0x90a0b0c0
    mov r8d,0xd0e0f000
    call webp_predict_basic
    cmp eax,0x70809060
    jne .predict_fail
    mov edi,12
    mov esi,0xf0a02010
    mov edx,0x80406090
    mov ecx,0x20f01030
    xor r8d,r8d
    call webp_predict_basic
    cmp eax,0xff007070
    jne .predict_fail
    mov edi,13
    mov esi,0x10203040
    mov edx,0x50607080
    mov ecx,0x30405060
    xor r8d,r8d
    call webp_predict_basic
    cmp eax,0x30405060
    jne .predict_fail
    mov dword [rel webp_predict_pixels],0x01010101
    mov dword [rel webp_predict_pixels+4],0x01010101
    mov dword [rel webp_predict_pixels+8],0x01010101
    mov dword [rel webp_predict_pixels+12],0x01010101
    mov dword [rel webp_predict_modes],0x00000100
    lea rdi,[rel webp_predict_state]
    lea rax,[rel webp_predict_pixels]
    mov [rdi+WebPPredictState.pixels],rax
    lea rax,[rel webp_predict_modes]
    mov [rdi+WebPPredictState.modes],rax
    mov dword [rdi+WebPPredictState.width],2
    mov dword [rdi+WebPPredictState.height],2
    mov dword [rdi+WebPPredictState.size_bits],2
    mov dword [rdi+WebPPredictState.mode_count],1
    call webp_inverse_predictor
    test eax,eax
    jnz .predict_fail
    cmp dword [rel webp_predict_pixels],0x00010101
    jne .predict_fail
    cmp dword [rel webp_predict_pixels+4],0x01020202
    jne .predict_fail
    cmp dword [rel webp_predict_pixels+8],0x01020202
    jne .predict_fail
    cmp dword [rel webp_predict_pixels+12],0x02030303
    jne .predict_fail
    jmp .predict_done
.predict_fail:
    inc ebx
.predict_done:
    lea rdi,[rel webp_reader]
    lea rsi,[rel webp_prefix_bits]
    mov edx,1
    call webp_bits_init
    lea rdi,[rel webp_reader]
    mov esi,4
    call webp_prefix_value
    cmp eax,6
    jne .primitive_fail
    lea rdi,[rel webp_pixels]
    mov dword [rdi],0x11223344
    mov dword [rdi+4],0x55667788
    mov esi,2
    mov edx,6
    mov ecx,2
    mov r8d,4
    call webp_copy_pixels
    cmp eax,6
    jne .primitive_fail
    cmp dword [rel webp_pixels+8],0x11223344
    jne .primitive_fail
    cmp dword [rel webp_pixels+12],0x55667788
    jne .primitive_fail
    cmp dword [rel webp_pixels+16],0x11223344
    jne .primitive_fail
    cmp dword [rel webp_pixels+20],0x55667788
    jne .primitive_fail
    mov edi,0x11223344
    mov esi,8
    call webp_color_cache_index
    cmp eax,256
    jae .primitive_fail
    jmp .primitive_done
.primitive_fail:
    inc ebx
.primitive_done:
    lea rdi,[rel webp_vp8l]
    mov esi,webp_vp8l_end-webp_vp8l
    lea rdx,[rel webp_info]
    call webp_inspect
    test eax,eax
    jnz .lossless_fail
    cmp dword [rel webp_info+WebPInfo.width],2
    jne .lossless_fail
    cmp dword [rel webp_info+WebPInfo.height],3
    jne .lossless_fail
    cmp dword [rel webp_info+WebPInfo.codec],WEBP_CODEC_VP8L
    jne .lossless_fail
    test dword [rel webp_info+WebPInfo.flags],WEBP_FLAG_ALPHA
    jnz .lossless_done
.lossless_fail:
    inc ebx
.lossless_done:
    lea rdi,[rel webp_vp8]
    mov esi,webp_vp8_end-webp_vp8
    lea rdx,[rel webp_info]
    call webp_inspect
    test eax,eax
    jnz .lossy_fail
    cmp dword [rel webp_info+WebPInfo.width],4
    jne .lossy_fail
    cmp dword [rel webp_info+WebPInfo.height],5
    jne .lossy_fail
    cmp dword [rel webp_info+WebPInfo.codec],WEBP_CODEC_VP8
    je .lossy_done
.lossy_fail:
    inc ebx
.lossy_done:
    lea rdi,[rel webp_extended]
    mov esi,webp_extended_end-webp_extended
    lea rdx,[rel webp_info]
    call webp_inspect
    test eax,eax
    jnz .extended_fail
    cmp dword [rel webp_info+WebPInfo.width],10
    jne .extended_fail
    cmp dword [rel webp_info+WebPInfo.height],8
    jne .extended_fail
    test dword [rel webp_info+WebPInfo.flags],WEBP_FLAG_ALPHA
    jnz .extended_done
.extended_fail:
    inc ebx
.extended_done:
    lea rdi,[rel webp_vp8l]
    mov esi,11
    call webp_probe
    test eax,eax
    jz .truncated_done
    inc ebx
.truncated_done:
    lea rdi,[rel webp_bad_padding]
    mov esi,webp_bad_padding_end-webp_bad_padding
    lea rdx,[rel webp_info]
    call webp_inspect
    cmp eax,-EINVAL
    je .padding_done
    inc ebx
.padding_done:
    lea rdi,[rel webp_bad_reserved]
    mov esi,webp_bad_reserved_end-webp_bad_reserved
    lea rdx,[rel webp_info]
    call webp_inspect
    cmp eax,-EINVAL
    je .reserved_done
    inc ebx
.reserved_done:
    mov eax,ebx
    EPILOGUE_RESTORE rbx
    ret

section .rodata
webp_bits: db 0xad,0xaa
webp_bool_zeros: db 0,0,0,0
webp_bool_zeros_end:
webp_vp8_idct_expected:
    dw -3,-1,-1,0, -8,2,-2,0, 0,0,0,0, -2,0,0,0
webp_vp8_wht_expected:
    dw -1,-2,0,-1, -8,0,0,0, 0,0,0,0, -4,0,0,0
webp_huff_bits: db 0x1a
webp_huff_lengths: db 1,2,2
webp_huff_bad_lengths: db 1,1,1
webp_simple_bits: db 0x23,0x20
webp_normal_bits: db 0x00,0x48,0x8c
webp_group_bits: db 0x15,0x69,0x44,0x67,0xfa,0x1f
webp_group_bits_end:
; No color cache, no meta image, then webp_group_bits shifted by two bits.
webp_image_bits: db 0x54,0xa4,0x11,0x9d,0xe9,0x7f,0
webp_image_bits_end:
webp_vp8l_plain:
    db 0x2f
    dd 0
    db 0xa8,0x48,0x23,0x3a,0xd3,0xff,0
webp_vp8l_plain_end:
webp_vp8l_green:
    db 0x2f
    dd 0
    db 0x45,0x45,0x1a,0xd1,0x99,0xfe,0x07
webp_vp8l_green_end:
webp_prefix_bits: db 1
webp_empty_bits: db 0
webp_copy_bits: db 2

section .bss
align 8
webp_predict_state: resb WebPPredictState_size
webp_predict_pixels: resd 4
webp_predict_modes: resd 1

section .rodata
webp_vp8l:
    db 'R','I','F','F'
    dd 18
    db 'W','E','B','P','V','P','8','L'
    dd 5
    db 0x2f,0x01,0x80,0x00,0x10,0
webp_vp8l_end:
webp_vp8:
    db 'R','I','F','F'
    dd 22
    db 'W','E','B','P','V','P','8',' '
    dd 10
    db 0,0,0, 0x9d,0x01,0x2a, 4,0, 5,0
webp_vp8_end:
webp_extended:
    db 'R','I','F','F'
    dd 40
    db 'W','E','B','P','V','P','8','X'
    dd 10
    db WEBP_FLAG_ALPHA,0,0,0, 9,0,0, 7,0,0
    db 'V','P','8',' '
    dd 10
    db 0,0,0, 0x9d,0x01,0x2a, 4,0, 5,0
webp_extended_end:
webp_bad_padding:
    db 'R','I','F','F'
    dd 17
    db 'W','E','B','P','V','P','8','L'
    dd 5
    db 0x2f,0x01,0x80,0x00,0x10
webp_bad_padding_end:
webp_bad_reserved:
    db 'R','I','F','F'
    dd 22
    db 'W','E','B','P','V','P','8','X'
    dd 10
    db 0x80,0,0,0, 0,0,0, 0,0,0
webp_bad_reserved_end:

section .bss
alignb 8
webp_info: resb WebPInfo_size
webp_reader: resb WebPBitReader_size
webp_bool_reader: resb WebPBoolReader_size
webp_vp8_info: resb WebPVP8Info_size
webp_vp8_coeffs: resw 16
webp_vp8_residual: resw 16
webp_vp8_predict: resb 16
webp_vp8_block: resb 16
webp_vp8_y: resb 4
webp_vp8_u: resb 1
webp_vp8_v: resb 1
webp_vp8_bgra: resd 4
webp_yuv_state: resb WebPYUVState_size
alignb 16
webp_huff_table: resb WEBP_HUFF_TABLE_SIZE
webp_huff_temp: resb WEBP_HUFF_TABLE_SIZE
webp_huff_scratch: resb WEBP_HUFF_MAX_SYMBOLS+19
alignb 16
webp_huff_group: resb WEBP_HUFF_GROUP_SIZE
webp_pixels: resd 6
webp_decoded_pixels: resd 2
webp_color_cache: resd 4
webp_vp8l_state: resb WebPVP8LState_size
webp_meta_state: resb WebPMetaState_size
webp_entropy_pixel: resd 1
webp_entropy_arena: resq 4
webp_entropy_arena_data: resb 65536
webp_entropy_output: resd 1
webp_transform_pixels: resd 1
webp_transform_data: resd 1
webp_index_packed: resd 1
webp_index_palette: resd 2
webp_index_output: resd 3
webp_index_state: resb WebPIndexState_size

section .data
global test_webp_version
test_webp_version: dq 0x010000
