; WebP RIFF and primary-bitstream metadata tests.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern webp_probe
extern webp_inspect
extern webp_inspect_animation
extern webp_composite_frame
extern webp_dispose_background
extern webp_decode_animation
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
extern webp_decode
extern webp_alpha_apply_raw
extern webp_vp8l_decode
extern webp_bool_init
extern webp_bool_get
extern webp_bool_literal
extern webp_vp8_inspect
extern webp_vp8_parse_config
extern webp_vp8_parse_partitions
extern webp_vp8_decode_token
extern webp_vp8_decode_block
extern webp_vp8_update_probs
extern webp_vp8_coeff_probs_init
extern webp_vp8_coeff_probs_update
extern webp_vp8_decode_macroblock_residual
extern webp_vp8_quant_factors
extern webp_vp8_dequant_block
extern webp_vp8_dequant_macroblock
extern webp_vp8_decode_keyframe_base_modes
extern webp_vp8_decode_bpred_modes
extern webp_vp8_decode_mb_header
extern webp_vp8_idct4x4
extern webp_vp8_iwht4x4
extern webp_vp8_add_block
extern webp_vp8_reconstruct_macroblock
extern webp_vp8_predict_macroblock
extern webp_vp8_alloc_frame_planes
extern webp_vp8_render_macroblock
extern webp_vp8_filter_sample
extern webp_vp8_predict_block
extern webp_vp8_predict4x4
extern webp_vp8_yuv420_to_bgra
extern webp_inverse_subtract_green
extern webp_inverse_color
extern webp_inverse_color_index
extern webp_palette_expand
extern webp_predict_basic
extern webp_inverse_predictor
extern modern_probe

section .text
global test_webp_suite
test_webp_suite:
    PROLOGUE_SAVE rbx
    xor ebx,ebx
    lea rdi,[rel modern_avif]
    mov esi,modern_avif_end-modern_avif
    call modern_probe
    cmp eax,IMAGE_FMT_AVIF
    jne .modern_fail
    lea rdi,[rel modern_heif]
    mov esi,modern_heif_end-modern_heif
    call modern_probe
    cmp eax,IMAGE_FMT_HEIF
    jne .modern_fail
    lea rdi,[rel modern_jxl]
    mov esi,modern_jxl_end-modern_jxl
    call modern_probe
    cmp eax,IMAGE_FMT_JXL
    je .modern_done
.modern_fail:
    inc ebx
.modern_done:
    lea rdi,[rel webp_animated]
    mov esi,webp_animated_end-webp_animated
    lea rdx,[rel webp_animation_info]
    call webp_inspect_animation
    test eax,eax
    jnz .animation_fail
    cmp dword [rel webp_animation_info+WebPAnimationInfo.width],2
    jne .animation_fail
    cmp dword [rel webp_animation_info+WebPAnimationInfo.height],2
    jne .animation_fail
    cmp dword [rel webp_animation_info+WebPAnimationInfo.frame_count],1
    jne .animation_fail
    cmp dword [rel webp_animation_info+WebPAnimationInfo.loop_count],3
    jne .animation_fail
    cmp qword [rel webp_animation_info+WebPAnimationInfo.duration_ms],25
    jne .animation_fail
    cmp dword [rel webp_animation_info+WebPAnimationInfo.background],0x11223344
    je .animation_done
.animation_fail:
    inc ebx
.animation_done:
    mov qword [rel webp_composite_canvas+PixBuf_width],1
    mov qword [rel webp_composite_canvas+PixBuf_height],1
    mov qword [rel webp_composite_canvas+PixBuf_stride],4
    mov qword [rel webp_composite_canvas+PixBuf_format],DRM_FORMAT_BGRA8888
    mov qword [rel webp_composite_source+PixBuf_width],1
    mov qword [rel webp_composite_source+PixBuf_height],1
    mov qword [rel webp_composite_source+PixBuf_stride],4
    mov qword [rel webp_composite_source+PixBuf_format],DRM_FORMAT_BGRA8888
    lea rax,[rel webp_composite_canvas_pixels]
    mov [rel webp_composite_canvas+PixBuf_data],rax
    lea rax,[rel webp_composite_frame_pixels]
    mov [rel webp_composite_source+PixBuf_data],rax
    mov dword [rel webp_composite_canvas_pixels],0xff0000ff
    mov dword [rel webp_composite_frame_pixels],0x80ff0000
    lea rdi,[rel webp_composite_state]
    lea rax,[rel webp_composite_canvas]
    mov [rdi+WebPCompositeState.canvas],rax
    lea rax,[rel webp_composite_source]
    mov [rdi+WebPCompositeState.frame],rax
    mov dword [rdi+WebPCompositeState.x],0
    mov dword [rdi+WebPCompositeState.y],0
    mov dword [rdi+WebPCompositeState.width],1
    mov dword [rdi+WebPCompositeState.height],1
    mov dword [rdi+WebPCompositeState.blend],1
    call webp_composite_frame
    test eax,eax
    jnz .composite_fail
    cmp dword [rel webp_composite_canvas_pixels],0xff80007f
    jne .composite_fail
    mov dword [rel webp_composite_frame_pixels],0x01020304
    lea rdi,[rel webp_composite_state]
    mov dword [rdi+WebPCompositeState.blend],0
    call webp_composite_frame
    test eax,eax
    jnz .composite_fail
    cmp dword [rel webp_composite_canvas_pixels],0x01020304
    jne .composite_fail
    mov dword [rdi+WebPCompositeState.x],1
    call webp_composite_frame
    cmp eax,-EINVAL
    jne .composite_fail
    mov dword [rdi+WebPCompositeState.x],0
    lea rdi,[rel webp_composite_canvas]
    xor esi,esi
    xor edx,edx
    mov ecx,1
    mov r8d,1
    mov r9d,0x44332211
    call webp_dispose_background
    test eax,eax
    jnz .composite_fail
    cmp dword [rel webp_composite_canvas_pixels],0x44332211
    je .composite_done
.composite_fail:
    inc ebx
.composite_done:
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
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_bool_config_zeros]
    mov edx,webp_bool_config_zeros_end-webp_bool_config_zeros
    call webp_bool_init
    test eax,eax
    jnz .config_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_config]
    call webp_vp8_parse_config
    test eax,eax
    jnz .config_fail
    cmp dword [rel webp_vp8_config+WebPVP8Config.token_partitions],1
    jne .config_fail
    cmp dword [rel webp_vp8_config+WebPVP8Config.base_qindex],0
    jne .config_fail
    cmp byte [rel webp_vp8_config+WebPVP8Config.segment_probs],255
    je .config_done
.config_fail:
    inc ebx
.config_done:
    lea rdi,[rel webp_vp8_partition_data]
    mov esi,webp_vp8_partition_data_end-webp_vp8_partition_data
    mov edx,4
    lea rcx,[rel webp_vp8_partitions]
    call webp_vp8_parse_partitions
    test eax,eax
    jnz .partition_fail
    cmp dword [rel webp_vp8_partitions+WebPVP8Partitions.count],4
    jne .partition_fail
    cmp qword [rel webp_vp8_partitions+WebPVP8Partitions.length],2
    jne .partition_fail
    cmp qword [rel webp_vp8_partitions+WebPVP8Partitions.length+8],1
    jne .partition_fail
    cmp qword [rel webp_vp8_partitions+WebPVP8Partitions.length+16],3
    jne .partition_fail
    cmp qword [rel webp_vp8_partitions+WebPVP8Partitions.length+24],4
    jne .partition_fail
    lea rax,[rel webp_vp8_partition_data+9]
    cmp [rel webp_vp8_partitions+WebPVP8Partitions.data],rax
    jne .partition_fail
    lea rdi,[rel webp_vp8_partition_data]
    mov esi,8
    mov edx,4
    lea rcx,[rel webp_vp8_partitions]
    call webp_vp8_parse_partitions
    cmp eax,-EINVAL
    jne .partition_fail
    lea rdi,[rel webp_vp8_partition_oversize]
    mov esi,webp_vp8_partition_oversize_end-webp_vp8_partition_oversize
    mov edx,2
    lea rcx,[rel webp_vp8_partitions]
    call webp_vp8_parse_partitions
    cmp eax,-EINVAL
    je .partition_done
.partition_fail:
    inc ebx
.partition_done:
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_token_eob_bits]
    mov edx,4
    call webp_bool_init
    test eax,eax
    jnz .token_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_token_probs]
    lea rdx,[rel webp_vp8_token_value]
    call webp_vp8_decode_token
    cmp eax,VP8_TOKEN_EOB
    jne .token_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_token_one_bits]
    mov edx,4
    call webp_bool_init
    test eax,eax
    jnz .token_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_token_probs]
    lea rdx,[rel webp_vp8_token_value]
    call webp_vp8_decode_token
    cmp eax,VP8_TOKEN_ONE
    jne .token_fail
    cmp dword [rel webp_vp8_token_value],1
    je .token_done
.token_fail:
    inc ebx
.token_done:
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_token_one_bits]
    mov edx,4
    call webp_bool_init
    test eax,eax
    jnz .block_token_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_block_probs]
    lea rdx,[rel webp_vp8_token_coeffs]
    xor ecx,ecx
    xor r8d,r8d
    call webp_vp8_decode_block
    cmp eax,1
    jne .block_token_fail
    cmp word [rel webp_vp8_token_coeffs],1
    je .block_token_done
.block_token_fail:
    inc ebx
.block_token_done:
    mov byte [rel webp_vp8_mutable_probs],10
    mov byte [rel webp_vp8_mutable_probs+1],20
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_token_eob_bits]
    mov edx,4
    call webp_bool_init
    test eax,eax
    jnz .prob_update_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_mutable_probs]
    lea rdx,[rel webp_vp8_no_update_probs]
    mov ecx,2
    call webp_vp8_update_probs
    test eax,eax
    jnz .prob_update_fail
    cmp byte [rel webp_vp8_mutable_probs],10
    jne .prob_update_fail
    cmp byte [rel webp_vp8_mutable_probs+1],20
    je .prob_update_done
.prob_update_fail:
    inc ebx
.prob_update_done:
    lea rdi,[rel webp_vp8_coeff_prob_state]
    call webp_vp8_coeff_probs_init
    test eax,eax
    jnz .coeff_prob_fail
    cmp byte [rel webp_vp8_coeff_prob_state],128
    jne .coeff_prob_fail
    cmp byte [rel webp_vp8_coeff_prob_state+33],253
    jne .coeff_prob_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_coeff_update_zeros]
    mov edx,webp_vp8_coeff_update_zeros_end-webp_vp8_coeff_update_zeros
    call webp_bool_init
    test eax,eax
    jnz .coeff_prob_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_coeff_prob_state]
    call webp_vp8_coeff_probs_update
    test eax,eax
    jnz .coeff_prob_fail
    cmp byte [rel webp_vp8_coeff_prob_state+33],253
    je .coeff_prob_done
.coeff_prob_fail:
    inc ebx
.coeff_prob_done:
    lea rdi,[rel webp_vp8_residual_above]
    xor eax,eax
    mov ecx,18
    rep stosb
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_residual_zeros]
    mov edx,webp_vp8_residual_zeros_end-webp_vp8_residual_zeros
    call webp_bool_init
    test eax,eax
    jnz .macroblock_fail
    lea rdi,[rel webp_vp8_residual_state]
    lea rax,[rel webp_bool_reader]
    mov [rdi+WebPVP8ResidualState.reader],rax
    lea rax,[rel webp_vp8_coeff_prob_state]
    mov [rdi+WebPVP8ResidualState.probs],rax
    lea rax,[rel webp_vp8_macroblock_coeffs]
    mov [rdi+WebPVP8ResidualState.coeffs],rax
    lea rax,[rel webp_vp8_residual_above]
    mov [rdi+WebPVP8ResidualState.above],rax
    lea rax,[rel webp_vp8_residual_left]
    mov [rdi+WebPVP8ResidualState.left],rax
    mov dword [rdi+WebPVP8ResidualState.y_mode],VP8_Y_MODE_B_PRED
    call webp_vp8_decode_macroblock_residual
    test eax,eax
    jnz .macroblock_fail
    cmp byte [rel webp_vp8_residual_above],0
    jne .macroblock_fail
    cmp word [rel webp_vp8_macroblock_coeffs],0
    jne .macroblock_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_residual_zeros]
    mov edx,webp_vp8_residual_zeros_end-webp_vp8_residual_zeros
    call webp_bool_init
    test eax,eax
    jnz .macroblock_fail
    mov dword [rel webp_vp8_residual_state+WebPVP8ResidualState.y_mode],0
    lea rdi,[rel webp_vp8_residual_state]
    call webp_vp8_decode_macroblock_residual
    test eax,eax
    jz .macroblock_done
.macroblock_fail:
    inc ebx
.macroblock_done:
    mov dword [rel webp_vp8_config+WebPVP8Config.base_qindex],0
    mov dword [rel webp_vp8_config+WebPVP8Config.segmentation],0
    lea rdi,[rel webp_vp8_config]
    xor esi,esi
    lea rdx,[rel webp_vp8_quant_factor_state]
    call webp_vp8_quant_factors
    test eax,eax
    jnz .quant_fail
    cmp word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y1_dc],4
    jne .quant_fail
    cmp word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y2_dc],8
    jne .quant_fail
    cmp word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y2_ac],8
    jne .quant_fail
    mov dword [rel webp_vp8_config+WebPVP8Config.base_qindex],127
    lea rdi,[rel webp_vp8_config]
    xor esi,esi
    lea rdx,[rel webp_vp8_quant_factor_state]
    call webp_vp8_quant_factors
    test eax,eax
    jnz .quant_fail
    cmp word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y1_ac],284
    jne .quant_fail
    cmp word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.uv_dc],132
    jne .quant_fail
    cmp word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y2_ac],440
    jne .quant_fail
    mov word [rel webp_vp8_quant_input],2
    mov word [rel webp_vp8_quant_input+2],-3
    lea rdi,[rel webp_vp8_quant_input]
    lea rsi,[rel webp_vp8_quant_output]
    mov edx,4
    mov ecx,5
    call webp_vp8_dequant_block
    test eax,eax
    jnz .quant_fail
    cmp word [rel webp_vp8_quant_output],8
    jne .quant_fail
    cmp word [rel webp_vp8_quant_output+2],-15
    jne .quant_fail
    lea rdi,[rel webp_vp8_macroblock_coeffs]
    xor eax,eax
    mov ecx,100
    rep stosq
    mov word [rel webp_vp8_macroblock_coeffs],1
    mov word [rel webp_vp8_macroblock_coeffs+2],2
    mov word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y1_dc],4
    mov word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y1_ac],5
    lea rdi,[rel webp_vp8_macroblock_coeffs]
    lea rsi,[rel webp_vp8_quant_factor_state]
    mov edx,VP8_Y_MODE_B_PRED
    call webp_vp8_dequant_macroblock
    test eax,eax
    jnz .quant_fail
    cmp word [rel webp_vp8_macroblock_coeffs],4
    jne .quant_fail
    cmp word [rel webp_vp8_macroblock_coeffs+2],10
    jne .quant_fail
    lea rdi,[rel webp_vp8_macroblock_coeffs]
    xor eax,eax
    mov ecx,100
    rep stosq
    mov word [rel webp_vp8_macroblock_coeffs+24*32],1
    mov word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y1_ac],5
    mov word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y2_dc],8
    mov word [rel webp_vp8_quant_factor_state+WebPVP8QuantFactors.y2_ac],8
    lea rdi,[rel webp_vp8_macroblock_coeffs]
    lea rsi,[rel webp_vp8_quant_factor_state]
    xor edx,edx
    call webp_vp8_dequant_macroblock
    test eax,eax
    jnz .quant_fail
    cmp word [rel webp_vp8_macroblock_coeffs],1
    jne .quant_fail
    cmp word [rel webp_vp8_macroblock_coeffs+15*32],1
    je .quant_done
.quant_fail:
    inc ebx
.quant_done:
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_residual_zeros]
    mov edx,webp_vp8_residual_zeros_end-webp_vp8_residual_zeros
    call webp_bool_init
    test eax,eax
    jnz .base_mode_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_modes]
    call webp_vp8_decode_keyframe_base_modes
    test eax,eax
    jnz .base_mode_fail
    cmp dword [rel webp_vp8_modes+WebPVP8Modes.y_mode],VP8_Y_MODE_B_PRED
    jne .base_mode_fail
    cmp dword [rel webp_vp8_modes+WebPVP8Modes.uv_mode],0
    je .base_mode_done
.base_mode_fail:
    inc ebx
.base_mode_done:
    lea rdi,[rel webp_vp8_bpred_above]
    xor eax,eax
    mov ecx,24
    rep stosb
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_residual_zeros]
    mov edx,webp_vp8_residual_zeros_end-webp_vp8_residual_zeros
    call webp_bool_init
    test eax,eax
    jnz .bpred_mode_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_bpred_above]
    lea rdx,[rel webp_vp8_bpred_left]
    lea rcx,[rel webp_vp8_bpred_output]
    call webp_vp8_decode_bpred_modes
    test eax,eax
    jnz .bpred_mode_fail
    lea rdi,[rel webp_vp8_bpred_output]
    mov ecx,16
.bpred_mode_check:
    cmp byte [rdi],VP8_BMODE_DC
    jne .bpred_mode_fail
    inc rdi
    loop .bpred_mode_check
    jmp .bpred_mode_done
.bpred_mode_fail:
    inc ebx
.bpred_mode_done:
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_residual_zeros]
    mov edx,webp_vp8_residual_zeros_end-webp_vp8_residual_zeros
    call webp_bool_init
    test eax,eax
    jnz .mb_header_fail
    mov dword [rel webp_vp8_config+WebPVP8Config.segmentation],0
    lea rax,[rel webp_vp8_mb_header]
    push rax
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_config]
    xor edx,edx
    xor ecx,ecx
    lea r8,[rel webp_vp8_bpred_above]
    lea r9,[rel webp_vp8_bpred_left]
    call webp_vp8_decode_mb_header
    add rsp,8
    test eax,eax
    jnz .mb_header_fail
    cmp dword [rel webp_vp8_mb_header+WebPVP8MBHeader.y_mode],VP8_Y_MODE_B_PRED
    jne .mb_header_fail
    cmp byte [rel webp_vp8_mb_header+WebPVP8MBHeader.b_modes],VP8_BMODE_DC
    jne .mb_header_fail
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_residual_zeros]
    mov edx,webp_vp8_residual_zeros_end-webp_vp8_residual_zeros
    call webp_bool_init
    test eax,eax
    jnz .mb_header_fail
    mov dword [rel webp_vp8_config+WebPVP8Config.segmentation],1
    mov dword [rel webp_vp8_config+WebPVP8Config.segment_map_update],1
    lea rax,[rel webp_vp8_mb_header]
    push rax
    lea rdi,[rel webp_bool_reader]
    lea rsi,[rel webp_vp8_config]
    mov edx,1
    mov ecx,255
    lea r8,[rel webp_vp8_bpred_above]
    lea r9,[rel webp_vp8_bpred_left]
    call webp_vp8_decode_mb_header
    add rsp,8
    test eax,eax
    jnz .mb_header_fail
    cmp dword [rel webp_vp8_mb_header+WebPVP8MBHeader.segment_id],0
    jne .mb_header_fail
    cmp dword [rel webp_vp8_mb_header+WebPVP8MBHeader.skip_coeff],0
    je .mb_header_done
.mb_header_fail:
    inc ebx
.mb_header_done:
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_VE
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp dword [rel webp_vp8_predict4_output],0x32281e14
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_HE
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp byte [rel webp_vp8_predict4_output],20
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+4],30
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+8],40
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+12],48
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_LD
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp dword [rel webp_vp8_predict4_output],0x3c32281e
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+15],88
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_RD
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp byte [rel webp_vp8_predict4_output],15
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+15],15
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_VR
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp byte [rel webp_vp8_predict4_output],15
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+12],30
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_VL
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp byte [rel webp_vp8_predict4_output],25
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+15],80
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_HD
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp byte [rel webp_vp8_predict4_output],15
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+15],30
    jne .predict4_fail
    lea rdi,[rel webp_vp8_predict4_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict4_above]
    lea rcx,[rel webp_vp8_predict4_left]
    mov r8d,VP8_BMODE_HU
    call webp_vp8_predict4x4
    test eax,eax
    jnz .predict4_fail
    cmp byte [rel webp_vp8_predict4_output],25
    jne .predict4_fail
    cmp byte [rel webp_vp8_predict4_output+15],50
    je .predict4_done
.predict4_fail:
    inc ebx
.predict4_done:
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
    jne .recon_fail
    push qword 0
    lea rdi,[rel webp_vp8_predict_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict_above]
    lea rcx,[rel webp_vp8_predict_left]
    mov r8d,4
    xor r9d,r9d
    call webp_vp8_predict_block
    add rsp,8
    test eax,eax
    jnz .recon_fail
    cmp byte [rel webp_vp8_predict_output],45
    jne .recon_fail
    push qword 0
    lea rdi,[rel webp_vp8_predict_output]
    mov esi,4
    lea rdx,[rel webp_vp8_predict_clip]
    lea rcx,[rel webp_vp8_predict_clip]
    mov r8d,4
    mov r9d,3
    call webp_vp8_predict_block
    add rsp,8
    test eax,eax
    jnz .recon_fail
    cmp byte [rel webp_vp8_predict_output],255
    jne .recon_fail
    lea rdi,[rel webp_vp8_reconstruct_y]
    xor eax,eax
    mov ecx,32
    rep stosq
    lea rdi,[rel webp_vp8_reconstruct_u]
    mov ecx,8
    rep stosq
    lea rdi,[rel webp_vp8_reconstruct_v]
    mov al,10
    mov ecx,64
    rep stosb
    lea rdi,[rel webp_vp8_macroblock_coeffs]
    xor eax,eax
    mov ecx,100
    rep stosq
    mov word [rel webp_vp8_macroblock_coeffs],8
    mov word [rel webp_vp8_macroblock_coeffs+16*32],16
    mov word [rel webp_vp8_macroblock_coeffs+23*32],-8
    lea rdi,[rel webp_vp8_reconstruct_state]
    lea rax,[rel webp_vp8_reconstruct_y]
    mov [rdi+WebPVP8ReconstructState.y],rax
    lea rax,[rel webp_vp8_reconstruct_u]
    mov [rdi+WebPVP8ReconstructState.u],rax
    lea rax,[rel webp_vp8_reconstruct_v]
    mov [rdi+WebPVP8ReconstructState.v],rax
    lea rax,[rel webp_vp8_macroblock_coeffs]
    mov [rdi+WebPVP8ReconstructState.coeffs],rax
    mov dword [rdi+WebPVP8ReconstructState.y_stride],16
    mov dword [rdi+WebPVP8ReconstructState.uv_stride],8
    call webp_vp8_reconstruct_macroblock
    test eax,eax
    jnz .recon_fail
    cmp byte [rel webp_vp8_reconstruct_y],1
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_y+3+3*16],1
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_y+4],0
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_u],2
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_u+4],0
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_v],10
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_v+4+4*8],9
    jne .recon_fail
    cmp byte [rel webp_vp8_reconstruct_v+7+7*8],9
    jne .recon_fail
    lea rdi,[rel webp_vp8_predict_mb_y]
    xor eax,eax
    mov ecx,(24*18)/8
    rep stosq
    lea rdi,[rel webp_vp8_predict_mb_u]
    mov ecx,(12*10)/8
    rep stosq
    lea rdi,[rel webp_vp8_predict_mb_v]
    mov ecx,(12*10)/8
    rep stosq
    lea rdi,[rel webp_vp8_predict_mb_y+1]
    mov al,10
    mov ecx,16
    rep stosb
    lea rdi,[rel webp_vp8_predict_mb_u+1]
    mov al,30
    mov ecx,8
    rep stosb
    lea rdi,[rel webp_vp8_predict_mb_v+1]
    mov al,50
    mov ecx,8
    rep stosb
    mov byte [rel webp_vp8_predict_mb_y],10
    mov byte [rel webp_vp8_predict_mb_u],10
    mov byte [rel webp_vp8_predict_mb_v],20
    lea rdx,[rel webp_vp8_predict_mb_y]
    lea r8,[rel webp_vp8_predict_mb_u]
    lea r9,[rel webp_vp8_predict_mb_v]
    xor ecx,ecx
.predict_mb_edges:
    mov eax,ecx
    inc eax
    imul eax,24
    mov byte [rdx+rax],20
    cmp ecx,8
    jae .predict_mb_y_only
    mov eax,ecx
    inc eax
    imul eax,12
    mov byte [r8+rax],40
    mov byte [r9+rax],60
.predict_mb_y_only:
    inc ecx
    cmp ecx,16
    jb .predict_mb_edges
    mov dword [rel webp_vp8_mb_header+WebPVP8MBHeader.y_mode],0
    mov dword [rel webp_vp8_mb_header+WebPVP8MBHeader.uv_mode],3
    lea rdi,[rel webp_vp8_predict_mb_state]
    lea rax,[rel webp_vp8_predict_mb_y+25]
    mov [rdi+WebPVP8PredictMBState.y],rax
    lea rax,[rel webp_vp8_predict_mb_u+13]
    mov [rdi+WebPVP8PredictMBState.u],rax
    lea rax,[rel webp_vp8_predict_mb_v+13]
    mov [rdi+WebPVP8PredictMBState.v],rax
    lea rax,[rel webp_vp8_mb_header]
    mov [rdi+WebPVP8PredictMBState.header],rax
    mov dword [rdi+WebPVP8PredictMBState.y_stride],24
    mov dword [rdi+WebPVP8PredictMBState.uv_stride],12
    call webp_vp8_predict_macroblock
    test eax,eax
    jnz .recon_fail
    cmp byte [rel webp_vp8_predict_mb_y+25],15
    jne .recon_fail
    cmp byte [rel webp_vp8_predict_mb_y+25+15+15*24],15
    jne .recon_fail
    cmp byte [rel webp_vp8_predict_mb_u+13],60
    jne .recon_fail
    cmp byte [rel webp_vp8_predict_mb_v+13+7+7*12],90
    jne .recon_fail
    lea rax,[rel webp_vp8_plane_arena_data]
    mov [rel webp_vp8_plane_arena],rax
    mov [rel webp_vp8_plane_arena+8],rax
    add rax,4096
    mov [rel webp_vp8_plane_arena+16],rax
    mov qword [rel webp_vp8_plane_arena+24],0
    lea rdi,[rel webp_vp8_plane_arena]
    mov esi,17
    mov edx,17
    lea rcx,[rel webp_vp8_frame_planes]
    call webp_vp8_alloc_frame_planes
    test eax,eax
    jnz .recon_fail
    cmp dword [rel webp_vp8_frame_planes+WebPVP8FramePlanes.coded_width],32
    jne .recon_fail
    cmp dword [rel webp_vp8_frame_planes+WebPVP8FramePlanes.coded_height],32
    jne .recon_fail
    cmp dword [rel webp_vp8_frame_planes+WebPVP8FramePlanes.y_stride],41
    jne .recon_fail
    mov rax,[rel webp_vp8_frame_planes+WebPVP8FramePlanes.y]
    cmp byte [rax-1],129
    jne .recon_fail
    sub rax,41
    cmp byte [rax],127
    jne .recon_fail
    lea rdi,[rel webp_vp8_config]
    xor eax,eax
    mov ecx,WebPVP8Config_size/8
    rep stosq
    lea rdi,[rel webp_vp8_mb_header]
    mov ecx,WebPVP8MBHeader_size/8
    rep stosq
    lea rdi,[rel webp_vp8_macroblock_coeffs]
    mov ecx,100
    rep stosq
    lea rdi,[rel webp_vp8_render_mb_state]
    lea rax,[rel webp_vp8_config]
    mov [rdi+WebPVP8RenderMBState.config],rax
    lea rax,[rel webp_vp8_mb_header]
    mov [rdi+WebPVP8RenderMBState.header],rax
    lea rax,[rel webp_vp8_macroblock_coeffs]
    mov [rdi+WebPVP8RenderMBState.coeffs],rax
    mov rax,[rel webp_vp8_frame_planes+WebPVP8FramePlanes.y]
    mov [rdi+WebPVP8RenderMBState.y],rax
    mov rax,[rel webp_vp8_frame_planes+WebPVP8FramePlanes.u]
    mov [rdi+WebPVP8RenderMBState.u],rax
    mov rax,[rel webp_vp8_frame_planes+WebPVP8FramePlanes.v]
    mov [rdi+WebPVP8RenderMBState.v],rax
    mov dword [rdi+WebPVP8RenderMBState.y_stride],41
    mov dword [rdi+WebPVP8RenderMBState.uv_stride],25
    call webp_vp8_render_macroblock
    test eax,eax
    jnz .recon_fail
    mov rax,[rel webp_vp8_frame_planes+WebPVP8FramePlanes.y]
    cmp byte [rax],128
    jne .recon_fail
    cmp byte [rax+15+15*41],128
    jne .recon_fail
    mov dword [rel webp_vp8_filter_pixels],0x64646464
    mov dword [rel webp_vp8_filter_pixels+4],0x6e6e6e6e
    lea rdi,[rel webp_vp8_filter_pixels+4]
    mov esi,1
    mov edx,40
    mov ecx,20
    xor r8d,r8d
    xor r9d,r9d
    call webp_vp8_filter_sample
    cmp eax,1
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+3],102
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+4],107
    jne .recon_fail
    mov dword [rel webp_vp8_filter_pixels],0x64646464
    mov dword [rel webp_vp8_filter_pixels+4],0x6e6e6e6e
    lea rdi,[rel webp_vp8_filter_pixels+4]
    mov esi,1
    mov edx,40
    mov ecx,20
    xor r8d,r8d
    mov r9d,2
    call webp_vp8_filter_sample
    cmp eax,1
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+1],101
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+2],103
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+3],104
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+4],106
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+5],107
    jne .recon_fail
    cmp byte [rel webp_vp8_filter_pixels+6],109
    jne .recon_fail
    lea rdi,[rel webp_alpha_pixbuf]
    lea rax,[rel webp_alpha_pixels]
    mov [rdi+PixBuf_data],rax
    mov dword [rdi+PixBuf_width],2
    mov dword [rdi+PixBuf_height],2
    mov dword [rdi+PixBuf_stride],8
    lea rsi,[rel webp_alpha_raw]
    mov edx,webp_alpha_raw_end-webp_alpha_raw
    call webp_alpha_apply_raw
    test eax,eax
    jnz .recon_fail
    cmp byte [rel webp_alpha_pixels+3],10
    jne .recon_fail
    cmp byte [rel webp_alpha_pixels+7],20
    jne .recon_fail
    cmp byte [rel webp_alpha_pixels+11],40
    jne .recon_fail
    cmp byte [rel webp_alpha_pixels+15],50
    jne .recon_fail
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena],rax
    mov [rel webp_entropy_arena+8],rax
    add rax,65536
    mov [rel webp_entropy_arena+16],rax
    mov qword [rel webp_entropy_arena+24],0
    lea rdi,[rel webp_alpha_pixbuf]
    lea rax,[rel webp_alpha_compressed_pixels]
    mov [rdi+PixBuf_data],rax
    mov dword [rdi+PixBuf_width],17
    mov dword [rdi+PixBuf_height],17
    mov dword [rdi+PixBuf_stride],68
    lea rsi,[rel webp_alpha_compressed]
    mov edx,webp_alpha_compressed_end-webp_alpha_compressed
    lea rcx,[rel webp_entropy_arena]
    call webp_alpha_apply_raw
    test eax,eax
    jnz .recon_fail
    cmp byte [rel webp_alpha_compressed_pixels+3],0
    je .recon_fail
    movzx eax,byte [rel webp_alpha_compressed_pixels+3]
    cmp al,[rel webp_alpha_compressed_pixels+(17*17-1)*4+3]
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
    lea rdi,[rel webp_metadata]
    mov esi,webp_metadata_end-webp_metadata
    lea rdx,[rel webp_info]
    call webp_inspect
    test eax,eax
    jnz .metadata_fail
    cmp qword [rel webp_info+WebPInfo.icc_len],3
    jne .metadata_fail
    cmp qword [rel webp_info+WebPInfo.exif_len],2
    jne .metadata_fail
    cmp qword [rel webp_info+WebPInfo.xmp_len],3
    jne .metadata_fail
    mov rax,[rel webp_info+WebPInfo.icc]
    cmp dword [rax],0x00434349
    jne .metadata_fail
    mov rax,[rel webp_info+WebPInfo.exif]
    cmp word [rax],0x4945
    jne .metadata_fail
    mov rax,[rel webp_info+WebPInfo.xmp]
    cmp dword [rax],0x00504d58
    je .metadata_done
.metadata_fail:
    inc ebx
.metadata_done:
    lea rdi,[rel webp_missing_metadata]
    mov esi,webp_missing_metadata_end-webp_missing_metadata
    lea rdx,[rel webp_info]
    call webp_inspect
    cmp eax,-EINVAL
    jne .metadata_conformance_fail
    lea rdi,[rel webp_late_icc]
    mov esi,webp_late_icc_end-webp_late_icc
    lea rdx,[rel webp_info]
    call webp_inspect
    cmp eax,-EINVAL
    je .metadata_conformance_done
.metadata_conformance_fail:
    inc ebx
.metadata_conformance_done:
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
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena],rax
    mov [rel webp_entropy_arena+8],rax
    add rax,65536
    mov [rel webp_entropy_arena+16],rax
    mov qword [rel webp_entropy_arena+24],0
    lea rdi,[rel webp_entropy_arena]
    lea rsi,[rel webp_vp8_lossy_fixture]
    mov edx,webp_vp8_lossy_fixture_end-webp_vp8_lossy_fixture
    call webp_decode
    test rax,rax
    jz .lossy_decode_fail
    cmp dword [rax+PixBuf_width],2
    jne .lossy_decode_fail
    cmp dword [rax+PixBuf_height],2
    jne .lossy_decode_fail
    mov rax,[rax+PixBuf_data]
    cmp byte [rax+3],255
    jne .lossy_decode_fail
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena+8],rax
    lea rdi,[rel webp_entropy_arena]
    lea rsi,[rel webp_vp8_lossy_multimb]
    mov edx,webp_vp8_lossy_multimb_end-webp_vp8_lossy_multimb
    call webp_decode
    test rax,rax
    jz .lossy_decode_fail
    cmp dword [rax+PixBuf_width],17
    jne .lossy_decode_fail
    cmp dword [rax+PixBuf_height],17
    jne .lossy_decode_fail
    mov ecx,[rax+PixBuf_stride]
    imul ecx,16
    add ecx,16*4+3
    mov rax,[rax+PixBuf_data]
    cmp byte [rax+rcx],255
    je .lossy_decode_done
.lossy_decode_fail:
    inc ebx
.lossy_decode_done:
    lea rax,[rel webp_entropy_arena_data]
    mov [rel webp_entropy_arena],rax
    mov [rel webp_entropy_arena+8],rax
    add rax,65536
    mov [rel webp_entropy_arena+16],rax
    mov qword [rel webp_entropy_arena+24],0
    lea rdi,[rel webp_entropy_arena]
    lea rsi,[rel webp_animated_lossy]
    mov edx,webp_animated_lossy_end-webp_animated_lossy
    call webp_decode_animation
    test rax,rax
    jz .animation_decode_fail
    cmp dword [rax+WebPAnimation.frame_count],1
    jne .animation_decode_fail
    cmp qword [rax+WebPAnimation.duration_ms],40
    jne .animation_decode_fail
    mov rcx,[rax+WebPAnimation.delays_ms]
    cmp dword [rcx],40
    jne .animation_decode_fail
    mov rcx,[rax+WebPAnimation.frames]
    mov rcx,[rcx]
    cmp qword [rcx+PixBuf_width],2
    jne .animation_decode_fail
    cmp qword [rcx+PixBuf_height],2
    je .animation_decode_done
.animation_decode_fail:
    inc ebx
.animation_decode_done:
    mov eax,ebx
    EPILOGUE_RESTORE rbx
    ret

section .rodata
modern_avif: db 0,0,0,24,'f','t','y','p','m','i','f','1',0,0,0,0,'a','v','i','f'
modern_avif_end:
modern_heif: db 0,0,0,20,'f','t','y','p','h','e','i','c',0,0,0,0
modern_heif_end:
modern_jxl: db 0xff,0x0a
modern_jxl_end:
webp_bits: db 0xad,0xaa
webp_bool_zeros: db 0,0,0,0
webp_bool_zeros_end:
webp_bool_config_zeros: times 16 db 0
webp_bool_config_zeros_end:
webp_vp8_partition_data:
    db 2,0,0, 1,0,0, 3,0,0
    db 10,11, 20, 30,31,32, 40,41,42,43
webp_vp8_partition_data_end:
webp_vp8_partition_oversize:
    db 255,0,0, 1,2,3
webp_vp8_partition_oversize_end:
webp_vp8_predict_above: db 10,20,30,40
webp_vp8_predict_left: db 50,60,70,80
webp_vp8_predict_clip: db 250,250,250,250
webp_vp8_token_probs: times 11 db 128
webp_vp8_block_probs: times 264 db 128
webp_vp8_token_eob_bits: db 0,0,0,0
webp_vp8_token_one_bits: db 0xc0,0,0,0
webp_vp8_no_update_probs: db 255,255
webp_vp8_coeff_update_zeros: times 256 db 0
webp_vp8_coeff_update_zeros_end:
webp_vp8_predict4_corner: db 10
webp_vp8_predict4_above: db 20,30,40,50,60,70,80,90
webp_vp8_predict4_left: db 20,30,40,50
webp_vp8_residual_zeros: times 128 db 0
webp_vp8_residual_zeros_end:
webp_vp8_idct_expected:
    dw -3,-1,-1,0, -8,2,-2,0, 0,0,0,0, -2,0,0,0
webp_vp8_wht_expected:
    dw -1,-2,0,-1, -8,0,0,0, 0,0,0,0, -4,0,0,0
webp_vp8_lossy_fixture:
    db 0x52,0x49,0x46,0x46,0x36,0,0,0,0x57,0x45,0x42,0x50
    db 0x56,0x50,0x38,0x20,0x2a,0,0,0,0xd0,0x01,0,0x9d,0x01,0x2a
    db 0x02,0,0x02,0,0x02,0,0x34,0x25,0xa0,0x02,0x74,0xba,0x01,0xf8
    db 0,0x03,0xb0,0,0xfe,0xdf,0x80,0x3f,0xf1,0xbb,0x71,0x86,0xfc,0x17
    db 0x7f,0xe1,0x57,0xc6,0xe4,0x2c,0x28,0
webp_vp8_lossy_fixture_end:
webp_vp8_lossy_multimb:
    db 0x52,0x49,0x46,0x46,0x50,0,0,0,0x57,0x45,0x42,0x50
    db 0x56,0x50,0x38,0x20,0x44,0,0,0,0x50,0x03,0,0x9d,0x01,0x2a
    db 0x11,0,0x11,0,0x3e,0x9d,0x3e,0x99,0x48,0x25,0xa3,0x22,0x21,0x30
    db 0x08,0,0xb0,0x13,0x89,0x65,0,0xca,0,0x21,0xd6,0x9c,0x0e,0xf5
    db 0x40,0,0xfe,0xf2,0xda,0x94,0xa3,0x17,0x61,0x48,0x71,0x76,0x42
    db 0x2a,0x54,0xa7,0xb8,0x3b,0x79,0x2a,0x5e,0x3e,0x8b,0x9f,0x37
    db 0x8c,0x59,0xaa,0xb8,0x08,0x0c,0,0,0
webp_vp8_lossy_multimb_end:
webp_animated:
    db 'RIFF'
    dd webp_animated_end-webp_animated-8
    db 'WEBP'
    db 'VP8X',10,0,0,0,2,0,0,0,1,0,0,1,0,0
    db 'ANIM',6,0,0,0,0x44,0x33,0x22,0x11,3,0
    db 'ANMF',30,0,0,0
    db 0,0,0, 0,0,0, 1,0,0, 1,0,0, 25,0,0, 0
    db 'VP8L',5,0,0,0,0x2f,1,0,0,0,0
webp_animated_end:
webp_animated_lossy:
    db 'RIFF'
    dd webp_animated_lossy_end-webp_animated_lossy-8
    db 'WEBP'
    db 'VP8X',10,0,0,0,2,0,0,0,1,0,0,1,0,0
    db 'ANIM',6,0,0,0,0,0,0,0,0,0
    db 'ANMF',66,0,0,0
    db 0,0,0, 0,0,0, 1,0,0, 1,0,0, 40,0,0, 0
    db 'VP8 ',42,0,0,0
    db 0xd0,0x01,0,0x9d,0x01,0x2a,0x02,0,0x02,0,0x02,0,0x34,0x25
    db 0xa0,0x02,0x74,0xba,0x01,0xf8,0,0x03,0xb0,0,0xfe,0xdf,0x80,0x3f
    db 0xf1,0xbb,0x71,0x86,0xfc,0x17,0x7f,0xe1,0x57,0xc6,0xe4,0x2c,0x28,0
webp_animated_lossy_end:
webp_alpha_raw: db 4,10,10,30,10
webp_alpha_raw_end:
webp_alpha_compressed:
    db 0x01,0x07,0xd0,0xbf,0x88,0x08,0x44,0x44,0xff,0x03
webp_alpha_compressed_end:
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
webp_vp8_partitions: resb WebPVP8Partitions_size

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
    dd 50
    db 'W','E','B','P','V','P','8','X'
    dd 10
    db WEBP_FLAG_ALPHA,0,0,0, 9,0,0, 7,0,0
    db 'A','L','P','H'
    dd 1
    db 0,0
    db 'V','P','8',' '
    dd 10
    db 0,0,0, 0x9d,0x01,0x2a, 4,0, 5,0
webp_extended_end:
webp_metadata:
    db 'RIFF'
    dd webp_metadata_end-webp_metadata-8
    db 'WEBP'
    db 'VP8X',10,0,0,0,WEBP_FLAG_ICC|WEBP_FLAG_EXIF|WEBP_FLAG_XMP,0,0,0,3,0,0,4,0,0
    db 'ICCP',3,0,0,0,'I','C','C',0
    db 'VP8 ',10,0,0,0,0,0,0,0x9d,0x01,0x2a,4,0,5,0
    db 'EXIF',2,0,0,0,'E','I'
    db 'XMP ',3,0,0,0,'X','M','P',0
webp_metadata_end:
webp_missing_metadata:
    db 'RIFF'
    dd webp_missing_metadata_end-webp_missing_metadata-8
    db 'WEBP'
    db 'VP8X',10,0,0,0,WEBP_FLAG_EXIF,0,0,0,3,0,0,4,0,0
    db 'VP8 ',10,0,0,0,0,0,0,0x9d,0x01,0x2a,4,0,5,0
webp_missing_metadata_end:
webp_late_icc:
    db 'RIFF'
    dd webp_late_icc_end-webp_late_icc-8
    db 'WEBP'
    db 'VP8X',10,0,0,0,WEBP_FLAG_ICC,0,0,0,3,0,0,4,0,0
    db 'VP8 ',10,0,0,0,0,0,0,0x9d,0x01,0x2a,4,0,5,0
    db 'ICCP',1,0,0,0,0,0
webp_late_icc_end:
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
webp_animation_info: resb WebPAnimationInfo_size
align 8
webp_composite_canvas: resb PixBuf_size
webp_composite_source: resb PixBuf_size
webp_composite_state: resb WebPCompositeState_size
webp_composite_canvas_pixels: resd 1
webp_composite_frame_pixels: resd 1
webp_reader: resb WebPBitReader_size
webp_bool_reader: resb WebPBoolReader_size
webp_vp8_info: resb WebPVP8Info_size
webp_vp8_config: resb WebPVP8Config_size
webp_vp8_coeffs: resw 16
webp_vp8_residual: resw 16
webp_vp8_predict: resb 16
webp_vp8_block: resb 16
webp_vp8_y: resb 4
webp_vp8_u: resb 1
webp_vp8_v: resb 1
webp_vp8_bgra: resd 4
webp_yuv_state: resb WebPYUVState_size
webp_vp8_predict_output: resb 256
webp_vp8_token_value: resd 1
webp_vp8_token_coeffs: resw 16
webp_vp8_mutable_probs: resb 2
webp_vp8_coeff_prob_state: resb VP8_COEFF_PROBS_SIZE
webp_vp8_residual_state: resb WebPVP8ResidualState_size
webp_vp8_residual_above: resb 9
webp_vp8_residual_left: resb 9
webp_vp8_macroblock_coeffs: resw 25*16
webp_vp8_quant_factor_state: resb WebPVP8QuantFactors_size
webp_vp8_quant_input: resw 16
webp_vp8_quant_output: resw 16
webp_vp8_modes: resb WebPVP8Modes_size
webp_vp8_bpred_above: resb 4
webp_vp8_bpred_left: resb 4
webp_vp8_bpred_output: resb 16
webp_vp8_mb_header: resb WebPVP8MBHeader_size
webp_vp8_predict4_output: resb 16
webp_vp8_reconstruct_state: resb WebPVP8ReconstructState_size
webp_vp8_reconstruct_y: resb 256
webp_vp8_reconstruct_u: resb 64
webp_vp8_reconstruct_v: resb 64
webp_vp8_predict_mb_state: resb WebPVP8PredictMBState_size
webp_vp8_predict_mb_y: resb 24*18
webp_vp8_predict_mb_u: resb 12*10
webp_vp8_predict_mb_v: resb 12*10
webp_vp8_frame_planes: resb WebPVP8FramePlanes_size
webp_vp8_render_mb_state: resb WebPVP8RenderMBState_size
webp_vp8_plane_arena: resq 4
webp_vp8_plane_arena_data: resb 4096
webp_vp8_filter_pixels: resb 8
webp_alpha_pixbuf: resb PixBuf_size
webp_alpha_pixels: resb 16
webp_alpha_compressed_pixels: resb 17*17*4
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
