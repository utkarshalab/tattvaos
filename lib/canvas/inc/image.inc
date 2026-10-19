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
endstruc
%define WebPInfo_size 32

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
