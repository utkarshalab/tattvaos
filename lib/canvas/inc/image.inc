; ============================================================================
; Image — Shared Image Decoder Definitions (sniff, formats)
; ============================================================================

%ifndef __IMAGE_INC__
%define __IMAGE_INC__

; Supported formats
%define IMAGE_FMT_UNKNOWN   0
%define IMAGE_FMT_PNG       1
%define IMAGE_FMT_JPEG      2
%define IMAGE_FMT_GIF       3
%define IMAGE_FMT_BMP       4
%define IMAGE_FMT_SVG       5
%define IMAGE_FMT_QOI       6
%define IMAGE_FMT_TGA       7
%define IMAGE_FMT_PNM       8
%define IMAGE_FMT_FARBFELD  9
%define IMAGE_FMT_DNG      10
%define IMAGE_FMT_PCX      11
%define IMAGE_FMT_ICO      12
%define IMAGE_FMT_TIFF     13
%define IMAGE_FMT_HDR      14
%define IMAGE_FMT_EXR      15
%define IMAGE_FMT_DDS      16
%define IMAGE_FMT_KTX      17
%define IMAGE_FMT_KTX2     18
%define IMAGE_FMT_PSD      19
%define IMAGE_FMT_WEBP     20
%define IMAGE_FMT_AVIF     21
%define IMAGE_FMT_HEIF     22
%define IMAGE_FMT_JXL      23
%define IMAGE_FMT_CR2      24
%define IMAGE_FMT_CR3      25
%define IMAGE_FMT_NEF      26
%define IMAGE_FMT_ARW      27
%define IMAGE_FMT_RAF      28
%define IMAGE_FMT_ORF      29
%define IMAGE_FMT_RW2      30

%define WEBP_CODEC_NONE 0
%define WEBP_CODEC_VP8  1
%define WEBP_CODEC_VP8L 2

%define WEBP_FLAG_ANIMATION 0x02
%define WEBP_FLAG_XMP       0x04
%define WEBP_FLAG_EXIF      0x08
%define WEBP_FLAG_ALPHA     0x10
%define WEBP_FLAG_ICC       0x20

struc WebPInfo
    .width:          resd 1
    .height:         resd 1
    .codec:          resd 1
    .flags:          resd 1
    .payload:        resq 1
    .payload_len:    resq 1
    .alpha:          resq 1
    .alpha_len:      resq 1
    .icc:            resq 1
    .icc_len:        resq 1
    .exif:           resq 1
    .exif_len:       resq 1
    .xmp:            resq 1
    .xmp_len:        resq 1
endstruc
%define WebPInfo_size 96

struc WebPAnimationInfo
    .width:          resd 1
    .height:         resd 1
    .frame_count:    resd 1
    .loop_count:     resd 1       ; 0 means infinite
    .duration_ms:    resq 1
    .background:     resd 1       ; BGRA, as stored by ANIM
    .reserved:       resd 1
endstruc
%define WebPAnimationInfo_size 32

struc WebPCompositeState
    .canvas:         resq 1       ; destination PixBuf
    .frame:          resq 1       ; source PixBuf
    .x:              resd 1
    .y:              resd 1
    .width:          resd 1
    .height:         resd 1
    .blend:          resd 1       ; 0=replace, nonzero=source-over
    .reserved:       resd 1
endstruc
%define WebPCompositeState_size 40

struc WebPAnimation
    .width:          resd 1
    .height:         resd 1
    .frame_count:    resd 1
    .loop_count:     resd 1
    .duration_ms:    resq 1
    .background:     resd 1
    .reserved:       resd 1
    .frames:         resq 1       ; PixBuf*[frame_count]
    .delays_ms:      resq 1       ; uint32[frame_count]
    .disposals:      resq 1       ; uint8[frame_count]
    .blends:         resq 1       ; uint8[frame_count], 1=source-over
    .arena:          resq 1
endstruc
%define WebPAnimation_size 72

struc WebPBitReader
    .cursor:         resq 1
    .end:            resq 1
    .bits:           resq 1
    .count:          resd 1
    .reserved:       resd 1
endstruc
%define WebPBitReader_size 32

%define WEBP_HUFF_MAX_SYMBOLS 2328
%define WEBP_HUFF_COUNTS       0
%define WEBP_HUFF_FIRST_CODE  64
%define WEBP_HUFF_FIRST_SYM  128
%define WEBP_HUFF_SYMBOLS    192
%define WEBP_HUFF_TABLE_SIZE 4848

%define WEBP_GROUP_GREEN     0
%define WEBP_GROUP_RED       (WEBP_HUFF_TABLE_SIZE*1)
%define WEBP_GROUP_BLUE      (WEBP_HUFF_TABLE_SIZE*2)
%define WEBP_GROUP_ALPHA     (WEBP_HUFF_TABLE_SIZE*3)
%define WEBP_GROUP_DISTANCE  (WEBP_HUFF_TABLE_SIZE*4)
%define WEBP_HUFF_GROUP_SIZE (WEBP_HUFF_TABLE_SIZE*5)

struc WebPVP8LState
    .pixels:         resq 1
    .capacity:       resq 1
    .produced:       resq 1
    .cache:          resq 1
    .width:          resd 1
    .cache_bits:     resd 1
endstruc
%define WebPVP8LState_size 40

struc WebPIndexState
    .packed:         resq 1
    .output:         resq 1
    .palette:        resq 1
    .width:          resd 1
    .height:         resd 1
    .packed_width:   resd 1
    .palette_count:  resd 1
    .width_bits:     resd 1
    .reserved:       resd 1
endstruc
%define WebPIndexState_size 48

struc WebPPredictState
    .pixels:         resq 1
    .modes:          resq 1
    .width:          resd 1
    .height:         resd 1
    .size_bits:      resd 1
    .mode_count:     resd 1
endstruc
%define WebPPredictState_size 32

struc WebPMetaState
    .groups:         resq 1
    .entropy:        resq 1
    .vp8l:           resq 1
    .group_count:    resd 1
    .entropy_width:  resd 1
    .prefix_bits:    resd 1
    .reserved:       resd 1
endstruc
%define WebPMetaState_size 40

struc WebPBoolReader
    .cursor:         resq 1
    .end:            resq 1
    .range:          resd 1
    .value:          resd 1
    .count:          resd 1
    .error:          resd 1
endstruc
%define WebPBoolReader_size 32

struc WebPVP8Info
    .width:          resd 1
    .height:         resd 1
    .version:        resd 1
    .show_frame:     resd 1
    .first:          resq 1
    .first_len:      resq 1
    .tokens:         resq 1
    .tokens_len:     resq 1
endstruc
%define WebPVP8Info_size 48

struc WebPYUVState
    .y:              resq 1
    .u:              resq 1
    .v:              resq 1
    .output:         resq 1
    .width:          resd 1
    .height:         resd 1
    .y_stride:       resd 1
    .uv_stride:      resd 1
    .output_stride:  resd 1
    .reserved:       resd 1
endstruc
%define WebPYUVState_size 56

struc WebPVP8Config
    .color_space:       resd 1
    .clamping:          resd 1
    .segmentation:      resd 1
    .segment_map_update:resd 1
    .segment_data_update:resd 1
    .segment_absolute:  resd 1
    .filter_type:       resd 1
    .filter_level:      resd 1
    .sharpness:         resd 1
    .lf_adjustments:    resd 1
    .lf_update:         resd 1
    .token_partitions:  resd 1
    .base_qindex:       resd 1
    .refresh_entropy:   resd 1
    .segment_quant:     resd 4
    .segment_filter:    resd 4
    .segment_probs:     resb 4
    .quant_deltas:      resd 5
    .ref_lf_deltas:     resd 4
    .mode_lf_deltas:    resd 4
endstruc
%define WebPVP8Config_size 144

struc WebPVP8Partitions
    .count:           resd 1
    .reserved:        resd 1
    .data:            resq 8
    .length:          resq 8
endstruc
%define WebPVP8Partitions_size 136

%define VP8_TOKEN_ZERO  0
%define VP8_TOKEN_ONE   1
%define VP8_TOKEN_TWO   2
%define VP8_TOKEN_THREE 3
%define VP8_TOKEN_FOUR  4
%define VP8_TOKEN_CAT1  5
%define VP8_TOKEN_CAT2  6
%define VP8_TOKEN_CAT3  7
%define VP8_TOKEN_CAT4  8
%define VP8_TOKEN_CAT5  9
%define VP8_TOKEN_CAT6  10
%define VP8_TOKEN_EOB   11
%define VP8_COEFF_PROBS_SIZE (4*8*3*11)
%define VP8_Y_MODE_B_PRED 4
%define VP8_BMODE_DC 0
%define VP8_BMODE_TM 1
%define VP8_BMODE_VE 2
%define VP8_BMODE_HE 3
%define VP8_BMODE_LD 4
%define VP8_BMODE_RD 5
%define VP8_BMODE_VR 6
%define VP8_BMODE_VL 7
%define VP8_BMODE_HD 8
%define VP8_BMODE_HU 9

struc WebPVP8ResidualState
    .reader:          resq 1
    .probs:           resq 1
    .coeffs:          resq 1
    .above:           resq 1
    .left:            resq 1
    .y_mode:          resd 1
    .reserved:        resd 1
endstruc
%define WebPVP8ResidualState_size 48

struc WebPVP8QuantFactors
    .y1_dc:           resw 1
    .y1_ac:           resw 1
    .uv_dc:           resw 1
    .uv_ac:           resw 1
    .y2_dc:           resw 1
    .y2_ac:           resw 1
endstruc
%define WebPVP8QuantFactors_size 12

struc WebPVP8Modes
    .y_mode:          resd 1
    .uv_mode:         resd 1
endstruc
%define WebPVP8Modes_size 8

struc WebPVP8MBHeader
    .segment_id:      resd 1
    .skip_coeff:      resd 1
    .y_mode:          resd 1
    .uv_mode:         resd 1
    .b_modes:         resb 16
endstruc
%define WebPVP8MBHeader_size 32

struc WebPVP8ReconstructState
    .y:               resq 1
    .u:               resq 1
    .v:               resq 1
    .coeffs:          resq 1
    .y_stride:        resd 1
    .uv_stride:       resd 1
endstruc
%define WebPVP8ReconstructState_size 40

; Macroblock prediction over padded Y/U/V planes. Each plane pointer addresses
; the macroblock origin and must expose one initialized row/column above/left.
struc WebPVP8PredictMBState
    .y:               resq 1
    .u:               resq 1
    .v:               resq 1
    .header:          resq 1
    .y_stride:        resd 1
    .uv_stride:       resd 1
endstruc
%define WebPVP8PredictMBState_size 40

struc WebPVP8FramePlanes
    .y:               resq 1
    .u:               resq 1
    .v:               resq 1
    .y_stride:        resd 1
    .uv_stride:       resd 1
    .coded_width:     resd 1
    .coded_height:    resd 1
endstruc
%define WebPVP8FramePlanes_size 40

struc WebPVP8RenderMBState
    .config:          resq 1
    .header:          resq 1
    .coeffs:          resq 1
    .y:               resq 1
    .u:               resq 1
    .v:               resq 1
    .y_stride:        resd 1
    .uv_stride:       resd 1
endstruc
%define WebPVP8RenderMBState_size 56

struc WebPVP8FilterFrameState
    .y:               resq 1
    .u:               resq 1
    .v:               resq 1
    .config:          resq 1
    .meta:            resq 1
    .y_stride:        resd 1
    .uv_stride:       resd 1
    .mb_cols:         resd 1
    .mb_rows:         resd 1
endstruc
%define WebPVP8FilterFrameState_size 56

; Headerless/raw raster formats. These use RawImageDesc and are never sniffed.
%define RAW_FMT_RGB24       1
%define RAW_FMT_BGR24       2
%define RAW_FMT_RGBA32      3
%define RAW_FMT_BGRA32      4
%define RAW_FMT_ARGB32      5
%define RAW_FMT_ABGR32      6
%define RAW_FMT_GRAY8       7
%define RAW_FMT_GRAY16LE    8
%define RAW_FMT_RGB565LE    9
%define RAW_FMT_NV12       10
%define RAW_FMT_I420       11
%define RAW_FMT_YUYV       12

struc RawImageDesc
    .width:          resd 1
    .height:         resd 1
    .stride0:        resd 1
    .format:         resd 1
    .plane1_offset:  resq 1
    .stride1:        resd 1
    .stride2:        resd 1
    .plane2_offset:  resq 1
endstruc
%define RawImageDesc_size 40

; Camera sensor mosaic formats and processing metadata.
%define SENSOR_CFA_RGGB 0
%define SENSOR_CFA_BGGR 1
%define SENSOR_CFA_GRBG 2
%define SENSOR_CFA_GBRG 3
%define SENSOR_PACK_UNPACKED 0
%define SENSOR_PACK_LSB_BITS 1
%define SENSOR_PACK_MSB_BITS 2
%define SENSOR_PACK_UNPACKED_BE 3

struc SensorImageDesc
    .width:          resd 1
    .height:         resd 1
    .stride:         resd 1
    .bit_depth:      resd 1
    .packing:        resd 1
    .cfa:            resd 1
    .black_level:    resd 1
    .white_level:    resd 1
    .wb_r:           resd 1
    .wb_g:           resd 1
    .wb_b:           resd 1
    .reserved:       resd 1
    .color_matrix:   resd 9       ; signed 16.16, camera RGB -> linear sRGB
    .data_offset:    resq 1
    .crop_x:         resd 1
    .crop_y:         resd 1
endstruc
%define SensorImageDesc_size 104

struc GifAnimationInfo
    .width:          resd 1
    .height:         resd 1
    .frame_count:    resd 1
    .loop_count:     resd 1       ; 0 means infinite
    .duration_cs:    resq 1
endstruc
%define GifAnimationInfo_size 24

struc GifAnimation
    .width:          resd 1
    .height:         resd 1
    .frame_count:    resd 1
    .loop_count:     resd 1
    .duration_cs:    resq 1
    .frames:         resq 1       ; PixBuf*[frame_count]
    .delays_cs:      resq 1       ; uint32[frame_count]
    .disposals:      resq 1       ; uint8[frame_count]
    .arena:          resq 1
endstruc
%define GifAnimation_size 56

; PixBuf field offsets (mirrors pixbuf.asm layout)
%define PixBuf_width     0
%define PixBuf_height    8
%define PixBuf_stride    16
%define PixBuf_format    24
%define PixBuf_data      32
%define PixBuf_size      40
%define PixBuf_refcount  48
%define PixBuf_arena     56

; DRM formats (subset, mirrors color.inc)
%ifndef DRM_FORMAT_BGRA8888
%define DRM_FORMAT_BGR8888      0x34325242
%define DRM_FORMAT_BGRA8888     0x41524742
%define DRM_FORMAT_RGB565       0x35364247
%define DRM_FORMAT_XRGB2101010  0x33305258
%endif

%endif ; __IMAGE_INC__
