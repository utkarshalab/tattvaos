; ============================================================================
; PNG Image Decoding — PNG Specification Compliant
; ============================================================================

%ifndef __PNG_INC__
%define __PNG_INC__

; PNG chunk types
%define PNG_IHDR      0x49484452  ; Image Header
%define PNG_PLTE      0x504C5445  ; Palette
%define PNG_IDAT      0x49444154  ; Image Data
%define PNG_IEND      0x49454E44  ; Image End
%define PNG_tRNS      0x74524E53  ; Transparency
%define PNG_gAMA      0x67414D41  ; Gamma
%define PNG_cHRM      0x6348524D  ; Chromaticity
%define PNG_sRGB      0x73524742  ; sRGB
%define PNG_iCCP      0x69434350  ; ICC Profile
%define PNG_tEXt      0x74455874  ; Textual Data
%define PNG_zTXt      0x7A545874  ; Compressed Text
%define PNG_iTXt      0x69545874  ; International Text
%define PNG_bKGD      0x624B4744  ; Background
%define PNG_pHYs      0x70485973  ; Physical Pixel Dimensions
%define PNG_sBIT      0x73424954  ; Significant Bits

; Color types
%define PNG_COLOR_GRAY       0
%define PNG_COLOR_RGB        2
%define PNG_COLOR_PALETTE    3
%define PNG_COLOR_GRAY_ALPHA 4
%define PNG_COLOR_RGBA       6

; Interlace methods
%define PNG_INTERLACE_NONE   0
%define PNG_INTERLACE_ADAM7  1

; Filter types
%define PNG_FILTER_NONE      0
%define PNG_FILTER_SUB       1
%define PNG_FILTER_UP        2
%define PNG_FILTER_AVERAGE   3
%define PNG_FILTER_PAETH     4

; PNG struct
%define PNG_WIDTH       0
%define PNG_HEIGHT      4
%define PNG_BIT_DEPTH   8
%define PNG_COLOR_TYPE  9
%define PNG_COMPRESSION 10
%define PNG_FILTER      11
%define PNG_INTERLACE   12
%define PNG_PALETTE     16
%define PNG_PALETTE_SZ  24
%define PNG_TRNS        32
%define PNG_TRNS_SZ     40
%define PNG_GAMMA       48
%define PNG_CHROMA      56
%define PNG_SRGB        64
%define PNG_ICCP        72
%define PNG_ICCP_SZ     80
%define PNG_BKGD        88
%define PNG_PHYS        96
%define PNG_SBIT        104
%define PNG_IDAT_BUF    112
%define PNG_IDAT_LEN    120
%define PNG_IDAT_CAP    128
%define PNG_ARENA       136
%define PNG_PIXBUF      144
%define PNG_SIZE        152

; Decoder state
%define PNGDEC_STATE      0
%define PNGDEC_BYTE_POS   4
%define PNGDEC_BIT_BUFFER 8
%define PNGDEC_BIT_COUNT  12
%define PNGDEC_LIT_TAB    16
%define PNGDEC_DIST_TAB   24
%define PNGDEC_SIZE       32

%define PNGDEC_STATE_HEADER   0
%define PNGDEC_STATE_CHUNK    1
%define PNGDEC_STATE_IDAT     2
%define PNGDEC_STATE_IEND     3
%define PNGDEC_STATE_ERROR    4

%endif ; __PNG_INC__